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

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/platform-prod-apigw-logs-eu-west-1"
    }
  }
}

variables {
  environment  = "prod"
  tags         = { Team = "platform" }
  support_role = { trusted_principal_arns = ["arn:aws:iam::123456789012:role/incident-response"] }
  alternate_contacts = {
    security = { name = "Security Team", title = "Security", email_address = "security@example.com", phone_number = "+1 555 0100" }
  }
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = aws_iam_account_password_policy.this[0].minimum_password_length == 14 && aws_iam_account_password_policy.this[0].password_reuse_prevention == 24 && aws_iam_account_password_policy.this[0].max_password_age == 90 && aws_iam_account_password_policy.this[0].require_symbols
    error_message = "Password policy defaults meet IAM.7 and IAM.10-17."
  }

  assert {
    condition     = aws_s3_account_public_access_block.this[0].block_public_acls && aws_s3_account_public_access_block.this[0].block_public_policy && aws_s3_account_public_access_block.this[0].ignore_public_acls && aws_s3_account_public_access_block.this[0].restrict_public_buckets
    error_message = "The account S3 public access block is on by default."
  }

  assert {
    condition     = aws_ebs_encryption_by_default.this["eu-west-1"].enabled && length(aws_ebs_default_kms_key.this) == 0
    error_message = "EBS encryption by default with the AWS managed key."
  }

  assert {
    condition     = aws_ec2_instance_metadata_defaults.this["eu-west-1"].http_tokens == "required" && aws_ec2_instance_metadata_defaults.this["eu-west-1"].http_put_response_hop_limit == 2
    error_message = "IMDSv2 required with hop limit 2."
  }

  assert {
    condition     = aws_ebs_snapshot_block_public_access.this["eu-west-1"].state == "block-all-sharing" && aws_ec2_image_block_public_access.this["eu-west-1"].state == "block-new-sharing" && !aws_ec2_serial_console_access.this["eu-west-1"].enabled
    error_message = "Snapshot and AMI public sharing blocked, serial console off."
  }

  assert {
    condition     = length(aws_vpc_block_public_access_options.this) == 0
    error_message = "VPC block public access is off by default."
  }

  assert {
    condition     = aws_ecr_registry_scanning_configuration.this["eu-west-1"].scan_type == "ENHANCED" && one(aws_ecr_registry_scanning_configuration.this["eu-west-1"].rule).scan_frequency == "CONTINUOUS_SCAN"
    error_message = "ECR enhanced continuous scanning by default."
  }

  assert {
    condition     = length(aws_ecr_replication_configuration.this) == 0 && length(aws_ecr_pull_through_cache_rule.this) == 0
    error_message = "ECR replication and pull through cache are opt-in."
  }

  assert {
    condition     = keys(aws_api_gateway_account.this) == ["eu-west-1"] && length(module.api_gateway_role) == 1
    error_message = "The API Gateway logging role is set in every Region."
  }

  assert {
    condition     = keys(aws_account_alternate_contact.this) == ["SECURITY"] && aws_account_alternate_contact.this["SECURITY"].account_id == null
    error_message = "The security contact is set on the calling account."
  }

  assert {
    condition     = module.naming.tags["Team"] == "platform" && module.naming.tags["Application"] == "platform" && module.naming.tags["Environment"] == "prod"
    error_message = "Caller and governance tags reach the roles."
  }
}

run "roles" {
  command = plan

  assert {
    condition     = module.support_role[0].name == "platform-prod-support-eu-west-1" && module.api_gateway_role[0].name == "platform-prod-apigw-logs-eu-west-1"
    error_message = "Role names are <application>-<environment>-<purpose>-<region>."
  }

  assert {
    condition     = jsondecode(module.support_role[0].trust_policy_json).Statement[0].Principal.AWS == ["arn:aws:iam::123456789012:role/incident-response"] && !can(jsondecode(module.support_role[0].trust_policy_json).Statement[0].Condition)
    error_message = "Only the trusted principals may assume the support role."
  }

  assert {
    condition     = jsondecode(module.api_gateway_role[0].trust_policy_json).Statement[0].Principal.Service == ["apigateway.amazonaws.com"]
    error_message = "Only API Gateway may assume the logging role."
  }
}

