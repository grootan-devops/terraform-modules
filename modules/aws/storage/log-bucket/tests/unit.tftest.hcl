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
      arn                = "arn:aws:s3:::core-prod-logs-123456789012-eu-west-1"
      bucket_domain_name = "core-prod-logs-123456789012-eu-west-1.s3.amazonaws.com"
    }
  }
}

variables {
  application = "core"
  environment = "prod"
  name        = "logs"
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = output.name == "core-prod-logs-123456789012-eu-west-1" && module.bucket.kms_key_arn == null
    error_message = "The log bucket is <application>-<environment>-<name>-<account>-<region> with SSE-S3."
  }

  assert {
    condition     = [for s in jsondecode(module.bucket.policy_json).Statement : s.Sid] == ["DenyInsecureTransport", "DenyOutdatedTls", "S3ServerAccessLogs"]
    error_message = "By default only S3 server access logs may be delivered, after the TLS guards."
  }

  assert {
    condition     = jsondecode(module.bucket.policy_json).Statement[2].Principal.Service == ["logging.s3.amazonaws.com"] && jsondecode(module.bucket.policy_json).Statement[2].Resource == ["arn:aws:s3:::core-prod-logs-123456789012-eu-west-1/*"] && jsondecode(module.bucket.policy_json).Statement[2].Condition.StringEquals["aws:SourceAccount"] == ["123456789012"]
    error_message = "S3 server access logs are limited to this account."
  }

  assert {
    condition     = local.policy_statements[0].actions == ["s3:PutObject"] && length(local.policy_statements) == 1
    error_message = "Only PutObject is granted to the S3 logging service."
  }
}

run "lifecycle_defaults" {
  command = plan

  variables {
    transitions = [{ days = 90, storage_class = "GLACIER_IR" }]
  }

  assert {
    condition     = local.lifecycle_rules[0].expiration_days == 365 && local.lifecycle_rules[0].transitions[0].storage_class == "GLACIER_IR" && local.noncurrent_version_expiration.enabled && local.noncurrent_version_expiration.days == 30
    error_message = "Logs expire after 365 days and old versions after 30."
  }
}

run "all_log_types" {
  command = apply

  variables {
    s3_access_logs = { source_bucket_arns = ["arn:aws:s3:::core-prod-assets-123456789012-eu-west-1"] }
    elb_logs       = { enabled = true, prefix = "alb" }
    vended_logs    = { enabled = true }
  }

  assert {
    condition     = [for s in jsondecode(module.bucket.policy_json).Statement : s.Sid] == ["DenyInsecureTransport", "DenyOutdatedTls", "S3ServerAccessLogs", "ElbLogDelivery", "ElbLegacyLogDelivery", "VendedLogDeliveryWrite", "VendedLogDeliveryCheck"]
    error_message = "Every enabled log type gets its statements."
  }

  assert {
    condition     = jsondecode(module.bucket.policy_json).Statement[2].Condition.ArnLike["aws:SourceArn"] == ["arn:aws:s3:::core-prod-assets-123456789012-eu-west-1"]
    error_message = "source_bucket_arns limit the S3 log sources."
  }

  assert {
    condition     = jsondecode(module.bucket.policy_json).Statement[3].Principal.Service == ["logdelivery.elasticloadbalancing.amazonaws.com"] && jsondecode(module.bucket.policy_json).Statement[3].Resource == ["arn:aws:s3:::core-prod-logs-123456789012-eu-west-1/alb/AWSLogs/123456789012/*"]
    error_message = "ELB logs go under <prefix>/AWSLogs/<account>/."
  }

  assert {
    condition     = jsondecode(module.bucket.policy_json).Statement[4].Principal.AWS == ["arn:aws:iam::156460612806:root"] && jsondecode(module.bucket.policy_json).Statement[4].Resource == jsondecode(module.bucket.policy_json).Statement[3].Resource
    error_message = "eu-west-1 also gets the regional ELB account."
  }

  assert {
    condition     = jsondecode(module.bucket.policy_json).Statement[5].Principal.Service == ["delivery.logs.amazonaws.com"] && jsondecode(module.bucket.policy_json).Statement[5].Condition.StringEquals["s3:x-amz-acl"] == ["bucket-owner-full-control"] && jsondecode(module.bucket.policy_json).Statement[5].Condition.ArnLike["aws:SourceArn"] == ["arn:aws:logs:*:123456789012:*"]
    error_message = "Vended logs need the owner ACL and come from this account's log deliveries."
  }

  assert {
    condition     = jsondecode(module.bucket.policy_json).Statement[6].Action == ["s3:GetBucketAcl", "s3:ListBucket"] && jsondecode(module.bucket.policy_json).Statement[6].Resource == ["arn:aws:s3:::core-prod-logs-123456789012-eu-west-1"]
    error_message = "The vended log check reads only the bucket."
  }

  assert {
    condition     = output.arn == "arn:aws:s3:::core-prod-logs-123456789012-eu-west-1" && output.domain_name == "core-prod-logs-123456789012-eu-west-1.s3.amazonaws.com"
    error_message = "Outputs pass the bucket through."
  }
}

