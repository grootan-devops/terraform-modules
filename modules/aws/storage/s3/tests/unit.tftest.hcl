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

  mock_resource "aws_s3_bucket" {
    defaults = {
      id                          = "core-prod-assets-123456789012-eu-west-1"
      arn                         = "arn:aws:s3:::core-prod-assets-123456789012-eu-west-1"
      bucket_domain_name          = "core-prod-assets-123456789012-eu-west-1.s3.amazonaws.com"
      bucket_regional_domain_name = "core-prod-assets-123456789012-eu-west-1.s3.eu-west-1.amazonaws.com"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/core-prod-assets-replication-eu-west-1"
    }
  }
}

variables {
  application = "core"
  environment = "prod"
  name        = "assets"
  tags        = { Team = "platform" }
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = aws_s3_bucket.this.bucket == "core-prod-assets-123456789012-eu-west-1" && output.name == "core-prod-assets-123456789012-eu-west-1"
    error_message = "The bucket must be <application>-<environment>-<name>-<account>-<region>."
  }

  assert {
    condition     = aws_s3_bucket.this.force_destroy == false && aws_s3_bucket.this.object_lock_enabled == false
    error_message = "No force_destroy and no Object Lock by default."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_acls && aws_s3_bucket_public_access_block.this.block_public_policy && aws_s3_bucket_public_access_block.this.ignore_public_acls && aws_s3_bucket_public_access_block.this.restrict_public_buckets
    error_message = "All four public access block settings must be on (S3.8)."
  }

  assert {
    condition     = aws_s3_bucket_ownership_controls.this.rule[0].object_ownership == "BucketOwnerEnforced" && aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "ACLs disabled (S3.12) and versioning on (S3.14)."
  }

  assert {
    condition     = [for r in aws_s3_bucket_server_side_encryption_configuration.this.rule : r.apply_server_side_encryption_by_default[0].sse_algorithm] == ["AES256"] && [for r in aws_s3_bucket_server_side_encryption_configuration.this.rule : r.bucket_key_enabled] == [false]
    error_message = "No kms input means SSE-S3."
  }

  assert {
    condition     = flatten([for r in aws_s3_bucket_server_side_encryption_configuration.this.rule : r.blocked_encryption_types]) == ["SSE-C"] && output.kms_key_arn == null
    error_message = "SSE-C is blocked; no key output for SSE-S3."
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this.rule) == 1 && aws_s3_bucket_lifecycle_configuration.this.rule[0].id == "abort-incomplete-multipart-uploads" && aws_s3_bucket_lifecycle_configuration.this.rule[0].abort_incomplete_multipart_upload[0].days_after_initiation == 7
    error_message = "Only the abort-incomplete-uploads rule by default (S3.13)."
  }

  assert {
    condition     = length(aws_s3_bucket_logging.this) + length(aws_s3_bucket_notification.this) + length(aws_s3_bucket_cors_configuration.this) + length(aws_s3_bucket_object_lock_configuration.this) + length(aws_s3_bucket_replication_configuration.this) + length(module.replication_role) == 0
    error_message = "No logging, notifications, CORS, Object Lock or replication by default."
  }

  assert {
    condition     = aws_s3_bucket.this.tags["Name"] == "core-prod-assets-123456789012-eu-west-1" && aws_s3_bucket.this.tags["Team"] == "platform" && aws_s3_bucket.this.tags["ManagedBy"] == "Terraform"
    error_message = "Caller and governance tags must be applied."
  }
}

