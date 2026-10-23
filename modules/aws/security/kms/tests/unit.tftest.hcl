mock_provider "aws" {
  mock_resource "aws_kms_key" {
    defaults = {
      arn    = "arn:aws:kms:us-west-2:123456789012:key/mrk-1234abcd12ab34cd56ef1234567890ab"
      key_id = "mrk-1234abcd12ab34cd56ef1234567890ab"
    }
  }
}

mock_provider "aws" {
  alias = "replica"

  mock_resource "aws_kms_replica_key" {
    defaults = {
      arn    = "arn:aws:kms:us-east-1:123456789012:key/mrk-1234abcd12ab34cd56ef1234567890ab"
      key_id = "mrk-1234abcd12ab34cd56ef1234567890ab"
    }
  }
}

variables {
  application = "core"
  environment = "prod"
  name        = "primary"
}

# ------------------------------------------------------------------------------
# Naming
# ------------------------------------------------------------------------------

run "naming_renders_application_environment_name" {
  command = plan

  providers = {
    aws         = aws
    aws.replica = aws.replica
  }

  assert {
    condition     = aws_kms_alias.this.name == "alias/core-prod-primary-key"
    error_message = "KMS alias must be alias/<application>-<environment>-<name>-key."
  }

  assert {
    condition     = aws_kms_key.this.tags["Name"] == "core-prod-primary"
    error_message = "KMS key Name tag must be the rendered name <application>-<environment>-<name>."
  }

  assert {
    condition     = aws_kms_key.this.description == "KMS Key for core primary in prod"
    error_message = "KMS key default description must be computed from application, name and environment."
  }
}

run "naming_falls_back_when_name_is_null" {
  command = plan

  providers = {
    aws         = aws
    aws.replica = aws.replica
  }

  variables {
    name = null
  }

  assert {
    condition     = aws_kms_alias.this.name == "alias/core-prod-key"
    error_message = "With a null name the alias must fall back to alias/<application>-<environment>-key."
  }

  assert {
    condition     = aws_kms_key.this.tags["Name"] == "core-prod"
    error_message = "With a null name the Name tag must fall back to <application>-<environment>."
  }

  assert {
    condition     = aws_kms_key.this.description == "KMS Key for core in prod"
    error_message = "With a null name the default description must omit the name segment."
  }
}

run "naming_falls_back_when_name_is_empty" {
  command = plan

  providers = {
    aws         = aws
    aws.replica = aws.replica
  }

  variables {
    name = ""
  }

  assert {
    condition     = aws_kms_alias.this.name == "alias/core-prod-key"
    error_message = "With an empty name the alias must fall back to alias/<application>-<environment>-key."
  }

  assert {
    condition     = aws_kms_key.this.tags["Name"] == "core-prod"
    error_message = "With an empty name the Name tag must fall back to <application>-<environment>."
  }
}

# ------------------------------------------------------------------------------
# Tags
# ------------------------------------------------------------------------------

run "tags_include_governance_and_caller_tags" {
  command = plan

  providers = {
    aws         = aws
    aws.replica = aws.replica
  }

  variables {
    tags = {
      CostCenter = "1234"
      Team       = "platform"
    }
  }

  assert {
    condition     = aws_kms_key.this.tags["Application"] == "core"
    error_message = "KMS key must carry the Application governance tag."
  }

  assert {
    condition     = aws_kms_key.this.tags["Environment"] == "prod"
    error_message = "KMS key must carry the Environment governance tag."
  }

  assert {
    condition     = aws_kms_key.this.tags["Name"] == "core-prod-primary"
    error_message = "KMS key must carry the Name governance tag."
  }

  assert {
    condition     = aws_kms_key.this.tags["CostCenter"] == "1234" && aws_kms_key.this.tags["Team"] == "platform"
    error_message = "Caller tags from var.tags must be preserved on the KMS key."
  }
}

# ------------------------------------------------------------------------------
# Security defaults and shipped parameter defaults
# ------------------------------------------------------------------------------

run "security_defaults_enforced" {
  command = plan

  providers = {
    aws         = aws
    aws.replica = aws.replica
  }

  assert {
    condition     = aws_kms_key.this.enable_key_rotation == true
    error_message = "Automatic key rotation must be enabled by default."
  }

  assert {
    condition     = aws_kms_key.this.rotation_period_in_days == 365
    error_message = "Default rotation period must be 365 days."
  }

  assert {
    condition     = aws_kms_key.this.deletion_window_in_days == 30
    error_message = "Default deletion window must be 30 days."
  }

  assert {
    condition     = aws_kms_key.this.bypass_policy_lockout_safety_check == false
    error_message = "The policy lockout safety check must never be bypassed on the key."
  }

  assert {
    condition     = aws_kms_key.this.is_enabled == true
    error_message = "The key must be enabled by default."
  }

  assert {
    condition     = aws_kms_key.this.key_usage == "ENCRYPT_DECRYPT"
    error_message = "Default key usage must be ENCRYPT_DECRYPT."
  }

  assert {
    condition     = aws_kms_key.this.customer_master_key_spec == "SYMMETRIC_DEFAULT"
    error_message = "Default key spec must be SYMMETRIC_DEFAULT."
  }

  assert {
    condition     = aws_kms_key.this.multi_region == false
    error_message = "Keys must be single-region by default."
  }

  assert {
    condition     = length(aws_kms_key_policy.this) == 0
    error_message = "No separate key policy resource must be created when policy_json is null."
  }

  assert {
    condition     = length(aws_kms_replica_key.this) == 0 && length(aws_kms_alias.replica) == 0
    error_message = "No replica key or replica alias must be created by default."
  }

  assert {
    condition     = output.replica_key_arn == null
    error_message = "replica_key_arn output must be null when no replica is created."
  }
}

