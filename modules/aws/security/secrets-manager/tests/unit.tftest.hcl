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

  mock_resource "aws_secretsmanager_secret" {
    defaults = {
      arn = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:core-prod-db-AbCdEf"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:eu-west-1:123456789012:key/mrk-0123456789abcdef0123456789abcdef"
    }
  }

  mock_resource "aws_kms_replica_key" {
    defaults = {
      arn = "arn:aws:kms:eu-central-1:123456789012:key/mrk-0123456789abcdef0123456789abcdef"
    }
  }
}

variables {
  application = "core"
  environment = "prod"
  name        = "db"
  tags        = { Team = "data" }
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = aws_secretsmanager_secret.this.name == "core-prod-db" && aws_secretsmanager_secret.this.description == "core-prod-db secret" && output.name == "core-prod-db"
    error_message = "The secret is <application>-<environment>-<name>."
  }

  assert {
    condition     = aws_secretsmanager_secret.this.kms_key_id == null && output.kms_key_arn == null && aws_secretsmanager_secret.this.recovery_window_in_days == 30
    error_message = "No kms input means aws/secretsmanager; 30-day recovery window."
  }

  assert {
    condition     = length(aws_secretsmanager_secret_version.this) + length(aws_secretsmanager_secret_policy.this) + length(aws_secretsmanager_secret_rotation.this) + length(aws_secretsmanager_secret.this.replica) == 0 && output.version_id == null
    error_message = "No value, policy, rotation or replica by default."
  }

  assert {
    condition     = aws_secretsmanager_secret.this.tags["Name"] == "core-prod-db" && aws_secretsmanager_secret.this.tags["Team"] == "data" && aws_secretsmanager_secret.this.tags["ManagedBy"] == "Terraform"
    error_message = "Caller and governance tags must be applied (SecretsManager.5)."
  }
}

run "module_key_is_planned_safely" {
  command = plan

  variables {
    kms             = { create = true }
    replica_regions = { eu-central-1 = {} }
  }

  assert {
    condition     = length(module.key) == 1 && module.encryption.created == false && length(aws_secretsmanager_secret.this.replica) == 1
    error_message = "kms.create with replicas must plan a multi-Region key without knowing its ARN."
  }
}

run "module_key_encrypts_secret" {
  command = apply

  variables {
    kms = { create = true }
  }

  assert {
    condition     = module.encryption.created && length(module.key) == 0 && aws_secretsmanager_secret.this.kms_key_id == "arn:aws:kms:eu-west-1:123456789012:key/mrk-0123456789abcdef0123456789abcdef" && output.kms_key_arn == aws_secretsmanager_secret.this.kms_key_id
    error_message = "Without replicas the module key comes from core/encryption."
  }
}