run "bucket_policy_guards_and_caller_statements" {
  command = plan

  variables {
    policy_statements = [
      { sid = "ReadObjects", actions = ["s3:GetObject"], principals = { AWS = ["arn:aws:iam::123456789012:role/reader"] } },
      { sid = "WriteUploads", actions = ["s3:PutObject"], resources = ["arn:aws:s3:::core-prod-assets-123456789012-eu-west-1/uploads/*"], principals = { AWS = ["arn:aws:iam::123456789012:role/writer"] } }
    ]
  }

  assert {
    condition     = [for s in jsondecode(output.policy_json).Statement : s.Sid] == ["DenyInsecureTransport", "DenyOutdatedTls", "ReadObjects", "WriteUploads"]
    error_message = "Guard statements come first, then caller statements."
  }

  assert {
    condition     = jsondecode(output.policy_json).Statement[0].Effect == "Deny" && jsondecode(output.policy_json).Statement[0].Condition.Bool["aws:SecureTransport"] == ["false"] && jsondecode(output.policy_json).Statement[1].Condition.NumericLessThan["s3:TlsVersion"] == ["1.2"]
    error_message = "Requests without TLS or below TLS 1.2 must be denied (S3.5)."
  }

  assert {
    condition     = jsondecode(output.policy_json).Statement[0].Resource == ["arn:aws:s3:::core-prod-assets-123456789012-eu-west-1", "arn:aws:s3:::core-prod-assets-123456789012-eu-west-1/*"] && jsondecode(output.policy_json).Statement[2].Resource == jsondecode(output.policy_json).Statement[0].Resource
    error_message = "Statements without resources apply to the bucket and its objects."
  }

  assert {
    condition     = jsondecode(output.policy_json).Statement[3].Resource == ["arn:aws:s3:::core-prod-assets-123456789012-eu-west-1/uploads/*"]
    error_message = "A caller Resource must never be overwritten."
  }
}

run "long_names_are_truncated" {
  command = plan

  variables {
    application = "analytics-platform-core"
    environment = "production1"
    name        = "a-very-long-bucket-name-for-test"
  }

  assert {
    condition     = length(aws_s3_bucket.this.bucket) == 63 && startswith(aws_s3_bucket.this.bucket, "analytics-platform-core-production1-a-very-long-bucket-")
    error_message = "Bucket names are cut to 63 characters with a hash suffix."
  }
}

run "exact_bucket_name" {
  command = plan

  variables {
    bucket_name = "aws-waf-logs-core-prod"
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "aws-waf-logs-core-prod" && aws_s3_bucket.this.tags["Name"] == "aws-waf-logs-core-prod"
    error_message = "bucket_name must be used as is."
  }
}

run "module_key_is_planned_safely" {
  command = plan

  variables {
    kms = { create = true }
    replication = {
      enabled = true
      rules   = [{ id = "dr", destination_bucket_arn = "arn:aws:s3:::core-prod-assets-dr", replica_kms_key_arn = "arn:aws:kms:eu-central-1:123456789012:key/99999999-2222-3333-4444-555555555555" }]
    }
  }

  assert {
    condition     = module.encryption.created && length(module.replication_role) == 1 && length(aws_s3_bucket_replication_configuration.this) == 1
    error_message = "kms.create and replication must plan without knowing the key and role ARNs."
  }

  assert {
    condition     = [for r in aws_s3_bucket_server_side_encryption_configuration.this.rule : r.apply_server_side_encryption_by_default[0].sse_algorithm] == ["aws:kms"] && [for r in aws_s3_bucket_server_side_encryption_configuration.this.rule : r.bucket_key_enabled] == [true]
    error_message = "A KMS key means SSE-KMS with a bucket key."
  }
}

run "module_key_encrypts_bucket" {
  command = apply

  variables {
    kms = { create = true }
  }

  assert {
    condition     = [for r in aws_s3_bucket_server_side_encryption_configuration.this.rule : r.apply_server_side_encryption_by_default[0].kms_master_key_id] == ["arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"] && output.kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    error_message = "The module key must encrypt the bucket."
  }

  assert {
    condition     = output.arn == "arn:aws:s3:::core-prod-assets-123456789012-eu-west-1" && output.regional_domain_name == "core-prod-assets-123456789012-eu-west-1.s3.eu-west-1.amazonaws.com" && output.domain_name == "core-prod-assets-123456789012-eu-west-1.s3.amazonaws.com"
    error_message = "Outputs must expose the bucket ARN and domain names."
  }
}

run "caller_key_id" {
  command = plan

  variables {
    kms = { key_id = "11111111-2222-3333-4444-555555555555" }
  }

  assert {
    condition     = output.kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && [for r in aws_s3_bucket_server_side_encryption_configuration.this.rule : r.apply_server_side_encryption_by_default[0].sse_algorithm] == ["aws:kms"]
    error_message = "A key ID must become the key ARN and enable SSE-KMS."
  }
}