run "key_policy_attached_when_provided" {
  command = apply

  providers = {
    aws         = aws
    aws.replica = aws.replica
  }

  variables {
    policy_json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"EnableRootAccess\",\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"arn:aws:iam::123456789012:root\"},\"Action\":\"kms:*\",\"Resource\":\"*\"}]}"
  }

  assert {
    condition     = length(aws_kms_key_policy.this) == 1
    error_message = "A key policy resource must be created when policy_json is set."
  }

  assert {
    condition     = aws_kms_key_policy.this[0].policy == var.policy_json
    error_message = "The key policy must be the policy_json passed in."
  }

  assert {
    condition     = aws_kms_key_policy.this[0].key_id == aws_kms_key.this.id
    error_message = "The key policy must be attached to the module's KMS key."
  }

  assert {
    condition     = aws_kms_key_policy.this[0].bypass_policy_lockout_safety_check == false
    error_message = "The policy lockout safety check must never be bypassed on the key policy."
  }

  assert {
    condition     = aws_kms_alias.this.target_key_id == aws_kms_key.this.key_id
    error_message = "The alias must target the module's KMS key."
  }

  assert {
    condition     = output.key_arn == aws_kms_key.this.arn && output.key_id == aws_kms_key.this.key_id
    error_message = "key_arn and key_id outputs must expose the KMS key's ARN and key id."
  }
}

# ------------------------------------------------------------------------------
# Parameter overrides
# ------------------------------------------------------------------------------

run "parameter_overrides_flow_through" {
  command = plan

  providers = {
    aws         = aws
    aws.replica = aws.replica
  }

  variables {
    description              = "Signing key for release artifacts"
    is_enabled               = false
    key_usage                = "SIGN_VERIFY"
    customer_master_key_spec = "RSA_2048"
    deletion_window_in_days  = 7
    enable_key_rotation      = false
    rotation_period_in_days  = 90
  }

  assert {
    condition     = aws_kms_key.this.description == "Signing key for release artifacts"
    error_message = "A custom description must override the computed one."
  }

  assert {
    condition     = aws_kms_key.this.is_enabled == false
    error_message = "is_enabled must flow through to the key."
  }

  assert {
    condition     = aws_kms_key.this.key_usage == "SIGN_VERIFY"
    error_message = "key_usage must flow through to the key."
  }

  assert {
    condition     = aws_kms_key.this.customer_master_key_spec == "RSA_2048"
    error_message = "customer_master_key_spec must flow through to the key."
  }

  assert {
    condition     = aws_kms_key.this.deletion_window_in_days == 7
    error_message = "deletion_window_in_days must flow through to the key."
  }

  assert {
    condition     = aws_kms_key.this.enable_key_rotation == false
    error_message = "enable_key_rotation must flow through to the key."
  }

  assert {
    condition     = aws_kms_key.this.rotation_period_in_days == 90
    error_message = "rotation_period_in_days must flow through to the key."
  }
}

# ------------------------------------------------------------------------------
# Multi-region and replica toggles
# ------------------------------------------------------------------------------

run "multi_region_without_replica_creates_no_replica" {
  command = plan

  providers = {
    aws         = aws
    aws.replica = aws.replica
  }

  variables {
    multi_region = true
  }

  assert {
    condition     = aws_kms_key.this.multi_region == true
    error_message = "multi_region must flow through to the key."
  }

  assert {
    condition     = length(aws_kms_replica_key.this) == 0 && length(aws_kms_alias.replica) == 0
    error_message = "No replica must be created unless replica_key.create is true."
  }
}

run "replica_not_created_for_single_region_key" {
  command = plan

  providers = {
    aws         = aws
    aws.replica = aws.replica
  }

  variables {
    replica_key = {
      create = true
    }
  }

  assert {
    condition     = length(aws_kms_replica_key.this) == 0 && length(aws_kms_alias.replica) == 0
    error_message = "A replica requires multi_region = true and must not be created for a single-region key."
  }
}

