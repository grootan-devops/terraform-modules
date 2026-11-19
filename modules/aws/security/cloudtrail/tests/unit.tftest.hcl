mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "eu-west-1"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_data "aws_organizations_organization" {
    defaults = {
      id = "o-a1b2c3d4e5"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/platform-prod-trail-logs-eu-west-1"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-west-1:123456789012:log-group:/aws/cloudtrail/platform-prod"
    }
  }

  mock_resource "aws_cloudtrail" {
    defaults = {
      arn = "arn:aws:cloudtrail:eu-west-1:123456789012:trail/platform-prod"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::platform-prod-cloudtrail-123456789012-eu-west-1"
    }
  }
}

variables {
  environment = "prod"
  tags        = { Team = "security" }
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = aws_cloudtrail.this[0].name == "platform-prod" && aws_cloudtrail.this[0].s3_bucket_name == "platform-prod-cloudtrail-123456789012-eu-west-1" && aws_cloudtrail.this[0].s3_key_prefix == null
    error_message = "Trail <application>-<environment> writes to the module bucket <base>-cloudtrail-<account>-<region>."
  }

  assert {
    condition     = aws_cloudtrail.this[0].is_multi_region_trail && aws_cloudtrail.this[0].include_global_service_events && aws_cloudtrail.this[0].enable_log_file_validation && aws_cloudtrail.this[0].enable_logging && aws_cloudtrail.this[0].is_organization_trail
    error_message = "Organization trail: multi-Region, global events, log file validation, logging on (CloudTrail.3, CloudTrail.4)."
  }

  assert {
    condition     = length(aws_cloudtrail.this[0].advanced_event_selector) == 1 && aws_cloudtrail.this[0].advanced_event_selector[0].name == "Management events" && [for f in aws_cloudtrail.this[0].advanced_event_selector[0].field_selector : f.field] == ["eventCategory"] && length(aws_cloudtrail.this[0].insight_selector) == 0
    error_message = "Read and write management events only, no Insights by default (CloudTrail.1)."
  }

  assert {
    condition     = module.encryption.created && module.log_group[0].name == "/aws/cloudtrail/platform-prod" && module.log_group[0].retention_in_days == 365 && length(module.role) == 1
    error_message = "Module key, 365-day log group and delivery role by default (CloudTrail.5)."
  }

  assert {
    condition     = aws_cloudtrail.this[0].tags["Name"] == "platform-prod" && aws_cloudtrail.this[0].tags["Application"] == "platform" && aws_cloudtrail.this[0].tags["Team"] == "security" && aws_cloudtrail.this[0].tags["ManagedBy"] == "Terraform"
    error_message = "Caller and governance tags; application defaults to platform (CloudTrail.9)."
  }

  assert {
    condition     = length(aws_organizations_aws_service_access.this) + length(aws_cloudtrail_organization_delegated_admin_account.this) == 0
    error_message = "No organization resources by default."
  }

  assert {
    condition     = length(module.bucket) == 1 && !local.bucket_object_lock.enabled && !var.bucket.access_logs.enabled && [for r in local.bucket_lifecycle_rules : r.id] == ["cloudtrail-log-retention"]
    error_message = "storage/s3 bucket; Object Lock and access logs are opt-in; the lifecycle rule is on."
  }
}

run "bucket_hardening" {
  command = plan

  assert {
    condition     = module.bucket[0].name == "platform-prod-cloudtrail-123456789012-eu-west-1" && output.bucket_name == module.bucket[0].name
    error_message = "storage/s3 bucket with a globally unique name."
  }

  assert {
    condition     = [for s in jsondecode(module.bucket[0].policy_json).Statement : s.Sid] == ["DenyInsecureTransport", "DenyOutdatedTls", "AWSCloudTrailAclCheck", "AWSCloudTrailWrite", "AWSCloudTrailOrganizationWrite"]
    error_message = "TLS guards from storage/s3 come first, then the CloudTrail grants (S3.5)."
  }

  assert {
    condition     = local.bucket_lifecycle_rules[0].expiration_days == 2557 && local.bucket_lifecycle_rules[0].noncurrent_version_expiration_days == 365 && [for tr in local.bucket_lifecycle_rules[0].transitions : tr.storage_class] == ["GLACIER", "DEEP_ARCHIVE"]
    error_message = "Logs move to Glacier and Deep Archive and expire after 7 years."
  }
}

