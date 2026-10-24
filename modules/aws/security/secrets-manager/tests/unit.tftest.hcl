mock_provider "aws" {
  mock_resource "aws_secretsmanager_secret" {
    defaults = {
      arn = "arn:aws:secretsmanager:us-west-2:123456789012:secret:core-prod-db-credentials-AbCdEf"
      id  = "arn:aws:secretsmanager:us-west-2:123456789012:secret:core-prod-db-credentials-AbCdEf"
    }
  }
}

variables {
  application = "core"
  environment = "prod"
  name        = "db-credentials"
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
}

# ------------------------------------------------------------------------------
# Naming
# ------------------------------------------------------------------------------

run "naming_renders_application_environment_name" {
  command = plan

  assert {
    condition     = aws_secretsmanager_secret.this.name == "core-prod-db-credentials"
    error_message = "Secret name must be <application>-<environment>-<name>."
  }

  assert {
    condition     = aws_secretsmanager_secret.this.tags["Name"] == "core-prod-db-credentials"
    error_message = "Name tag must be the rendered secret name."
  }
}

run "naming_does_not_double_prefix_a_rendered_name" {
  command = plan

  variables {
    name = "core-prod-db-credentials"
  }

  assert {
    condition     = aws_secretsmanager_secret.this.name == "core-prod-db-credentials"
    error_message = "A name already starting with <application>-<environment> must not be prefixed again."
  }
}

run "naming_falls_back_when_name_is_null" {
  command = plan

  variables {
    name = null
  }

  assert {
    condition     = aws_secretsmanager_secret.this.name == "core-prod"
    error_message = "With a null name the secret name must fall back to <application>-<environment>."
  }

  assert {
    condition     = aws_secretsmanager_secret.this.tags["Name"] == "core-prod"
    error_message = "With a null name the Name tag must fall back to <application>-<environment>."
  }
}

run "naming_falls_back_when_name_is_empty" {
  command = plan

  variables {
    name = ""
  }

  assert {
    condition     = aws_secretsmanager_secret.this.name == "core-prod"
    error_message = "With an empty name the secret name must fall back to <application>-<environment>."
  }
}

run "naming_uses_name_prefix_when_set" {
  command = plan

  variables {
    name        = null
    name_prefix = "core-prod-api-key-"
  }

  assert {
    condition     = aws_secretsmanager_secret.this.name_prefix == "core-prod-api-key-"
    error_message = "name_prefix must flow through to the secret."
  }

  assert {
    condition     = aws_secretsmanager_secret.this.tags["Name"] == "core-prod-api-key-"
    error_message = "With name_prefix the Name tag must be the prefix."
  }
}

# ------------------------------------------------------------------------------
# Tags
# ------------------------------------------------------------------------------

run "tags_include_governance_and_caller_tags" {
  command = plan

  variables {
    tags = {
      CostCenter = "1234"
      Team       = "platform"
    }
  }

  assert {
    condition     = aws_secretsmanager_secret.this.tags["Application"] == "core"
    error_message = "Secret must carry the Application governance tag."
  }

  assert {
    condition     = aws_secretsmanager_secret.this.tags["Environment"] == "prod"
    error_message = "Secret must carry the Environment governance tag."
  }

  assert {
    condition     = aws_secretsmanager_secret.this.tags["Name"] == "core-prod-db-credentials"
    error_message = "Secret must carry the Name governance tag."
  }

  assert {
    condition     = aws_secretsmanager_secret.this.tags["ManagedBy"] == "Terraform"
    error_message = "Secret must carry ManagedBy = Terraform."
  }

  assert {
    condition     = aws_secretsmanager_secret.this.tags["CostCenter"] == "1234" && aws_secretsmanager_secret.this.tags["Team"] == "platform"
    error_message = "Caller tags from var.tags must be preserved on the secret."
  }
}