run "lifecycle_rules" {
  command = plan

  variables {
    abort_incomplete_multipart_upload_days = 3
    noncurrent_version_expiration          = { enabled = true, days = 30, newer_noncurrent_versions = 3 }
    lifecycle_rules = [
      { id = "tmp", prefix = "tmp/", expiration_days = 7 },
      { id = "archive", tags = { class = "archive" }, transitions = [{ days = 30, storage_class = "GLACIER_IR" }] },
      { id = "reports", prefix = "reports/", tags = { keep = "short" }, noncurrent_version_expiration_days = 14, noncurrent_version_transitions = [{ days = 7, storage_class = "STANDARD_IA" }] }
    ]
  }

  assert {
    condition     = [for r in aws_s3_bucket_lifecycle_configuration.this.rule : r.id] == ["abort-incomplete-multipart-uploads", "expire-noncurrent-versions", "tmp", "archive", "reports"] && aws_s3_bucket_lifecycle_configuration.this.rule[0].abort_incomplete_multipart_upload[0].days_after_initiation == 3
    error_message = "Module rules come first, then caller rules."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this.rule[1].noncurrent_version_expiration[0].noncurrent_days == 30 && aws_s3_bucket_lifecycle_configuration.this.rule[1].noncurrent_version_expiration[0].newer_noncurrent_versions == 3
    error_message = "noncurrent_version_expiration must expire old versions (S3.10)."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this.rule[2].filter[0].prefix == "tmp/" && aws_s3_bucket_lifecycle_configuration.this.rule[2].expiration[0].days == 7
    error_message = "A prefix rule filters by prefix."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this.rule[3].filter[0].tag[0].key == "class" && length(aws_s3_bucket_lifecycle_configuration.this.rule[3].filter[0].and) == 0
    error_message = "A single tag uses the tag filter."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this.rule[4].filter[0].and[0].prefix == "reports/" && aws_s3_bucket_lifecycle_configuration.this.rule[4].filter[0].and[0].tags == tomap({ keep = "short" })
    error_message = "Prefix and tags use the and filter."
  }
}

run "access_logs" {
  command = plan

  variables {
    access_logs = { enabled = true, bucket = "core-prod-logs-123456789012-eu-west-1" }
  }

  assert {
    condition     = aws_s3_bucket_logging.this[0].target_bucket == "core-prod-logs-123456789012-eu-west-1" && aws_s3_bucket_logging.this[0].target_prefix == "core-prod-assets-123456789012-eu-west-1/"
    error_message = "Access logs go to the log bucket under <bucket>/ (S3.9)."
  }
}

run "notifications" {
  command = plan

  variables {
    notifications = {
      eventbridge = true
      queues      = { uploads = { arn = "arn:aws:sqs:eu-west-1:123456789012:core-prod-uploads", events = ["s3:ObjectCreated:*"], filter_prefix = "uploads/" } }
      topics      = { deletes = { arn = "arn:aws:sns:eu-west-1:123456789012:core-prod-deletes", events = ["s3:ObjectRemoved:*"] } }
      functions   = { thumbs = { arn = "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-thumbs:live", events = ["s3:ObjectCreated:Put"], filter_suffix = ".jpg" } }
    }
  }

  assert {
    condition     = aws_s3_bucket_notification.this[0].eventbridge && aws_s3_bucket_notification.this[0].queue[0].id == "uploads" && aws_s3_bucket_notification.this[0].queue[0].filter_prefix == "uploads/"
    error_message = "Notifications go to EventBridge and the queue (S3.11)."
  }

  assert {
    condition     = aws_s3_bucket_notification.this[0].topic[0].topic_arn == "arn:aws:sns:eu-west-1:123456789012:core-prod-deletes" && aws_s3_bucket_notification.this[0].lambda_function[0].filter_suffix == ".jpg"
    error_message = "Topic and function targets must be wired."
  }
}

run "eventbridge_only" {
  command = plan

  variables {
    notifications = { eventbridge = true }
  }

  assert {
    condition     = length(aws_s3_bucket_notification.this) == 1 && length(aws_s3_bucket_notification.this[0].queue) == 0
    error_message = "The EventBridge switch alone creates the notification configuration."
  }
}