run "bucket_policy_grants_trail_and_enforces_tls" {
  command = plan

  variables {
    bucket = {
      key_prefix = "/audit/"
      policy_statements = [{
        sid        = "ReadLogs"
        actions    = ["s3:GetObject"]
        principals = { AWS = ["arn:aws:iam::123456789012:role/auditor"] }
      }]
    }
  }

  assert {
    condition     = [for s in jsondecode(module.bucket[0].policy_json).Statement : s.Sid] == ["DenyInsecureTransport", "DenyOutdatedTls", "AWSCloudTrailAclCheck", "AWSCloudTrailWrite", "AWSCloudTrailOrganizationWrite", "ReadLogs"]
    error_message = "TLS denies and CloudTrail grants come first, caller statements last."
  }

  assert {
    condition     = jsondecode(module.bucket[0].policy_json).Statement[3].Resource == ["arn:aws:s3:::platform-prod-cloudtrail-123456789012-eu-west-1/audit/AWSLogs/123456789012/*"] && jsondecode(module.bucket[0].policy_json).Statement[4].Resource == ["arn:aws:s3:::platform-prod-cloudtrail-123456789012-eu-west-1/audit/AWSLogs/o-a1b2c3d4e5/*"]
    error_message = "Writes are limited to AWSLogs/<account> and AWSLogs/<organization> under the prefix."
  }

  assert {
    condition     = jsondecode(module.bucket[0].policy_json).Statement[3].Condition.StringEquals["aws:SourceArn"] == ["arn:aws:cloudtrail:eu-west-1:123456789012:trail/platform-prod"] && jsondecode(module.bucket[0].policy_json).Statement[3].Condition.StringEquals["s3:x-amz-acl"] == ["bucket-owner-full-control"] && jsondecode(module.bucket[0].policy_json).Statement[2].Principal.Service == ["cloudtrail.amazonaws.com"]
    error_message = "Writes need aws:SourceArn = the trail and bucket-owner-full-control."
  }

  assert {
    condition     = jsondecode(module.bucket[0].policy_json).Statement[0].Condition.Bool["aws:SecureTransport"] == ["false"] && jsondecode(module.bucket[0].policy_json).Statement[1].Condition.NumericLessThan["s3:TlsVersion"] == ["1.2"]
    error_message = "Plain HTTP and TLS below 1.2 are denied (S3.5)."
  }

  assert {
    condition     = jsondecode(module.bucket[0].policy_json).Statement[5].Resource == ["arn:aws:s3:::platform-prod-cloudtrail-123456789012-eu-west-1", "arn:aws:s3:::platform-prod-cloudtrail-123456789012-eu-west-1/*"] && aws_cloudtrail.this[0].s3_key_prefix == "audit"
    error_message = "Caller statements default to the bucket and its objects; the key prefix is trimmed."
  }
}

run "module_key_is_planned_safely" {
  command = plan

  variables {
    kms = { create = true }
  }

  assert {
    condition     = length(module.encryption.created ? [1] : []) == 1
    error_message = "kms.create must plan without knowing the key ARN."
  }
}