run "tags_governance_take_precedence_over_caller_tags" {
  command = plan

  variables {
    tags = {
      Application = "other-app"
      Environment = "dev"
      Name        = "other-name"
      ManagedBy   = "Manual"
      CostCenter  = "1234"
    }
  }

  assert {
    condition     = aws_secretsmanager_secret.this.tags["Application"] == "core"
    error_message = "A caller tag must not overwrite the Application governance tag."
  }

  assert {
    condition     = aws_secretsmanager_secret.this.tags["Environment"] == "prod"
    error_message = "A caller tag must not overwrite the Environment governance tag."
  }

  assert {
    condition     = aws_secretsmanager_secret.this.tags["Name"] == "core-prod-db-credentials"
    error_message = "A caller tag must not overwrite the Name governance tag."
  }

  assert {
    condition     = aws_secretsmanager_secret.this.tags["ManagedBy"] == "Terraform"
    error_message = "A caller tag must not overwrite the ManagedBy governance tag."
  }

  assert {
    condition     = aws_secretsmanager_secret.this.tags["CostCenter"] == "1234"
    error_message = "Non-governance caller tags must still be preserved."
  }
}

# ------------------------------------------------------------------------------
# Security defaults and shipped parameter defaults
# ------------------------------------------------------------------------------

run "security_defaults_enforced" {
  command = plan

  assert {
    condition     = aws_secretsmanager_secret.this.kms_key_id == var.kms_key_arn
    error_message = "The secret must be encrypted with the caller's KMS key."
  }

  assert {
    condition     = aws_secretsmanager_secret.this.recovery_window_in_days == 30
    error_message = "Default recovery window must be 30 days."
  }

  assert {
    condition     = aws_secretsmanager_secret.this.force_overwrite_replica_secret == false
    error_message = "Replica secrets must not be force-overwritten by default."
  }

  assert {
    condition     = aws_secretsmanager_secret.this.description == null && aws_secretsmanager_secret.this.type == null
    error_message = "description and type must default to null."
  }

  assert {
    condition     = length(aws_secretsmanager_secret_policy.this) == 0
    error_message = "No resource policy must be attached by default."
  }

  assert {
    condition     = length(aws_secretsmanager_secret_rotation.this) == 0
    error_message = "Rotation must be off by default."
  }

  assert {
    condition     = length(aws_secretsmanager_secret_version.this) == 0
    error_message = "No secret version must be created without a payload."
  }

  assert {
    condition     = output.version_id == null && output.policy_id == null
    error_message = "version_id and policy_id outputs must be null when those resources are not created."
  }
}

run "resource_policy_blocks_public_access_by_default" {
  command = apply

  variables {
    policy = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"AllowAppRole\",\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"arn:aws:iam::123456789012:role/core-prod-app\"},\"Action\":\"secretsmanager:GetSecretValue\",\"Resource\":\"*\"}]}"
  }

  assert {
    condition     = length(aws_secretsmanager_secret_policy.this) == 1
    error_message = "A resource policy must be attached when policy is set."
  }

  assert {
    condition     = aws_secretsmanager_secret_policy.this[0].block_public_policy == true
    error_message = "block_public_policy must default to true."
  }

  assert {
    condition     = aws_secretsmanager_secret_policy.this[0].policy == var.policy
    error_message = "The resource policy must be the policy passed in."
  }

  assert {
    condition     = aws_secretsmanager_secret_policy.this[0].secret_arn == aws_secretsmanager_secret.this.arn
    error_message = "The resource policy must be attached to the module's secret."
  }

  assert {
    condition     = output.policy_id == aws_secretsmanager_secret_policy.this[0].id
    error_message = "policy_id output must expose the resource policy id."
  }
}