run "central_log_bucket" {
  command = plan

  variables {
    source_account_ids = ["111111111111", "222222222222"]
    s3_access_logs     = { enabled = false }
    elb_logs           = { enabled = true }
    vended_logs        = { enabled = true, source_arns = ["arn:aws:logs:us-east-1:111111111111:delivery-source:*"] }
  }

  assert {
    condition     = [for s in jsondecode(module.bucket.policy_json).Statement : s.Sid] == ["DenyInsecureTransport", "DenyOutdatedTls", "ElbLogDelivery", "ElbLegacyLogDelivery", "VendedLogDeliveryWrite", "VendedLogDeliveryCheck"]
    error_message = "Switches must turn log types off."
  }

  assert {
    condition     = jsondecode(module.bucket.policy_json).Statement[2].Resource == ["arn:aws:s3:::core-prod-logs-123456789012-eu-west-1/AWSLogs/111111111111/*", "arn:aws:s3:::core-prod-logs-123456789012-eu-west-1/AWSLogs/222222222222/*"]
    error_message = "ELB logs are allowed per source account."
  }

  assert {
    condition     = jsondecode(module.bucket.policy_json).Statement[4].Condition.StringEquals["aws:SourceAccount"] == ["111111111111", "222222222222"] && jsondecode(module.bucket.policy_json).Statement[4].Condition.ArnLike["aws:SourceArn"] == ["arn:aws:logs:us-east-1:111111111111:delivery-source:*"]
    error_message = "source_account_ids and source_arns scope vended logs."
  }
}

run "exact_name_and_own_access_logs" {
  command = plan

  variables {
    bucket_name = "aws-waf-logs-core-prod"
    access_logs = { enabled = true, bucket = "core-prod-audit-logs" }
  }

  assert {
    condition     = output.name == "aws-waf-logs-core-prod"
    error_message = "bucket_name must be used as is."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Logs_Bucket"
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
    bucket_name = "Logs"
  }

  expect_failures = [var.bucket_name]
}

run "rejects_invalid_source_account" {
  command = plan

  variables {
    source_account_ids = ["1234"]
  }

  expect_failures = [var.source_account_ids]
}

run "rejects_invalid_expiration" {
  command = plan

  variables {
    expiration_days = 0
  }

  expect_failures = [var.expiration_days]
}

run "rejects_invalid_noncurrent_expiration" {
  command = plan

  variables {
    noncurrent_version_expiration_days = 0
  }

  expect_failures = [var.noncurrent_version_expiration_days]
}

run "rejects_invalid_transition" {
  command = plan

  variables {
    transitions = [{ days = 30, storage_class = "COLD" }]
  }

  expect_failures = [var.transitions]
}

run "rejects_invalid_elb_prefix" {
  command = plan

  variables {
    elb_logs = { enabled = true, prefix = "alb/AWSLogs" }
  }

  expect_failures = [var.elb_logs]
}

run "rejects_access_logs_without_bucket" {
  command = plan

  variables {
    access_logs = { enabled = true }
  }

  expect_failures = [var.access_logs]
}
