mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_data "aws_regions" {
    defaults = {
      names = ["af-south-1", "ap-east-1", "me-south-1"]
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    }
  }

  mock_resource "aws_guardduty_detector" {
    defaults = {
      id  = "12abc34d567e8fa901bc2d34e56789f0"
      arn = "arn:aws:guardduty:us-east-1:123456789012:detector/12abc34d567e8fa901bc2d34e56789f0"
    }
  }

  mock_resource "aws_guardduty_publishing_destination" {
    defaults = {
      destination_id = "a4b86f27a0e464e4a7e0516d242f1234"
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
    condition     = keys(aws_guardduty_detector.this) == ["us-east-1"] && aws_guardduty_detector.this["us-east-1"].region == "us-east-1" && aws_guardduty_detector.this["us-east-1"].enable
    error_message = "One enabled detector in the provider Region (GuardDuty.1)."
  }

  assert {
    condition     = aws_guardduty_detector.this["us-east-1"].finding_publishing_frequency == "FIFTEEN_MINUTES" && aws_guardduty_organization_configuration.this["us-east-1"].auto_enable_organization_members == "ALL"
    error_message = "Findings publish every 15 minutes; every organization member is auto-enabled."
  }

  assert {
    condition     = aws_guardduty_detector.this["us-east-1"].tags["Name"] == "platform-prod" && aws_guardduty_detector.this["us-east-1"].tags["Application"] == "platform" && aws_guardduty_detector.this["us-east-1"].tags["Team"] == "security" && aws_guardduty_detector.this["us-east-1"].tags["ManagedBy"] == "Terraform"
    error_message = "Detectors carry caller and governance tags; application defaults to platform."
  }

  assert {
    condition     = length(aws_guardduty_filter.this) + length(aws_guardduty_publishing_destination.this) + length(aws_organizations_aws_service_access.this) + length(aws_guardduty_organization_admin_account.this) == 0
    error_message = "No filters, export or organization resources by default."
  }

  assert {
    condition     = output.kms_key_arn == null && output.destination_policy_json == null && output.kms_key_policy_json == null && !module.encryption.created
    error_message = "No export key and no export policies by default."
  }
}

run "every_protection_plan_on_by_default" {
  command = plan

  assert {
    condition     = length(aws_guardduty_detector_feature.this) == 7 && alltrue([for f in values(aws_guardduty_detector_feature.this) : f.status == "ENABLED"])
    error_message = "All seven protection plans are enabled on the detector."
  }

  assert {
    condition     = alltrue([for f in values(aws_guardduty_detector_feature.this) : alltrue([for c in f.additional_configuration : c.status == "ENABLED"])]) && length(aws_guardduty_detector_feature.this["us-east-1/RUNTIME_MONITORING"].additional_configuration) == 3
    error_message = "Runtime Monitoring agents and RDS data risk are enabled."
  }

  assert {
    condition     = alltrue([for f in values(aws_guardduty_organization_configuration_feature.this) : f.auto_enable == "ALL"]) && length(aws_guardduty_organization_configuration_feature.this) == 7
    error_message = "Every plan is auto-enabled for the organization."
  }
}

run "regions_fan_out" {
  command = plan

  variables {
    regions = ["us-east-1", "eu-west-1", "eu-west-1"]
  }

  assert {
    condition     = toset(keys(aws_guardduty_detector.this)) == toset(["us-east-1", "eu-west-1"]) && aws_guardduty_detector.this["eu-west-1"].region == "eu-west-1"
    error_message = "One detector per distinct Region."
  }

  assert {
    condition     = length(aws_guardduty_detector_feature.this) == 14 && length(aws_guardduty_organization_configuration.this) == 2 && length(aws_guardduty_organization_configuration_feature.this) == 14
    error_message = "Plans and organization configuration in every Region."
  }
}

run "disabled_plans_are_set_off" {
  command = plan

  variables {
    features = { runtime_monitoring = false, rds_data_risk = false, ec2_agent_management = false }
  }

  assert {
    condition     = aws_guardduty_detector_feature.this["us-east-1/RUNTIME_MONITORING"].status == "DISABLED" && alltrue([for c in aws_guardduty_detector_feature.this["us-east-1/RUNTIME_MONITORING"].additional_configuration : c.status == "DISABLED"])
    error_message = "A disabled plan and its agents are set DISABLED."
  }

  assert {
    condition     = aws_guardduty_organization_configuration_feature.this["us-east-1/RUNTIME_MONITORING"].auto_enable == "NONE" && alltrue([for c in aws_guardduty_organization_configuration_feature.this["us-east-1/RUNTIME_MONITORING"].additional_configuration : c.auto_enable == "NONE"])
    error_message = "A disabled plan is not auto-enabled."
  }

  assert {
    condition     = aws_guardduty_detector_feature.this["us-east-1/RDS_LOGIN_EVENTS"].status == "ENABLED" && [for c in aws_guardduty_detector_feature.this["us-east-1/RDS_LOGIN_EVENTS"].additional_configuration : c.status] == ["DISABLED"]
    error_message = "RDS data risk can be turned off alone."
  }
}