run "module_key_encrypts_trail_bucket_and_logs" {
  command = apply

  assert {
    condition     = aws_cloudtrail.this[0].kms_key_id == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && output.kms_key_arn == aws_cloudtrail.this[0].kms_key_id
    error_message = "The module key must encrypt the trail (CloudTrail.2)."
  }

  assert {
    condition     = module.bucket[0].kms_key_arn == output.kms_key_arn && module.log_group[0].kms_key_arn == output.kms_key_arn
    error_message = "The module key must encrypt the bucket and the log group."
  }

  assert {
    condition     = aws_cloudtrail.this[0].cloud_watch_logs_group_arn == "arn:aws:logs:eu-west-1:123456789012:log-group:/aws/cloudtrail/platform-prod:*" && aws_cloudtrail.this[0].cloud_watch_logs_role_arn == "arn:aws:iam::123456789012:role/platform-prod-trail-logs-eu-west-1"
    error_message = "The trail must deliver to the module log group through the delivery role."
  }

  assert {
    condition     = output.arn == "arn:aws:cloudtrail:eu-west-1:123456789012:trail/platform-prod" && output.name == "platform-prod" && output.bucket_arn == "arn:aws:s3:::platform-prod-cloudtrail-123456789012-eu-west-1" && output.role_arn == aws_cloudtrail.this[0].cloud_watch_logs_role_arn && output.role_name == "platform-prod-trail-logs-eu-west-1"
    error_message = "Outputs must expose the trail, bucket and role."
  }
}

run "key_policy_statements" {
  command = plan

  assert {
    condition     = [for s in jsondecode(output.kms_key_policy_json).Statement : s.Sid] == ["AllowCloudTrailEncryptLogs", "AllowCloudTrailDescribeKey", "AllowCloudWatchLogs", "AllowCloudTrailLogDecrypt"]
    error_message = "The key policy must grant CloudTrail, CloudWatch Logs and log readers in this account."
  }

  assert {
    condition     = jsondecode(output.kms_key_policy_json).Statement[0].Condition.StringEquals["aws:SourceArn"] == ["arn:aws:cloudtrail:eu-west-1:123456789012:trail/platform-prod"] && jsondecode(output.kms_key_policy_json).Statement[0].Condition.StringLike["kms:EncryptionContext:aws:cloudtrail:arn"] == ["arn:aws:cloudtrail:*:123456789012:trail/*"]
    error_message = "CloudTrail may encrypt only for this trail (confused deputy)."
  }

  assert {
    condition     = jsondecode(output.kms_key_policy_json).Statement[2].Principal.Service == ["logs.eu-west-1.amazonaws.com"] && jsondecode(output.kms_key_policy_json).Statement[2].Condition.ArnEquals["kms:EncryptionContext:aws:logs:arn"] == ["arn:aws:logs:eu-west-1:123456789012:log-group:/aws/cloudtrail/platform-prod"]
    error_message = "CloudWatch Logs may use the key only for the trail log group."
  }
}