run "rotation_wired_when_configured" {
  command = apply

  variables {
    rotation_config = {
      rotation_lambda_arn = "arn:aws:lambda:us-west-2:123456789012:function:core-prod-secrets-rotator"
      rotation_rules = {
        automatically_after_days = 30
      }
    }
  }

  assert {
    condition     = length(aws_secretsmanager_secret_rotation.this) == 1
    error_message = "Rotation must be configured when rotation_config is set."
  }

  assert {
    condition     = aws_secretsmanager_secret_rotation.this[0].secret_id == aws_secretsmanager_secret.this.id
    error_message = "Rotation must target the module's secret."
  }

  assert {
    condition     = aws_secretsmanager_secret_rotation.this[0].rotation_lambda_arn == "arn:aws:lambda:us-west-2:123456789012:function:core-prod-secrets-rotator"
    error_message = "rotation_lambda_arn must flow through to the rotation."
  }

  assert {
    condition     = aws_secretsmanager_secret_rotation.this[0].rotate_immediately == true
    error_message = "rotate_immediately must default to true."
  }

  assert {
    condition     = aws_secretsmanager_secret_rotation.this[0].rotation_rules[0].automatically_after_days == 30
    error_message = "rotation_rules.automatically_after_days must flow through to the rotation."
  }
}

run "rotation_schedule_overrides_flow_through" {
  command = plan

  variables {
    rotation_config = {
      rotation_lambda_arn = "arn:aws:lambda:us-west-2:123456789012:function:core-prod-secrets-rotator"
      rotate_immediately  = false
      rotation_rules = {
        duration            = "3h"
        schedule_expression = "rate(10 days)"
      }
    }
  }

  assert {
    condition     = aws_secretsmanager_secret_rotation.this[0].rotate_immediately == false
    error_message = "rotate_immediately = false must flow through to the rotation."
  }

  assert {
    condition     = aws_secretsmanager_secret_rotation.this[0].rotation_rules[0].schedule_expression == "rate(10 days)"
    error_message = "rotation_rules.schedule_expression must flow through to the rotation."
  }

  assert {
    condition     = aws_secretsmanager_secret_rotation.this[0].rotation_rules[0].duration == "3h"
    error_message = "rotation_rules.duration must flow through to the rotation."
  }

  assert {
    condition     = aws_secretsmanager_secret_rotation.this[0].rotation_rules[0].automatically_after_days == null
    error_message = "Unset rotation_rules.automatically_after_days must stay null."
  }
}

# ------------------------------------------------------------------------------
# Secret payloads
# ------------------------------------------------------------------------------

run "secret_string_creates_version" {
  command = apply

  variables {
    secret_string = "{\"username\":\"app\",\"password\":\"example-only\"}"
  }

  assert {
    condition     = length(aws_secretsmanager_secret_version.this) == 1
    error_message = "A secret version must be created when secret_string is set."
  }

  assert {
    condition     = aws_secretsmanager_secret_version.this[0].secret_id == aws_secretsmanager_secret.this.id
    error_message = "The secret version must belong to the module's secret."
  }

  assert {
    condition     = aws_secretsmanager_secret_version.this[0].secret_string == var.secret_string
    error_message = "secret_string must flow through to the secret version."
  }

  assert {
    condition     = output.version_id == aws_secretsmanager_secret_version.this[0].version_id
    error_message = "version_id output must expose the secret version id."
  }
}

run "secret_binary_creates_version" {
  command = plan

  variables {
    secret_binary = base64encode("example-binary-payload")
  }

  assert {
    condition     = length(aws_secretsmanager_secret_version.this) == 1
    error_message = "A secret version must be created when secret_binary is set."
  }

  assert {
    condition     = aws_secretsmanager_secret_version.this[0].secret_binary == var.secret_binary
    error_message = "secret_binary must flow through to the secret version."
  }

  assert {
    condition     = aws_secretsmanager_secret_version.this[0].secret_string == null
    error_message = "secret_string must stay null when only secret_binary is set."
  }
}