run "frequency_and_auto_enable" {
  command = plan

  variables {
    detector                         = { finding_publishing_frequency = "ONE_HOUR" }
    auto_enable_organization_members = "NEW"
  }

  assert {
    condition     = aws_guardduty_detector.this["us-east-1"].finding_publishing_frequency == "ONE_HOUR" && aws_guardduty_organization_configuration.this["us-east-1"].auto_enable_organization_members == "NEW" && aws_guardduty_organization_configuration_feature.this["us-east-1/S3_DATA_EVENTS"].auto_enable == "NEW"
    error_message = "Frequency and auto-enable follow the inputs."
  }
}

run "management_account_call" {
  command = plan

  variables {
    regions            = ["us-east-1", "eu-west-1"]
    detector           = { enabled = false }
    organization_admin = { enabled = true, account_id = "210987654321" }
  }

  assert {
    condition     = aws_organizations_aws_service_access.this[0].service_principal == "guardduty.amazonaws.com"
    error_message = "Trusted access for GuardDuty is enabled."
  }

  assert {
    condition     = toset(keys(aws_guardduty_organization_admin_account.this)) == toset(["us-east-1", "eu-west-1"]) && alltrue([for a in values(aws_guardduty_organization_admin_account.this) : a.admin_account_id == "210987654321"])
    error_message = "The same administrator is designated in every Region."
  }

  assert {
    condition     = length(aws_guardduty_detector.this) + length(aws_guardduty_detector_feature.this) + length(aws_guardduty_organization_configuration.this) == 0 && output.detector_ids == {}
    error_message = "The management account call creates no detector."
  }
}

run "management_account_call_without_trusted_access" {
  command = plan

  variables {
    detector           = { enabled = false }
    organization_admin = { enabled = true, account_id = "210987654321", manage_trusted_access = false }
  }

  assert {
    condition     = length(aws_organizations_aws_service_access.this) == 0 && length(aws_guardduty_organization_admin_account.this) == 1
    error_message = "Trusted access can be left to another owner."
  }
}

run "export_module_key_is_planned_safely" {
  command = plan

  variables {
    kms                    = { create = true }
    publishing_destination = { enabled = true, bucket_arn = "arn:aws:s3:::security-findings", prefix = "/guardduty/" }
  }

  assert {
    condition     = module.encryption.created && length(aws_guardduty_publishing_destination.this) == 1
    error_message = "kms.create must plan without knowing the key ARN."
  }

  assert {
    condition     = aws_guardduty_publishing_destination.this["us-east-1"].destination_arn == "arn:aws:s3:::security-findings/guardduty" && aws_guardduty_publishing_destination.this["us-east-1"].destination_type == "S3"
    error_message = "The export targets the bucket and trimmed prefix."
  }

  assert {
    condition     = aws_guardduty_publishing_destination.this["us-east-1"].tags["Name"] == "platform-prod-findings-export"
    error_message = "The export is tagged with its own name."
  }
}

run "export_module_key_encrypts_findings" {
  command = apply

  variables {
    kms                    = { create = true }
    publishing_destination = { enabled = true, bucket_arn = "arn:aws:s3:::security-findings" }
  }

  assert {
    condition     = aws_guardduty_publishing_destination.this["us-east-1"].kms_key_arn == "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555" && output.kms_key_arn == aws_guardduty_publishing_destination.this["us-east-1"].kms_key_arn
    error_message = "The module key encrypts exported findings."
  }

  assert {
    condition     = jsondecode(output.destination_policy_json).Statement[3].Condition.StringNotEquals["s3:x-amz-server-side-encryption-aws-kms-key-id"] == ["arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"]
    error_message = "The bucket policy denies uploads with another key."
  }

  assert {
    condition     = output.publishing_destination_ids == { "us-east-1" = "a4b86f27a0e464e4a7e0516d242f1234" }
    error_message = "Export IDs are output by Region."
  }
}