run "caller_key_id_and_log_overrides" {
  command = plan

  variables {
    kms             = { create = false, key_id = "11111111-2222-3333-4444-555555555555" }
    cloudwatch_logs = { kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/99999999-2222-3333-4444-555555555555", retention_in_days = 731, log_group_class = "INFREQUENT_ACCESS", deletion_protection_enabled = false }
  }

  assert {
    condition     = !module.encryption.created && aws_cloudtrail.this[0].kms_key_id == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && module.bucket[0].kms_key_arn == aws_cloudtrail.this[0].kms_key_id
    error_message = "A key ID must be used as the key ARN for the trail and the bucket."
  }

  assert {
    condition     = module.log_group[0].kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/99999999-2222-3333-4444-555555555555" && module.log_group[0].retention_in_days == 731
    error_message = "cloudwatch_logs must override the log key and retention."
  }
}

run "delivery_role" {
  command = plan

  variables {
    iam_role = {
      permissions_boundary_arn = "arn:aws:iam::123456789012:policy/boundary"
      policy_statements        = [{ sid = "Extra", actions = ["logs:DescribeLogGroups"], resources = ["*"] }]
    }
  }

  assert {
    condition     = module.role[0].name == "platform-prod-trail-logs-eu-west-1"
    error_message = "The role must be <application>-<environment>-trail-logs-<region>."
  }

  assert {
    condition     = jsondecode(module.role[0].trust_policy_json).Statement[0].Principal.Service == ["cloudtrail.amazonaws.com"]
    error_message = "Only CloudTrail may assume the delivery role."
  }

  assert {
    condition     = [for s in jsondecode(module.role[0].policy_json).Statement : s.Sid] == ["DeliverToLogGroup", "Extra"] && jsondecode(module.role[0].policy_json).Statement[0].Resource == ["arn:aws:logs:eu-west-1:123456789012:log-group:/aws/cloudtrail/platform-prod:log-stream:*"] && jsondecode(module.role[0].policy_json).Statement[0].Action == ["logs:CreateLogStream", "logs:PutLogEvents"]
    error_message = "The role may only write to its log group; caller statements are added."
  }
}

run "caller_delivery_role" {
  command = plan

  variables {
    iam_role = { create = false, arn = "arn:aws:iam::123456789012:role/trail-delivery" }
  }

  assert {
    condition     = length(module.role) == 0 && aws_cloudtrail.this[0].cloud_watch_logs_role_arn == "arn:aws:iam::123456789012:role/trail-delivery" && output.role_name == null
    error_message = "A caller role must be used as is."
  }
}

run "cloudwatch_logs_disabled" {
  command = plan

  variables {
    cloudwatch_logs = { enabled = false }
  }

  assert {
    condition     = length(module.log_group) + length(module.role) == 0 && aws_cloudtrail.this[0].cloud_watch_logs_group_arn == null && aws_cloudtrail.this[0].cloud_watch_logs_role_arn == null && output.log_group_name == null && output.role_arn == null
    error_message = "No log group, role or delivery without CloudWatch Logs."
  }

  assert {
    condition     = !contains([for s in jsondecode(output.kms_key_policy_json).Statement : s.Sid], "AllowCloudWatchLogs")
    error_message = "No CloudWatch Logs key grant without a log group."
  }
}

run "event_selectors" {
  command = plan

  variables {
    trail = {
      exclude_management_event_sources = ["kms.amazonaws.com"]
      data_events = {
        s3_objects       = { enabled = true, bucket_arns = ["arn:aws:s3:::orders"], read_write_type = "WriteOnly" }
        lambda_functions = { enabled = true }
        dynamodb_tables  = { enabled = true, table_arns = ["arn:aws:dynamodb:eu-west-1:123456789012:table/orders"], read_write_type = "ReadOnly" }
      }
      insight_types = ["ApiCallRateInsight", "ApiErrorRateInsight"]
    }
  }

  assert {
    condition     = [for s in aws_cloudtrail.this[0].advanced_event_selector : s.name] == ["Management events", "S3 object data events", "Lambda function data events", "DynamoDB table data events"]
    error_message = "One selector per enabled data event type after the management selector."
  }

  assert {
    condition     = contains([for f in aws_cloudtrail.this[0].advanced_event_selector[0].field_selector : f.field], "eventSource") && one([for f in aws_cloudtrail.this[0].advanced_event_selector[0].field_selector : f.not_equals if f.field == "eventSource"]) == tolist(["kms.amazonaws.com"])
    error_message = "Excluded management event sources use not_equals."
  }

  assert {
    condition     = one([for f in aws_cloudtrail.this[0].advanced_event_selector[1].field_selector : f.starts_with if f.field == "resources.ARN"]) == tolist(["arn:aws:s3:::orders/"]) && one([for f in aws_cloudtrail.this[0].advanced_event_selector[1].field_selector : f.equals if f.field == "readOnly"]) == tolist(["false"])
    error_message = "S3 data events are scoped to the listed buckets and write-only."
  }

  assert {
    condition     = length(aws_cloudtrail.this[0].advanced_event_selector[2].field_selector) == 2 && one([for f in aws_cloudtrail.this[0].advanced_event_selector[3].field_selector : f.equals if f.field == "readOnly"]) == tolist(["true"])
    error_message = "Lambda without ARNs logs every function; DynamoDB is read-only."
  }

  assert {
    condition     = length(aws_cloudtrail.this[0].insight_selector) == 2
    error_message = "Insights must be enabled when requested."
  }
}

run "account_trail" {
  command = plan

  variables {
    trail = { is_organization_trail = false }
  }

  assert {
    condition     = !aws_cloudtrail.this[0].is_organization_trail && length(data.aws_organizations_organization.this) == 0 && !contains([for s in jsondecode(module.bucket[0].policy_json).Statement : s.Sid], "AWSCloudTrailOrganizationWrite")
    error_message = "An account trail needs no organization lookup or organization write grant."
  }
}

run "trail_from_delegated_administrator" {
  command = plan

  variables {
    trail = { management_account_id = "999999999999" }
  }

  assert {
    condition     = jsondecode(module.bucket[0].policy_json).Statement[3].Resource == ["arn:aws:s3:::platform-prod-cloudtrail-123456789012-eu-west-1/AWSLogs/999999999999/*"] && jsondecode(module.bucket[0].policy_json).Statement[3].Condition.StringEquals["aws:SourceArn"] == ["arn:aws:cloudtrail:eu-west-1:999999999999:trail/platform-prod"]
    error_message = "An organization trail is owned by the management account."
  }
}

run "bucket_lifecycle_object_lock_and_access_logs" {
  command = plan

  variables {
    bucket = {
      name        = "audit-trail-logs"
      lifecycle   = { transition_to_glacier_days = 0, expiration_days = 3653 }
      object_lock = { enabled = true, mode = "COMPLIANCE", days = 2557 }
      access_logs = { enabled = true, bucket = "s3-access-logs" }
    }
  }

  assert {
    condition     = module.bucket[0].name == "audit-trail-logs" && aws_cloudtrail.this[0].s3_bucket_name == "audit-trail-logs"
    error_message = "bucket.name overrides the derived name."
  }

  assert {
    condition     = [for tr in local.bucket_lifecycle_rules[0].transitions : tr.storage_class] == ["DEEP_ARCHIVE"] && local.bucket_lifecycle_rules[0].expiration_days == 3653 && local.bucket_lifecycle_rules[0].noncurrent_version_expiration_days == 365
    error_message = "Lifecycle overrides must flow through; 0 turns a transition off."
  }

  assert {
    condition     = local.bucket_object_lock == { enabled = true, mode = "COMPLIANCE", days = 2557 }
    error_message = "Object Lock default retention when enabled (S3.15)."
  }

  assert {
    condition     = var.bucket.access_logs.enabled && var.bucket.access_logs.bucket == "s3-access-logs"
    error_message = "Access logs go to the target bucket (CloudTrail.7, S3.9)."
  }
}

run "lifecycle_off" {
  command = plan

  variables {
    bucket = { lifecycle = { transition_to_glacier_days = 0, transition_to_deep_archive_days = 0, expiration_days = 0, noncurrent_expiration_days = 0 } }
  }

  assert {
    condition     = length(local.bucket_lifecycle_rules) == 0
    error_message = "No retention rule when every action is 0; storage/s3 still aborts incomplete uploads."
  }
}

run "existing_bucket" {
  command = plan

  variables {
    bucket = { enabled = false, name = "central-trail-logs" }
  }

  assert {
    condition     = length(module.bucket) + length(data.aws_organizations_organization.this) == 0 && aws_cloudtrail.this[0].s3_bucket_name == "central-trail-logs"
    error_message = "With bucket.enabled = false the trail writes to the named bucket."
  }

  assert {
    condition     = output.bucket_name == "central-trail-logs" && output.bucket_arn == "arn:aws:s3:::central-trail-logs" && module.encryption.created
    error_message = "Outputs name the existing bucket; the trail keeps its key."
  }
}

run "log_archive_bucket_only" {
  command = plan

  variables {
    trail = { enabled = false }
    bucket = {
      organization_id       = "o-zzzzzzzzzz"
      additional_trail_arns = ["arn:aws:cloudtrail:us-east-1:111111111111:trail/org"]
    }
  }

  assert {
    condition     = length(aws_cloudtrail.this) + length(module.log_group) + length(module.role) + length(data.aws_organizations_organization.this) == 0 && output.arn == null
    error_message = "A bucket-only call creates no trail, log group or role."
  }

  assert {
    condition     = jsondecode(module.bucket[0].policy_json).Statement[3].Resource == ["arn:aws:s3:::platform-prod-cloudtrail-123456789012-eu-west-1/AWSLogs/111111111111/*"] && jsondecode(module.bucket[0].policy_json).Statement[4].Resource == ["arn:aws:s3:::platform-prod-cloudtrail-123456789012-eu-west-1/AWSLogs/o-zzzzzzzzzz/*"] && jsondecode(module.bucket[0].policy_json).Statement[3].Condition.StringEquals["aws:SourceArn"] == ["arn:aws:cloudtrail:us-east-1:111111111111:trail/org"]
    error_message = "Remote trails may write to their account and organization paths."
  }

  assert {
    condition     = module.encryption.created && [for s in jsondecode(output.kms_key_policy_json).Statement : s.Sid] == ["AllowCloudTrailEncryptLogs", "AllowCloudTrailDescribeKey", "AllowCloudTrailLogDecrypt"]
    error_message = "The bucket keeps a module key without a CloudWatch Logs grant."
  }
}

run "organization_admin_only" {
  command = plan

  variables {
    trail              = { enabled = false }
    bucket             = { enabled = false }
    organization_admin = { enabled = true, account_ids = ["222222222222", "333333333333"] }
  }

  assert {
    condition     = !module.encryption.created && output.kms_key_arn == null && output.kms_key_policy_json == null && output.bucket_name == null && output.bucket_arn == null
    error_message = "An organization-only call creates no key or bucket."
  }

  assert {
    condition     = aws_organizations_aws_service_access.this[0].service_principal == "cloudtrail.amazonaws.com" && [for a in aws_cloudtrail_organization_delegated_admin_account.this : a.account_id] == ["222222222222", "333333333333"]
    error_message = "Trusted access and every delegated administrator."
  }
}

run "organization_admin_without_trusted_access" {
  command = plan

  variables {
    organization_admin = { enabled = true, manage_trusted_access = false }
  }

  assert {
    condition     = length(aws_organizations_aws_service_access.this) + length(aws_cloudtrail_organization_delegated_admin_account.this) == 0
    error_message = "manage_trusted_access = false leaves trusted access alone."
  }
}

run "rejects_management_account_as_delegated_admin" {
  command = plan

  variables {
    organization_admin = { enabled = true, account_ids = ["123456789012"] }
  }

  expect_failures = [aws_cloudtrail_organization_delegated_admin_account.this]
}

run "governance_tags_win" {
  command = plan

  variables {
    application = "audit"
    tags        = { Application = "other", ManagedBy = "someone", Team = "security" }
  }

  assert {
    condition     = aws_cloudtrail.this[0].name == "audit-prod" && aws_cloudtrail.this[0].tags["Application"] == "audit" && aws_cloudtrail.this[0].tags["ManagedBy"] == "Terraform"
    error_message = "Governance tags must win over caller tags."
  }
}

run "long_names_are_truncated" {
  command = plan

  variables {
    application = "observability-platform-x"
    environment = "production-e"
  }

  assert {
    condition     = length(module.bucket[0].name) == 63 && startswith(module.bucket[0].name, "observability-platform-x-production-e-cloudtrail-") && can(regex("-[0-9a-f]{6}$", module.bucket[0].name)) && module.bucket[0].name == local.bucket_name
    error_message = "Bucket names longer than 63 characters are cut with a hash."
  }
}

run "rejects_invalid_trail_name" {
  command = plan

  variables {
    application = "core--x"
  }

  expect_failures = [aws_cloudtrail.this]
}

run "rejects_key_in_another_region" {
  command = plan

  variables {
    kms = { create = false, key_id = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555" }
  }

  expect_failures = [aws_cloudtrail.this]
}

run "rejects_invalid_application" {
  command = plan

  variables {
    application = "Platform"
  }

  expect_failures = [var.application]
}

run "rejects_invalid_environment" {
  command = plan

  variables {
    environment = "p"
  }

  expect_failures = [var.environment]
}

run "rejects_key_id_with_create" {
  command = plan

  variables {
    kms = { key_id = "11111111-2222-3333-4444-555555555555" }
  }

  expect_failures = [var.kms]
}

run "rejects_no_key" {
  command = plan

  variables {
    kms = { create = false }
  }

  expect_failures = [var.kms]
}

run "rejects_invalid_key_id" {
  command = plan

  variables {
    kms = { create = false, key_id = "alias/cloudtrail" }
  }

  expect_failures = [var.kms]
}

run "rejects_invalid_management_account_id" {
  command = plan

  variables {
    trail = { management_account_id = "12345" }
  }

  expect_failures = [var.trail]
}

run "rejects_invalid_excluded_source" {
  command = plan

  variables {
    trail = { exclude_management_event_sources = ["s3.amazonaws.com"] }
  }

  expect_failures = [var.trail]
}

run "rejects_invalid_read_write_type" {
  command = plan

  variables {
    trail = { data_events = { s3_objects = { enabled = true, read_write_type = "Write" } } }
  }

  expect_failures = [var.trail]
}

run "rejects_invalid_insight_type" {
  command = plan

  variables {
    trail = { insight_types = ["ApiLatencyInsight"] }
  }

  expect_failures = [var.trail]
}

run "rejects_caller_role_without_arn" {
  command = plan

  variables {
    iam_role = { create = false }
  }

  expect_failures = [var.iam_role]
}

run "rejects_existing_bucket_without_name" {
  command = plan

  variables {
    bucket = { enabled = false }
  }

  expect_failures = [var.bucket]
}

run "rejects_invalid_bucket_name" {
  command = plan

  variables {
    bucket = { name = "Invalid_Bucket" }
  }

  expect_failures = [var.bucket]
}

run "rejects_invalid_organization_id" {
  command = plan

  variables {
    bucket = { organization_id = "org-123" }
  }

  expect_failures = [var.bucket]
}

run "rejects_invalid_additional_trail_arn" {
  command = plan

  variables {
    bucket = { additional_trail_arns = ["arn:aws:s3:::not-a-trail"] }
  }

  expect_failures = [var.bucket]
}

run "rejects_bucket_without_writers" {
  command = plan

  variables {
    trail = { enabled = false }
  }

  expect_failures = [var.bucket]
}

run "rejects_invalid_lifecycle" {
  command = plan

  variables {
    bucket = { lifecycle = { transition_to_glacier_days = 90, transition_to_deep_archive_days = 120 } }
  }

  expect_failures = [var.bucket]
}

run "rejects_invalid_object_lock" {
  command = plan

  variables {
    bucket = { object_lock = { enabled = true, mode = "LEGAL_HOLD" } }
  }

  expect_failures = [var.bucket]
}

run "rejects_access_logs_without_bucket" {
  command = plan

  variables {
    bucket = { access_logs = { enabled = true } }
  }

  expect_failures = [var.bucket]
}

run "rejects_invalid_delegated_admins" {
  command = plan

  variables {
    organization_admin = { enabled = true, account_ids = ["111111111111", "222222222222", "333333333333", "444444444444"] }
  }

  expect_failures = [var.organization_admin]
}

run "rejects_delegated_admins_when_disabled" {
  command = plan

  variables {
    organization_admin = { account_ids = ["222222222222"] }
  }

  expect_failures = [var.organization_admin]
}