run "support_role_requires_mfa" {
  command = plan

  variables {
    support_role = { trusted_principal_arns = ["arn:aws:iam::123456789012:root"], require_mfa = true, max_session_duration = 7200 }
  }

  assert {
    condition     = jsondecode(module.support_role[0].trust_policy_json).Statement[0].Condition.Bool["aws:MultiFactorAuthPresent"] == ["true"]
    error_message = "require_mfa adds the MFA condition."
  }
}

run "api_gateway_account_uses_the_role" {
  command   = apply
  state_key = "apigw"

  assert {
    condition     = aws_api_gateway_account.this["eu-west-1"].cloudwatch_role_arn == "arn:aws:iam::123456789012:role/platform-prod-apigw-logs-eu-west-1" && output.api_gateway_role_arn == aws_api_gateway_account.this["eu-west-1"].cloudwatch_role_arn
    error_message = "API Gateway logs through the module role."
  }
}

run "multiple_regions" {
  command = plan

  variables {
    regions                 = ["eu-west-1", "us-east-1"]
    ebs_default_encryption  = { kms_key_arns = { "us-east-1" = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555" } }
    vpc_block_public_access = { enabled = true, mode = "block-bidirectional" }
  }

  assert {
    condition     = keys(aws_ebs_encryption_by_default.this) == ["eu-west-1", "us-east-1"] && keys(aws_ec2_instance_metadata_defaults.this) == ["eu-west-1", "us-east-1"] && keys(aws_api_gateway_account.this) == ["eu-west-1", "us-east-1"]
    error_message = "Per-Region settings apply in every Region."
  }

  assert {
    condition     = keys(aws_ebs_default_kms_key.this) == ["us-east-1"] && aws_ebs_default_kms_key.this["us-east-1"].region == "us-east-1"
    error_message = "A default EBS key applies only where one is given."
  }

  assert {
    condition     = aws_vpc_block_public_access_options.this["us-east-1"].internet_gateway_block_mode == "block-bidirectional" && aws_vpc_block_public_access_options.this["eu-west-1"].region == "eu-west-1"
    error_message = "VPC block public access uses the configured mode."
  }

  assert {
    condition     = length(module.api_gateway_role) == 1
    error_message = "One API Gateway role serves every Region."
  }
}

run "ecr_basic_scanning" {
  command = plan

  variables {
    ecr_registry_scanning = { type = "BASIC", rules = [{ scan_frequency = "SCAN_ON_PUSH", filters = ["prod-*"] }] }
  }

  assert {
    condition     = aws_ecr_registry_scanning_configuration.this["eu-west-1"].scan_type == "BASIC" && one(one(aws_ecr_registry_scanning_configuration.this["eu-west-1"].rule).repository_filter).filter == "prod-*"
    error_message = "Basic scan on push with filters."
  }
}

run "ecr_replication_skips_the_source_region" {
  command = plan

  variables {
    regions = ["eu-west-1", "eu-central-1"]
    ecr_replication = {
      enabled = true
      rules = [{
        destinations        = [{ region = "eu-central-1" }, { region = "us-east-1", registry_id = "222222222222" }]
        repository_prefixes = ["prod"]
      }]
    }
  }

  assert {
    condition     = length(aws_ecr_replication_configuration.this["eu-west-1"].replication_configuration[0].rule[0].destination) == 2 && aws_ecr_replication_configuration.this["eu-west-1"].replication_configuration[0].rule[0].destination[0].registry_id == "123456789012"
    error_message = "eu-west-1 replicates to both destinations; own registry by default."
  }

  assert {
    condition     = length(aws_ecr_replication_configuration.this["eu-central-1"].replication_configuration[0].rule[0].destination) == 1 && aws_ecr_replication_configuration.this["eu-central-1"].replication_configuration[0].rule[0].destination[0].region == "us-east-1"
    error_message = "A Region never replicates to itself."
  }

  assert {
    condition     = aws_ecr_replication_configuration.this["eu-west-1"].replication_configuration[0].rule[0].repository_filter[0].filter_type == "PREFIX_MATCH"
    error_message = "Repository prefixes filter the rule."
  }
}

run "ecr_replication_without_remote_destination" {
  command = plan

  variables {
    regions         = ["eu-west-1", "eu-central-1"]
    ecr_replication = { enabled = true, rules = [{ destinations = [{ region = "eu-central-1" }] }] }
  }

  assert {
    condition     = keys(aws_ecr_replication_configuration.this) == ["eu-west-1"]
    error_message = "No configuration where every destination is the source."
  }
}

run "ecr_pull_through_cache" {
  command = plan

  variables {
    regions = ["eu-west-1", "us-east-1"]
    ecr_pull_through_cache_rules = {
      ecr-public = { upstream_registry_url = "public.ecr.aws" }
      docker-hub = { upstream_registry_url = "registry-1.docker.io", credential_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:ecr-pullthroughcache/docker-hub", region = "us-east-1" }
    }
  }

  assert {
    condition     = keys(aws_ecr_pull_through_cache_rule.this) == ["eu-west-1/ecr-public", "us-east-1/docker-hub", "us-east-1/ecr-public"]
    error_message = "Rules apply in every Region unless pinned to one."
  }

  assert {
    condition     = aws_ecr_pull_through_cache_rule.this["us-east-1/docker-hub"].region == "us-east-1" && aws_ecr_pull_through_cache_rule.this["us-east-1/docker-hub"].ecr_repository_prefix == "docker-hub"
    error_message = "Pinned rules use their Region and credentials."
  }
}

run "contacts_for_another_account" {
  command = plan

  variables {
    alternate_contacts = {
      account_id = "222222222222"
      security   = { name = "Security Team", title = "Security", email_address = "security@example.com", phone_number = "+1 555 0100" }
      billing    = { name = "Finance", title = "Billing", email_address = "billing@example.com", phone_number = "+1 555 0101" }
    }
    password_policy                  = { enabled = false }
    support_role                     = { enabled = false }
    ebs_default_encryption           = { enabled = false }
    s3_account_public_access_block   = { enabled = false }
    instance_metadata_defaults       = { enabled = false }
    ebs_snapshot_block_public_access = { enabled = false }
    ami_block_public_access          = { enabled = false }
    serial_console_access_block      = { enabled = false }
    api_gateway_logging              = { enabled = false }
    ecr_registry_scanning            = { enabled = false }
  }

  assert {
    condition     = keys(aws_account_alternate_contact.this) == ["BILLING", "SECURITY"] && aws_account_alternate_contact.this["SECURITY"].account_id == "222222222222"
    error_message = "Contacts are set on the member account."
  }

  assert {
    condition     = length(aws_iam_account_password_policy.this) + length(aws_s3_account_public_access_block.this) + length(module.support_role) + length(module.api_gateway_role) + length(aws_ebs_encryption_by_default.this) + length(aws_ec2_instance_metadata_defaults.this) + length(aws_ebs_snapshot_block_public_access.this) + length(aws_ec2_image_block_public_access.this) + length(aws_ec2_serial_console_access.this) + length(aws_api_gateway_account.this) + length(aws_ecr_registry_scanning_configuration.this) == 0
    error_message = "Every switch turns its setting off."
  }

  assert {
    condition     = output.support_role_arn == null && output.api_gateway_role_arn == null
    error_message = "Disabled roles output null."
  }
}

run "contacts_for_the_calling_account_id_fail" {
  command = plan

  variables {
    alternate_contacts = {
      account_id = "123456789012"
      security   = { name = "Security Team", title = "Security", email_address = "security@example.com", phone_number = "+1 555 0100" }
    }
    password_policy                  = { enabled = false }
    support_role                     = { enabled = false }
    ebs_default_encryption           = { enabled = false }
    s3_account_public_access_block   = { enabled = false }
    instance_metadata_defaults       = { enabled = false }
    ebs_snapshot_block_public_access = { enabled = false }
    ami_block_public_access          = { enabled = false }
    serial_console_access_block      = { enabled = false }
    api_gateway_logging              = { enabled = false }
    ecr_registry_scanning            = { enabled = false }
  }

  expect_failures = [aws_account_alternate_contact.this]
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
    environment = "Prod"
  }

  expect_failures = [var.environment]
}

run "rejects_invalid_region" {
  command = plan

  variables {
    regions = ["europe"]
  }

  expect_failures = [var.regions]
}

run "rejects_short_password" {
  command = plan

  variables {
    password_policy = { minimum_password_length = 4 }
  }

  expect_failures = [var.password_policy]
}

run "rejects_invalid_support_principal" {
  command = plan

  variables {
    support_role = { trusted_principal_arns = ["incident-response"] }
  }

  expect_failures = [var.support_role]
}

run "rejects_missing_security_contact" {
  command = plan

  variables {
    alternate_contacts = {}
  }

  expect_failures = [var.alternate_contacts]
}

run "rejects_invalid_contact_account" {
  command = plan

  variables {
    alternate_contacts = {
      enabled    = false
      account_id = "2222"
    }
  }

  expect_failures = [var.alternate_contacts]
}

run "rejects_contact_account_with_other_settings" {
  command = plan

  variables {
    alternate_contacts = {
      account_id = "222222222222"
      security   = { name = "Security Team", title = "Security", email_address = "security@example.com", phone_number = "+1 555 0100" }
    }
  }

  expect_failures = [var.alternate_contacts]
}

run "rejects_ebs_key_in_another_region" {
  command = plan

  variables {
    ebs_default_encryption = { kms_key_arns = { "eu-west-1" = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555" } }
  }

  expect_failures = [var.ebs_default_encryption]
}

run "rejects_invalid_hop_limit" {
  command = plan

  variables {
    instance_metadata_defaults = { http_put_response_hop_limit = 65 }
  }

  expect_failures = [var.instance_metadata_defaults]
}

run "rejects_unblocked_snapshots" {
  command = plan

  variables {
    ebs_snapshot_block_public_access = { state = "unblocked" }
  }

  expect_failures = [var.ebs_snapshot_block_public_access]
}

run "rejects_invalid_vpc_block_mode" {
  command = plan

  variables {
    vpc_block_public_access = { enabled = true, mode = "off" }
  }

  expect_failures = [var.vpc_block_public_access]
}

run "rejects_invalid_scan_frequency" {
  command = plan

  variables {
    ecr_registry_scanning = { type = "BASIC", rules = [{ scan_frequency = "CONTINUOUS_SCAN" }] }
  }

  expect_failures = [var.ecr_registry_scanning]
}

run "rejects_replication_without_rules" {
  command = plan

  variables {
    ecr_replication = { enabled = true }
  }

  expect_failures = [var.ecr_replication]
}

run "rejects_invalid_replication_destination" {
  command = plan

  variables {
    ecr_replication = { rules = [{ destinations = [{ region = "us-east-1", registry_id = "2222" }] }] }
  }

  expect_failures = [var.ecr_replication]
}

run "rejects_invalid_pull_through_prefix" {
  command = plan

  variables {
    ecr_pull_through_cache_rules = { "Docker_Hub/" = { upstream_registry_url = "registry-1.docker.io" } }
  }

  expect_failures = [var.ecr_pull_through_cache_rules]
}

run "rejects_pull_through_region_outside_regions" {
  command = plan

  variables {
    ecr_pull_through_cache_rules = { ecr-public = { upstream_registry_url = "public.ecr.aws", region = "ap-south-1" } }
  }

  expect_failures = [var.ecr_pull_through_cache_rules]
}

run "support_role_trusts_the_account_by_default" {
  command = plan

  variables {
    support_role = {}
  }

  assert {
    condition     = jsondecode(module.support_role[0].trust_policy_json).Statement[0].Principal.AWS == ["arn:aws:iam::123456789012:root"]
    error_message = "Without trusted principals the support role must trust this account."
  }
}

