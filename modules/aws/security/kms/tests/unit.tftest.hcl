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

  mock_resource "aws_kms_key" {
    defaults = {
      arn    = "arn:aws:kms:eu-west-1:123456789012:key/mrk-1234abcd12ab34cd56ef1234567890ab"
      key_id = "mrk-1234abcd12ab34cd56ef1234567890ab"
    }
  }
}

variables {
  application = "core"
  environment = "prod"
  name        = "data"
  tags        = { Team = "platform", Name = "ignored" }
}

run "creates_a_rotating_key_with_alias_and_tags" {
  command = apply

  assert {
    condition     = aws_kms_key.this.enable_key_rotation && aws_kms_key.this.rotation_period_in_days == 365 && aws_kms_key.this.deletion_window_in_days == 30
    error_message = "A symmetric key must rotate every 365 days with a 30-day deletion window."
  }

  assert {
    condition     = output.alias_name == "alias/core-prod-data" && aws_kms_key.this.description == "core-prod-data key"
    error_message = "The alias and description must come from the base name."
  }

  assert {
    condition     = aws_kms_key.this.tags["Name"] == "core-prod-data" && aws_kms_key.this.tags["Team"] == "platform" && aws_kms_key.this.tags["ManagedBy"] == "Terraform"
    error_message = "Governance tags must win over caller tags."
  }

  assert {
    condition     = output.arn == "arn:aws:kms:eu-west-1:123456789012:key/mrk-1234abcd12ab34cd56ef1234567890ab" && output.id == "mrk-1234abcd12ab34cd56ef1234567890ab"
    error_message = "arn and id must expose the key."
  }

  assert {
    condition     = length(aws_kms_replica_key.this) == 0 && output.replica_arns == {}
    error_message = "No replica is created by default."
  }
}

run "key_policy_keeps_iam_delegation_and_adds_statements" {
  command = plan

  variables {
    policy_statements = [{
      sid        = "AllowCloudWatchLogs"
      actions    = ["kms:Encrypt*", "kms:Decrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
      principals = { Service = ["logs.eu-west-1.amazonaws.com"] }
      conditions = [{ test = "ArnLike", variable = "kms:EncryptionContext:aws:logs:arn", values = ["arn:aws:logs:eu-west-1:123456789012:log-group:/aws/lambda/core-prod-orders"] }]
    }]
  }

  assert {
    condition     = jsondecode(aws_kms_key.this.policy).Statement[0].Sid == "EnableIAMPolicies" && jsondecode(aws_kms_key.this.policy).Statement[0].Principal.AWS == ["arn:aws:iam::123456789012:root"]
    error_message = "The first statement must let the account's IAM policies grant access."
  }

  assert {
    condition     = jsondecode(aws_kms_key.this.policy).Statement[1].Sid == "AllowCloudWatchLogs" && jsondecode(aws_kms_key.this.policy).Statement[1].Resource == ["*"]
    error_message = "Extra statements must follow, with Resource * meaning this key."
  }

  assert {
    condition     = aws_kms_key.this.bypass_policy_lockout_safety_check == false
    error_message = "The lockout safety check must stay on."
  }
}

run "asymmetric_signing_key_does_not_rotate" {
  command = plan

  variables {
    key_usage = "SIGN_VERIFY"
    key_spec  = "ECC_NIST_P256"
    region    = "us-east-1"
  }

  assert {
    condition     = aws_kms_key.this.enable_key_rotation == false && aws_kms_key.this.customer_master_key_spec == "ECC_NIST_P256" && aws_kms_key.this.region == "us-east-1"
    error_message = "An asymmetric key must not rotate and must be created in the requested Region."
  }
}

run "replicas_and_additional_aliases" {
  command = plan

  variables {
    multi_region       = true
    replica_regions    = ["us-east-1", "ap-south-1"]
    additional_aliases = ["core/data"]
  }

  assert {
    condition     = aws_kms_replica_key.this["us-east-1"].region == "us-east-1" && aws_kms_replica_key.this["ap-south-1"].region == "ap-south-1"
    error_message = "Each replica must be created in its own Region through the region argument."
  }

  assert {
    condition     = aws_kms_alias.replica["us-east-1"].name == "alias/core-prod-data" && contains(keys(aws_kms_alias.this), "alias/core/data")
    error_message = "Replicas must carry the primary alias and extra aliases must be created."
  }
}

run "purpose_is_part_of_the_alias" {
  command = plan

  variables {
    purpose = "rds"
  }

  assert {
    condition     = output.alias_name == "alias/core-prod-data-rds" && aws_kms_key.this.description == "core-prod-data-rds key"
    error_message = "purpose must be appended to the alias so keys of different services never collide."
  }
}

run "rejects_invalid_purpose" {
  command = plan

  variables {
    purpose = "RDS"
  }

  expect_failures = [var.purpose]
}

run "rejects_public_key_policy_statement" {
  command = plan

  variables {
    policy_statements = [{ actions = ["kms:Decrypt"], principals = { AWS = ["*"] } }]
  }

  expect_failures = [var.policy_statements]
}

run "rejects_replicas_without_multi_region" {
  command = plan

  variables {
    replica_regions = ["us-east-1"]
  }

  expect_failures = [var.replica_regions]
}

run "key_agreement_key" {
  command = plan

  variables {
    key_usage = "KEY_AGREEMENT"
    key_spec  = "ECC_NIST_P384"
  }

  assert {
    condition     = aws_kms_key.this.key_usage == "KEY_AGREEMENT" && aws_kms_key.this.customer_master_key_spec == "ECC_NIST_P384" && !aws_kms_key.this.enable_key_rotation
    error_message = "Key agreement keys use ECC specs without rotation."
  }
}

run "edwards_signing_key" {
  command = plan

  variables {
    key_usage = "SIGN_VERIFY"
    key_spec  = "ECC_NIST_EDWARDS25519"
  }

  assert {
    condition     = aws_kms_key.this.customer_master_key_spec == "ECC_NIST_EDWARDS25519"
    error_message = "Ed25519 signing keys are allowed."
  }
}

run "rejects_invalid_key_usage" {
  command = plan

  variables {
    key_usage = "ENCRYPT"
  }

  expect_failures = [var.key_usage]
}

run "rejects_invalid_key_spec" {
  command = plan

  variables {
    key_spec = "AES_256"
  }

  expect_failures = [var.key_spec]
}

run "rejects_short_deletion_window" {
  command = plan

  variables {
    deletion_window_in_days = 3
  }

  expect_failures = [var.deletion_window_in_days]
}

run "rejects_invalid_rotation_period" {
  command = plan

  variables {
    rotation_period_in_days = 30
  }

  expect_failures = [var.rotation_period_in_days]
}

run "rejects_aws_reserved_alias" {
  command = plan

  variables {
    additional_aliases = ["aws/s3"]
  }

  expect_failures = [var.additional_aliases]
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

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Data_Key"
  }

  expect_failures = [var.name]
}