run "replica_created_on_replica_provider_when_enabled" {
  command = apply

  providers = {
    aws         = aws
    aws.replica = aws.replica
  }

  variables {
    multi_region = true
    policy_json  = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"PrimaryPolicy\",\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"arn:aws:iam::123456789012:root\"},\"Action\":\"kms:*\",\"Resource\":\"*\"}]}"
    replica_key = {
      create                  = true
      policy_json             = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"ReplicaPolicy\",\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"arn:aws:iam::123456789012:root\"},\"Action\":\"kms:*\",\"Resource\":\"*\"}]}"
      deletion_window_in_days = 7
    }
    tags = {
      CostCenter = "1234"
    }
  }

  assert {
    condition     = length(aws_kms_replica_key.this) == 1 && length(aws_kms_alias.replica) == 1
    error_message = "A replica key and replica alias must be created when multi_region and replica_key.create are true."
  }

  assert {
    condition     = aws_kms_replica_key.this[0].arn == "arn:aws:kms:us-east-1:123456789012:key/mrk-1234abcd12ab34cd56ef1234567890ab"
    error_message = "The replica key must be created through the aws.replica provider."
  }

  assert {
    condition     = aws_kms_replica_key.this[0].primary_key_arn == aws_kms_key.this.arn
    error_message = "The replica must replicate the module's primary key."
  }

  assert {
    condition     = aws_kms_replica_key.this[0].deletion_window_in_days == 7
    error_message = "replica_key.deletion_window_in_days must flow through to the replica."
  }

  assert {
    condition     = aws_kms_replica_key.this[0].policy == var.replica_key.policy_json
    error_message = "replica_key.policy_json must take precedence over policy_json on the replica."
  }

  assert {
    condition     = aws_kms_replica_key.this[0].bypass_policy_lockout_safety_check == false
    error_message = "The policy lockout safety check must never be bypassed on the replica."
  }

  assert {
    condition     = aws_kms_replica_key.this[0].description == "KMS Replica Key for core primary in prod"
    error_message = "Replica description must be computed from application, name and environment."
  }

  assert {
    condition     = aws_kms_replica_key.this[0].tags["Application"] == "core" && aws_kms_replica_key.this[0].tags["Environment"] == "prod" && aws_kms_replica_key.this[0].tags["Name"] == "core-prod-primary"
    error_message = "Replica key must carry the Application, Environment and Name governance tags."
  }

  assert {
    condition     = aws_kms_replica_key.this[0].tags["CostCenter"] == "1234"
    error_message = "Caller tags must be preserved on the replica key."
  }

  assert {
    condition     = aws_kms_alias.replica[0].name == "alias/core-prod-primary-replica-key"
    error_message = "Replica alias must be alias/<application>-<environment>-<name>-replica-key."
  }

  assert {
    condition     = aws_kms_alias.replica[0].target_key_id == aws_kms_replica_key.this[0].key_id
    error_message = "Replica alias must target the replica key."
  }

  assert {
    condition     = output.replica_key_arn == aws_kms_replica_key.this[0].arn
    error_message = "replica_key_arn output must expose the replica key ARN."
  }
}

run "replica_inherits_primary_policy_and_default_window" {
  command = plan

  providers = {
    aws         = aws
    aws.replica = aws.replica
  }

  variables {
    multi_region = true
    policy_json  = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"PrimaryPolicy\",\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"arn:aws:iam::123456789012:root\"},\"Action\":\"kms:*\",\"Resource\":\"*\"}]}"
    replica_key = {
      create = true
    }
  }

  assert {
    condition     = aws_kms_replica_key.this[0].policy == var.policy_json
    error_message = "Without replica_key.policy_json the replica must fall back to policy_json."
  }

  assert {
    condition     = aws_kms_replica_key.this[0].deletion_window_in_days == 30
    error_message = "Replica deletion window must default to 30 days."
  }
}

# ------------------------------------------------------------------------------
# Validation
# ------------------------------------------------------------------------------

run "rejects_invalid_environment" {
  command = plan

  providers = {
    aws         = aws
    aws.replica = aws.replica
  }

  variables {
    environment = "Prod_Env"
  }

  expect_failures = [var.environment]
}

run "rejects_deletion_window_below_7_days" {
  command = plan

  providers = {
    aws         = aws
    aws.replica = aws.replica
  }

  variables {
    deletion_window_in_days = 6
  }

  expect_failures = [var.deletion_window_in_days]
}

run "rejects_deletion_window_above_30_days" {
  command = plan

  providers = {
    aws         = aws
    aws.replica = aws.replica
  }

  variables {
    deletion_window_in_days = 31
  }

  expect_failures = [var.deletion_window_in_days]
}

run "rejects_rotation_period_below_90_days" {
  command = plan

  providers = {
    aws         = aws
    aws.replica = aws.replica
  }

  variables {
    rotation_period_in_days = 89
  }

  expect_failures = [var.rotation_period_in_days]
}

run "rejects_rotation_period_above_2560_days" {
  command = plan

  providers = {
    aws         = aws
    aws.replica = aws.replica
  }

  variables {
    rotation_period_in_days = 2561
  }

  expect_failures = [var.rotation_period_in_days]
}