run "module_key_replicated" {
  command   = apply
  state_key = "replicas"

  variables {
    kms = { create = true }
    replica_regions = {
      eu-central-1 = {}
      us-east-1    = { kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/22222222-2222-3333-4444-555555555555" }
    }
  }

  assert {
    condition     = output.kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/mrk-0123456789abcdef0123456789abcdef" && toset(keys(module.key[0].replica_arns)) == toset(["eu-central-1", "us-east-1"])
    error_message = "The module key is multi-Region and replicated to every replica Region."
  }

  assert {
    condition     = { for r in aws_secretsmanager_secret.this.replica : r.region => r.kms_key_id } == { "eu-central-1" = "arn:aws:kms:eu-central-1:123456789012:key/mrk-0123456789abcdef0123456789abcdef", "us-east-1" = "arn:aws:kms:us-east-1:123456789012:key/22222222-2222-3333-4444-555555555555" }
    error_message = "Replicas use the key replica unless a Region key is given."
  }
}

run "caller_key_with_region_keys" {
  command = plan

  variables {
    kms             = { key_id = "11111111-2222-3333-4444-555555555555" }
    replica_regions = { eu-central-1 = { kms_key_arn = "arn:aws:kms:eu-central-1:123456789012:key/33333333-2222-3333-4444-555555555555" } }
  }

  assert {
    condition     = aws_secretsmanager_secret.this.kms_key_id == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && length(module.key) == 0
    error_message = "A key ID must be used as the key ARN."
  }
}

run "default_key_replicas" {
  command = plan

  variables {
    replica_regions = { eu-central-1 = {} }
  }

  assert {
    condition     = length(aws_secretsmanager_secret.this.replica) == 1 && length(module.key) == 0
    error_message = "Without a key, replicas use aws/secretsmanager."
  }
}

run "write_only_value" {
  command = apply

  variables {
    secret_string_wo         = "{\"password\":\"example-only\"}"
    secret_string_wo_version = 1
  }

  assert {
    condition     = aws_secretsmanager_secret_version.this[0].secret_string_wo_version == 1 && aws_secretsmanager_secret_version.this[0].secret_string_wo == null && aws_secretsmanager_secret_version.this[0].secret_string == null
    error_message = "The value is written only through the write-only argument and never stored."
  }
}

run "rotation_and_policy" {
  command = apply

  variables {
    rotation = { enabled = true, lambda_arn = "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-rotate:live" }
    policy_statements = [
      { sid = "ReadFromApi", actions = ["secretsmanager:GetSecretValue"], principals = { AWS = ["arn:aws:iam::123456789012:role/core-prod-api-exec-eu-west-1"] } },
      { sid = "DenyOtherAccounts", effect = "Deny", actions = ["secretsmanager:*"], principals = { AWS = ["*"] }, conditions = [{ test = "StringNotEquals", variable = "aws:PrincipalAccount", values = ["123456789012"] }] }
    ]
  }

  assert {
    condition     = aws_secretsmanager_secret_rotation.this[0].rotation_rules[0].automatically_after_days == 30 && aws_secretsmanager_secret_rotation.this[0].rotate_immediately
    error_message = "Rotation runs every 30 days by default (SecretsManager.4)."
  }

  assert {
    condition     = aws_secretsmanager_secret_policy.this[0].block_public_policy && [for s in jsondecode(aws_secretsmanager_secret_policy.this[0].policy).Statement : s.Sid] == ["ReadFromApi", "DenyOtherAccounts"] && jsondecode(aws_secretsmanager_secret_policy.this[0].policy).Statement[0].Resource == ["*"]
    error_message = "The resource policy blocks public access and defaults to the secret."
  }
}

run "rotation_schedule" {
  command = plan

  variables {
    rotation = { enabled = true, lambda_arn = "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-rotate:live", schedule_expression = "rate(120 days)", duration = "3h" }
  }

  assert {
    condition     = aws_secretsmanager_secret_rotation.this[0].rotation_rules[0].schedule_expression == "rate(120 days)" && aws_secretsmanager_secret_rotation.this[0].rotation_rules[0].automatically_after_days == null
    error_message = "A schedule expression replaces the day count."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "DB_Secret"
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
    kms = { key_id = "alias/aws/secretsmanager" }
  }

  expect_failures = [var.kms]
}

run "rejects_invalid_recovery_window" {
  command = plan

  variables {
    recovery_window_in_days = 3
  }

  expect_failures = [var.recovery_window_in_days]
}

run "rejects_value_without_version" {
  command = plan

  variables {
    secret_string_wo = "example-only"
  }

  expect_failures = [var.secret_string_wo_version]
}

run "rejects_rotation_without_lambda" {
  command = plan

  variables {
    rotation = { enabled = true }
  }

  expect_failures = [var.rotation]
}

run "rejects_long_rotation_interval" {
  command = plan

  variables {
    rotation = { enabled = true, lambda_arn = "arn:aws:lambda:eu-west-1:123456789012:function:x", automatically_after_days = 120 }
  }

  expect_failures = [var.rotation]
}

run "rejects_invalid_replica_region" {
  command = plan

  variables {
    replica_regions = { Frankfurt = {} }
  }

  expect_failures = [var.replica_regions]
}

run "rejects_caller_key_without_region_keys" {
  command = plan

  variables {
    kms             = { key_id = "11111111-2222-3333-4444-555555555555" }
    replica_regions = { eu-central-1 = {} }
  }

  expect_failures = [var.replica_regions]
}