run "object_lock" {
  command = plan

  variables {
    object_lock = { enabled = true, mode = "GOVERNANCE", days = 30 }
  }

  assert {
    condition     = aws_s3_bucket.this.object_lock_enabled && aws_s3_bucket_object_lock_configuration.this[0].rule[0].default_retention[0].mode == "GOVERNANCE" && aws_s3_bucket_object_lock_configuration.this[0].rule[0].default_retention[0].days == 30
    error_message = "Object Lock must be enabled with the default retention (S3.15)."
  }
}

run "object_lock_without_retention" {
  command = plan

  variables {
    object_lock = { enabled = true }
  }

  assert {
    condition     = aws_s3_bucket.this.object_lock_enabled && length(aws_s3_bucket_object_lock_configuration.this) == 0
    error_message = "Object Lock without a mode sets no default retention."
  }
}

run "cors" {
  command = plan

  variables {
    cors_rules = [{ allowed_methods = ["GET"], allowed_origins = ["https://app.example.com"], max_age_seconds = 300 }]
  }

  assert {
    condition     = length(aws_s3_bucket_cors_configuration.this) == 1 && length(aws_s3_bucket_cors_configuration.this[0].cors_rule) == 1
    error_message = "cors_rules must create the CORS configuration."
  }
}

run "replication_with_module_key" {
  command   = apply
  state_key = "replication"

  variables {
    kms = { create = true }
    replication = {
      enabled = true
      rules = [
        { id = "dr", destination_bucket_arn = "arn:aws:s3:::core-prod-assets-dr", replica_kms_key_arn = "arn:aws:kms:eu-central-1:123456789012:key/99999999-2222-3333-4444-555555555555", replication_time = true },
        { id = "audit", prefix = "audit/", destination_bucket_arn = "arn:aws:s3:::audit-archive", destination_account_id = "210987654321", replica_kms_key_arn = "arn:aws:kms:eu-west-1:210987654321:key/88888888-2222-3333-4444-555555555555", storage_class = "GLACIER_IR" }
      ]
    }
  }

  assert {
    condition     = module.replication_role[0].name == "core-prod-assets-replication-eu-west-1" && output.replication_role_arn == "arn:aws:iam::123456789012:role/core-prod-assets-replication-eu-west-1" && aws_s3_bucket_replication_configuration.this[0].role == output.replication_role_arn
    error_message = "The replication role is <...>-replication-<region> and used by the configuration."
  }

  assert {
    condition     = jsondecode(module.replication_role[0].trust_policy_json).Statement[0].Principal.Service == ["s3.amazonaws.com"] && jsondecode(module.replication_role[0].trust_policy_json).Statement[0].Condition.StringEquals["aws:SourceAccount"] == ["123456789012"] && jsondecode(module.replication_role[0].trust_policy_json).Statement[0].Condition.ArnLike["aws:SourceArn"] == ["arn:aws:s3:::core-prod-assets-123456789012-eu-west-1"]
    error_message = "Only S3 for this bucket may assume the replication role."
  }

  assert {
    condition     = [for s in jsondecode(module.replication_role[0].policy_json).Statement : s.Sid] == ["ReadSourceBucket", "ReadSourceObjects", "ReplicateToDestinations", "DecryptSource", "EncryptReplicas"]
    error_message = "The replication role must get exactly the replication permissions."
  }

  assert {
    condition     = jsondecode(module.replication_role[0].policy_json).Statement[2].Resource == ["arn:aws:s3:::core-prod-assets-dr/*", "arn:aws:s3:::audit-archive/*"] && contains(jsondecode(module.replication_role[0].policy_json).Statement[2].Action, "s3:ObjectOwnerOverrideToBucketOwner")
    error_message = "Replication writes only to the destination buckets."
  }

  assert {
    condition     = jsondecode(module.replication_role[0].policy_json).Statement[3].Resource == ["arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"] && jsondecode(module.replication_role[0].policy_json).Statement[3].Condition.StringEquals["kms:ViaService"] == "s3.eu-west-1.amazonaws.com"
    error_message = "Decrypt is limited to the module key through S3."
  }

  assert {
    condition     = aws_s3_bucket_replication_configuration.this[0].rule[0].priority == 0 && aws_s3_bucket_replication_configuration.this[0].rule[0].destination[0].replication_time[0].status == "Enabled" && aws_s3_bucket_replication_configuration.this[0].rule[0].source_selection_criteria[0].sse_kms_encrypted_objects[0].status == "Enabled"
    error_message = "Rules get a priority, RTC when asked and SSE-KMS objects replicated."
  }

  assert {
    condition     = aws_s3_bucket_replication_configuration.this[0].rule[1].destination[0].access_control_translation[0].owner == "Destination" && aws_s3_bucket_replication_configuration.this[0].rule[1].destination[0].encryption_configuration[0].replica_kms_key_id == "arn:aws:kms:eu-west-1:210987654321:key/88888888-2222-3333-4444-555555555555"
    error_message = "Cross-account rules hand ownership to the destination and use the replica key."
  }
}