run "export_with_caller_key_id" {
  command   = plan
  state_key = "caller_key"

  variables {
    regions                = ["us-east-1", "af-south-1"]
    kms                    = { key_id = "99999999-2222-3333-4444-555555555555" }
    publishing_destination = { enabled = true, bucket_arn = "arn:aws:s3:::security-findings" }
  }

  assert {
    condition     = output.kms_key_arn == "arn:aws:kms:us-east-1:123456789012:key/99999999-2222-3333-4444-555555555555" && !module.encryption.created && length(aws_guardduty_publishing_destination.this) == 2
    error_message = "A key ID becomes the key ARN; the export runs in every Region."
  }

  assert {
    condition     = [for s in jsondecode(output.destination_policy_json).Statement : s.Sid] == ["AllowGuardDutyGetBucketLocation", "AllowGuardDutyPutObject", "DenyGuardDutyUnencryptedObjectUploads", "DenyGuardDutyIncorrectEncryptionKey", "DenyInsecureTransport", "DenyOutdatedTls"]
    error_message = "The bucket policy grants GuardDuty and enforces SSE-KMS and TLS."
  }

  assert {
    condition     = jsondecode(output.destination_policy_json).Statement[1].Resource == ["arn:aws:s3:::security-findings/*"] && jsondecode(output.destination_policy_json).Statement[1].Principal.Service == ["guardduty.af-south-1.amazonaws.com", "guardduty.amazonaws.com"]
    error_message = "Opt-in Regions use the Regional GuardDuty principal."
  }

  assert {
    condition     = jsondecode(output.destination_policy_json).Statement[1].Condition.StringEquals["aws:SourceAccount"] == ["123456789012"] && jsondecode(output.destination_policy_json).Statement[1].Condition.ArnLike["aws:SourceArn"] == ["arn:aws:guardduty:us-east-1:123456789012:detector/*", "arn:aws:guardduty:af-south-1:123456789012:detector/*"]
    error_message = "GuardDuty is scoped to this account's detectors."
  }

  assert {
    condition     = jsondecode(output.kms_key_policy_json).Statement[0].Action == ["kms:GenerateDataKey"] && jsondecode(output.kms_key_policy_json).Statement[0].Resource == ["*"] && jsondecode(output.kms_key_policy_json).Statement[0].Condition.StringEquals["aws:SourceAccount"] == ["123456789012"]
    error_message = "The key statement grants only GenerateDataKey, scoped to this account."
  }
}

run "export_policies_only" {
  command   = plan
  state_key = "policies_only"

  variables {
    kms                    = { key_id = "arn:aws:kms:us-east-1:123456789012:key/99999999-2222-3333-4444-555555555555" }
    publishing_destination = { enabled = true, bucket_arn = "arn:aws:s3:::security-findings", policies_only = true }
  }

  assert {
    condition     = length(aws_guardduty_publishing_destination.this) == 0 && output.destination_policy_json != null && output.kms_key_policy_json != null
    error_message = "policies_only outputs the policies without the export."
  }
}

run "kms_without_export_creates_no_key" {
  command = plan

  variables {
    kms = { create = true }
  }

  assert {
    condition     = !module.encryption.created && output.kms_key_arn == null
    error_message = "No key without an export."
  }
}

run "suppression_rules" {
  command = plan

  variables {
    regions = ["us-east-1", "eu-west-1"]
    filters = {
      portscan = {
        description = "Known scanner"
        criteria = {
          type                               = { equals = ["Recon:EC2/Portscan"] }
          "resource.instanceDetails.imageId" = { equals = [], not_equals = ["ami-0123456789abcdef0"] }
          severity                           = { greater_than_or_equal = "4" }
        }
      }
      audit = { action = "NOOP", rank = 50, criteria = { severity = { less_than = "2" } } }
    }
  }

  assert {
    condition     = length(aws_guardduty_filter.this) == 4 && aws_guardduty_filter.this["eu-west-1/portscan"].region == "eu-west-1"
    error_message = "Every filter exists in every Region."
  }

  assert {
    condition     = aws_guardduty_filter.this["us-east-1/portscan"].name == "platform-prod-portscan" && aws_guardduty_filter.this["us-east-1/portscan"].action == "ARCHIVE" && aws_guardduty_filter.this["us-east-1/portscan"].rank == 2 && aws_guardduty_filter.this["us-east-1/audit"].rank == 50
    error_message = "Filters are named <application>-<environment>-<key>, archive by default and rank by key order."
  }

  assert {
    condition     = length(aws_guardduty_filter.this["us-east-1/portscan"].finding_criteria[0].criterion) == 3 && contains([for c in aws_guardduty_filter.this["us-east-1/portscan"].finding_criteria[0].criterion : c.field if c.equals == null && c.not_equals == tolist(["ami-0123456789abcdef0"])], "resource.instanceDetails.imageId")
    error_message = "Empty operator lists are sent as null."
  }

  assert {
    condition     = aws_guardduty_filter.this["us-east-1/portscan"].tags["Name"] == "platform-prod-portscan" && aws_guardduty_filter.this["us-east-1/portscan"].tags["Team"] == "security"
    error_message = "Filters carry their own Name tag."
  }
}