run "write_only_secret_string_kept_out_of_state" {
  command = apply

  variables {
    secret_string_wo         = "{\"username\":\"app\",\"password\":\"example-only\"}"
    secret_string_wo_version = 1
  }

  assert {
    condition     = length(aws_secretsmanager_secret_version.this) == 1
    error_message = "A secret version must be created when secret_string_wo is set."
  }

  assert {
    condition     = aws_secretsmanager_secret_version.this[0].secret_string_wo == null
    error_message = "secret_string_wo is write-only and must never be persisted in state."
  }

  assert {
    condition     = aws_secretsmanager_secret_version.this[0].secret_string == null
    error_message = "The write-only payload must not be copied into the stateful secret_string."
  }

  assert {
    condition     = aws_secretsmanager_secret_version.this[0].secret_string_wo_version == 1
    error_message = "secret_string_wo_version must flow through to trigger write-only updates."
  }
}

# ------------------------------------------------------------------------------
# Parameter overrides
# ------------------------------------------------------------------------------

run "parameter_overrides_flow_through" {
  command = plan

  variables {
    description                    = "Database credentials for the core service"
    recovery_window_in_days        = 7
    force_overwrite_replica_secret = true
    region                         = "us-west-2"
    policy                         = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"AllowAppRole\",\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"arn:aws:iam::123456789012:role/core-prod-app\"},\"Action\":\"secretsmanager:GetSecretValue\",\"Resource\":\"*\"}]}"
    block_public_policy            = false
    secret_string                  = "example-only"
    version_stages                 = ["AWSCURRENT", "INITIAL"]
  }

  assert {
    condition     = aws_secretsmanager_secret.this.description == "Database credentials for the core service"
    error_message = "description must flow through to the secret."
  }

  assert {
    condition     = aws_secretsmanager_secret.this.recovery_window_in_days == 7
    error_message = "recovery_window_in_days must flow through to the secret."
  }

  assert {
    condition     = aws_secretsmanager_secret.this.force_overwrite_replica_secret == true
    error_message = "force_overwrite_replica_secret must flow through to the secret."
  }

  assert {
    condition     = aws_secretsmanager_secret.this.region == "us-west-2" && aws_secretsmanager_secret_policy.this[0].region == "us-west-2" && aws_secretsmanager_secret_version.this[0].region == "us-west-2"
    error_message = "region must flow through to the secret, its policy and its version."
  }

  assert {
    condition     = aws_secretsmanager_secret_policy.this[0].block_public_policy == false
    error_message = "block_public_policy must flow through to the resource policy."
  }

  assert {
    condition     = aws_secretsmanager_secret_version.this[0].version_stages == toset(["AWSCURRENT", "INITIAL"])
    error_message = "version_stages must flow through to the secret version."
  }
}

run "recovery_window_zero_allows_force_delete" {
  command = plan

  variables {
    recovery_window_in_days = 0
  }

  assert {
    condition     = aws_secretsmanager_secret.this.recovery_window_in_days == 0
    error_message = "recovery_window_in_days = 0 (force delete) must be accepted."
  }
}

# ------------------------------------------------------------------------------
# Validation
# ------------------------------------------------------------------------------

run "rejects_invalid_environment" {
  command = plan

  variables {
    environment = "Prod_Env"
  }

  expect_failures = [var.environment]
}

run "rejects_name_and_name_prefix_together" {
  command = plan

  variables {
    name        = "db-credentials"
    name_prefix = "core-prod-db-"
  }

  expect_failures = [var.name]
}

run "rejects_recovery_window_between_1_and_6_days" {
  command = plan

  variables {
    recovery_window_in_days = 5
  }

  expect_failures = [var.recovery_window_in_days]
}

run "rejects_recovery_window_above_30_days" {
  command = plan

  variables {
    recovery_window_in_days = 31
  }

  expect_failures = [var.recovery_window_in_days]
}

run "rejects_secret_string_with_write_only_string" {
  command = plan

  variables {
    secret_string    = "example-only"
    secret_string_wo = "example-only"
  }

  expect_failures = [aws_secretsmanager_secret_version.this]
}

run "rejects_secret_string_with_secret_binary" {
  command = plan

  variables {
    secret_string = "example-only"
    secret_binary = base64encode("example-binary-payload")
  }

  expect_failures = [aws_secretsmanager_secret_version.this]
}