run "replication_with_caller_role" {
  command   = plan
  state_key = "replication_byo"

  variables {
    replication = {
      enabled  = true
      rules    = [{ id = "dr", destination_bucket_arn = "arn:aws:s3:::core-prod-assets-dr" }]
      iam_role = { create = false, arn = "arn:aws:iam::123456789012:role/s3-replication" }
    }
  }

  assert {
    condition     = length(module.replication_role) == 0 && aws_s3_bucket_replication_configuration.this[0].role == "arn:aws:iam::123456789012:role/s3-replication" && output.replication_role_arn == "arn:aws:iam::123456789012:role/s3-replication"
    error_message = "A caller role must replace the module role."
  }

  assert {
    condition     = aws_s3_bucket_replication_configuration.this[0].rule[0].source_selection_criteria[0].sse_kms_encrypted_objects[0].status == "Disabled" && length(aws_s3_bucket_replication_configuration.this[0].rule[0].destination[0].encryption_configuration) == 0
    error_message = "SSE-S3 buckets replicate without replica keys."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Assets_Bucket"
  }

  expect_failures = [var.name]
}

run "rejects_invalid_application" {
  command = plan

  variables {
    application = "Core"
  }

  expect_failures = [var.application]
}

run "rejects_invalid_environment" {
  command = plan

  variables {
    environment = "PROD"
  }

  expect_failures = [var.environment]
}

run "rejects_invalid_bucket_name" {
  command = plan

  variables {
    bucket_name = "Invalid_Bucket"
  }

  expect_failures = [var.bucket_name]
}

run "rejects_create_and_key_id" {
  command = plan

  variables {
    kms = { create = true, key_id = "11111111-2222-3333-4444-555555555555" }
  }

  expect_failures = [var.kms]
}

run "rejects_invalid_key_id" {
  command = plan

  variables {
    kms = { key_id = "alias/assets" }
  }

  expect_failures = [var.kms]
}

run "rejects_duplicate_lifecycle_ids" {
  command = plan

  variables {
    lifecycle_rules = [{ id = "a", expiration_days = 1 }, { id = "a", expiration_days = 2 }]
  }

  expect_failures = [var.lifecycle_rules]
}

run "rejects_lifecycle_rule_without_action" {
  command = plan

  variables {
    lifecycle_rules = [{ id = "empty", prefix = "x/" }]
  }

  expect_failures = [var.lifecycle_rules]
}

run "rejects_invalid_transition_class" {
  command = plan

  variables {
    lifecycle_rules = [{ id = "old", transitions = [{ days = 30, storage_class = "COLD" }] }]
  }

  expect_failures = [var.lifecycle_rules]
}

run "rejects_invalid_abort_days" {
  command = plan

  variables {
    abort_incomplete_multipart_upload_days = 0
  }

  expect_failures = [var.abort_incomplete_multipart_upload_days]
}

run "rejects_invalid_noncurrent_days" {
  command = plan

  variables {
    noncurrent_version_expiration = { enabled = true, days = 0 }
  }

  expect_failures = [var.noncurrent_version_expiration]
}

run "rejects_access_logs_without_bucket" {
  command = plan

  variables {
    access_logs = { enabled = true }
  }

  expect_failures = [var.access_logs]
}

run "rejects_invalid_notification_event" {
  command = plan

  variables {
    notifications = { queues = { q = { arn = "arn:aws:sqs:eu-west-1:123456789012:q", events = ["ObjectCreated:*"] } } }
  }

  expect_failures = [var.notifications]
}

run "rejects_invalid_lock_mode" {
  command = plan

  variables {
    object_lock = { enabled = true, mode = "LEGAL", days = 1 }
  }

  expect_failures = [var.object_lock]
}