run "long_filter_names_are_truncated" {
  command = plan

  variables {
    application = "observability-platform"
    environment = "production"
    filters = {
      known-scanners-in-the-shared-services-vpc-ranges = { criteria = { type = { equals = ["Recon:EC2/Portscan"] } } }
    }
  }

  assert {
    condition     = length(aws_guardduty_filter.this["us-east-1/known-scanners-in-the-shared-services-vpc-ranges"].name) == 64 && startswith(aws_guardduty_filter.this["us-east-1/known-scanners-in-the-shared-services-vpc-ranges"].name, "observability-platform-production-known-scanners")
    error_message = "Filter names are cut to 64 characters with a hash."
  }
}

run "rejects_application" {
  command = plan

  variables {
    application = "Platform"
  }

  expect_failures = [var.application]
}

run "rejects_environment" {
  command = plan

  variables {
    environment = "p"
  }

  expect_failures = [var.environment]
}

run "rejects_region" {
  command = plan

  variables {
    regions = ["useast1"]
  }

  expect_failures = [var.regions]
}

run "rejects_kms_create_with_key_id" {
  command = plan

  variables {
    kms = { create = true, key_id = "11111111-2222-3333-4444-555555555555" }
  }

  expect_failures = [var.kms]
}

run "rejects_kms_alias" {
  command = plan

  variables {
    kms = { key_id = "alias/guardduty" }
  }

  expect_failures = [var.kms]
}

run "rejects_frequency" {
  command = plan

  variables {
    detector = { finding_publishing_frequency = "DAILY" }
  }

  expect_failures = [var.detector]
}

run "rejects_auto_enable" {
  command = plan

  variables {
    auto_enable_organization_members = "SOME"
  }

  expect_failures = [var.auto_enable_organization_members]
}

run "rejects_export_bucket_arn" {
  command = plan

  variables {
    kms                    = { create = true }
    publishing_destination = { enabled = true, bucket_arn = "arn:aws:s3:::security-findings/guardduty" }
  }

  expect_failures = [var.publishing_destination]
}

run "rejects_export_without_detector" {
  command = plan

  variables {
    detector               = { enabled = false }
    kms                    = { create = true }
    publishing_destination = { enabled = true, bucket_arn = "arn:aws:s3:::security-findings" }
  }

  expect_failures = [var.publishing_destination]
}

run "rejects_export_without_key" {
  command = plan

  variables {
    publishing_destination = { enabled = true, bucket_arn = "arn:aws:s3:::security-findings" }
  }

  expect_failures = [var.publishing_destination]
}

run "rejects_filter_key" {
  command = plan

  variables {
    filters = { Port_Scan = { criteria = { type = { equals = ["Recon:EC2/Portscan"] } } } }
  }

  expect_failures = [var.filters]
}

run "rejects_filter_action" {
  command = plan

  variables {
    filters = { portscan = { action = "SUPPRESS", criteria = { type = { equals = ["Recon:EC2/Portscan"] } } } }
  }

  expect_failures = [var.filters]
}

run "rejects_filter_without_operator" {
  command = plan

  variables {
    filters = { portscan = { criteria = { type = { equals = [] } } } }
  }

  expect_failures = [var.filters]
}

run "rejects_filter_rank" {
  command = plan

  variables {
    filters = { portscan = { rank = 101, criteria = { type = { equals = ["Recon:EC2/Portscan"] } } } }
  }

  expect_failures = [var.filters]
}

run "rejects_filters_without_detector" {
  command = plan

  variables {
    detector = { enabled = false }
    filters  = { portscan = { criteria = { type = { equals = ["Recon:EC2/Portscan"] } } } }
  }

  expect_failures = [var.filters]
}

run "rejects_organization_admin_account_id" {
  command = plan

  variables {
    detector           = { enabled = false }
    organization_admin = { enabled = true, account_id = "12345" }
  }

  expect_failures = [var.organization_admin]
}

run "rejects_organization_admin_with_detector" {
  command = plan

  variables {
    organization_admin = { enabled = true, account_id = "210987654321" }
  }

  expect_failures = [var.organization_admin]
}

run "rejects_management_account_as_administrator" {
  command = plan

  variables {
    detector           = { enabled = false }
    organization_admin = { enabled = true, account_id = "123456789012" }
  }

  expect_failures = [aws_guardduty_organization_admin_account.this]
}