run "rejects_lock_days_and_years" {
  command = plan

  variables {
    object_lock = { enabled = true, mode = "COMPLIANCE", days = 1, years = 1 }
  }

  expect_failures = [var.object_lock]
}

run "rejects_lock_mode_without_lock" {
  command = plan

  variables {
    object_lock = { mode = "COMPLIANCE", days = 1 }
  }

  expect_failures = [var.object_lock]
}

run "rejects_replication_without_rules" {
  command = plan

  variables {
    replication = { enabled = true }
  }

  expect_failures = [var.replication]
}

run "rejects_replication_role_without_arn" {
  command = plan

  variables {
    replication = { iam_role = { create = false } }
  }

  expect_failures = [var.replication]
}

run "rejects_replication_without_replica_key" {
  command = plan

  variables {
    kms         = { create = true }
    replication = { enabled = true, rules = [{ id = "dr", destination_bucket_arn = "arn:aws:s3:::dr" }] }
  }

  expect_failures = [var.replication]
}

run "rejects_invalid_replication_storage_class" {
  command = plan

  variables {
    replication = { enabled = true, rules = [{ id = "dr", destination_bucket_arn = "arn:aws:s3:::dr", storage_class = "COLD" }] }
  }

  expect_failures = [var.replication]
}

run "alarms_by_default" {
  command = plan

  assert {
    condition     = length(module.alarms) == 1 && length(output.alarm_names) == 0 && length(module.alarms[0].alarm_settings) == 0
    error_message = "No default alarms: bucket size needs a threshold."
  }
}

run "alarms_off" {
  command = plan

  variables {
    alarms = { enabled = false, overrides = { bucket_size = { threshold = 1099511627776 } } }
  }

  assert {
    condition     = length(module.alarms) == 0 && length(output.alarm_names) == 0 && length(output.alarm_arns) == 0
    error_message = "alarms.enabled = false creates no alarms."
  }
}

run "alarms_tuned_and_routed" {
  command = apply

  variables {
    alarms = {
      topic_arns = {
        critical = "arn:aws:sns:eu-west-1:123456789012:platform-prod-critical"
        warning  = "arn:aws:sns:eu-west-1:123456789012:platform-prod-warning"
        info     = "arn:aws:sns:eu-west-1:123456789012:platform-prod-info"
      }
      overrides = {
        bucket_size = { threshold = 1099511627776 }
      }
    }
  }

  assert {
    condition     = sort(keys(output.alarm_arns)) == tolist(["s3-bucket-bucket-size"]) && alltrue([for n in values(output.alarm_names) : startswith(n, "core-prod-assets-s3-bucket-")])
    error_message = "A threshold turns on the bucket size alarm; names start with the module base name."
  }

  assert {
    condition     = module.alarms[0].alarm_settings["s3-bucket-bucket-size"].threshold == 1099511627776 && module.alarms[0].alarm_settings["s3-bucket-bucket-size"].period == 86400 && module.alarms[0].alarm_settings["s3-bucket-bucket-size"].evaluation_periods == 1
    error_message = "The threshold is set; the rest keep the preset defaults."
  }

  assert {
    condition     = module.alarms[0].alarm_routes["s3-bucket-bucket-size"].topic_arn == "arn:aws:sns:eu-west-1:123456789012:platform-prod-info"
    error_message = "Each alarm notifies the topic for its severity."
  }
}

run "alarms_bucket_size_disabled" {
  command = plan

  variables {
    alarms = { overrides = { bucket_size = { threshold = 1099511627776, enabled = false } } }
  }

  assert {
    condition     = length(output.alarm_names) == 0
    error_message = "enabled = false wins over a threshold."
  }
}

run "alarms_plan_with_unknown_arns" {
  command = plan

  variables {
    kms    = { create = true }
    alarms = { overrides = { bucket_size = { threshold = 1099511627776 } } }
  }

  assert {
    condition     = length(module.alarms) == 1 && sort(keys(output.alarm_names)) == tolist(["s3-bucket-bucket-size"])
    error_message = "Alarm keys and names must be known at plan with a module key."
  }
}

run "rejects_invalid_alarm_topic" {
  command = plan

  variables {
    alarms = { topic_arns = { critical = "arn:aws:sqs:eu-west-1:123456789012:core-prod-critical" } }
  }

  expect_failures = [var.alarms]
}
