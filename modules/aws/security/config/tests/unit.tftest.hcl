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

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/platform-prod-config-aggregator-us-east-1"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::platform-prod-config-123456789012-us-east-1"
    }
  }

  mock_resource "aws_config_configuration_aggregator" {
    defaults = {
      arn = "arn:aws:config:eu-west-1:123456789012:config-aggregator/config-aggregator-abcdefgh"
    }
  }
}

variables {
  environment = "prod"
  tags        = { Team = "security" }
  bucket      = { enabled = true }
}

run "recorder_defaults" {
  command = plan

  assert {
    condition     = keys(aws_config_configuration_recorder.this) == ["us-east-1"] && aws_config_configuration_recorder.this["us-east-1"].name == "default" && aws_config_configuration_recorder.this["us-east-1"].role_arn == "arn:aws:iam::123456789012:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig"
    error_message = "One recorder named default in the provider Region with the service-linked role (Config.1)."
  }

  assert {
    condition     = aws_config_configuration_recorder.this["us-east-1"].recording_group[0].all_supported && aws_config_configuration_recorder.this["us-east-1"].recording_group[0].include_global_resource_types && aws_config_configuration_recorder.this["us-east-1"].recording_group[0].recording_strategy[0].use_only == "ALL_SUPPORTED_RESOURCE_TYPES"
    error_message = "The recorder must record every supported type, global types in the provider Region."
  }

  assert {
    condition     = aws_config_configuration_recorder.this["us-east-1"].recording_mode[0].recording_frequency == "CONTINUOUS" && length(aws_config_configuration_recorder.this["us-east-1"].recording_mode[0].recording_mode_override) == 0
    error_message = "Recording must be continuous without an override."
  }

  assert {
    condition     = aws_config_delivery_channel.this["us-east-1"].s3_bucket_name == "platform-prod-config-123456789012-us-east-1" && aws_config_delivery_channel.this["us-east-1"].s3_kms_key_arn == null && aws_config_delivery_channel.this["us-east-1"].s3_key_prefix == null && aws_config_delivery_channel.this["us-east-1"].sns_topic_arn == null
    error_message = "The channel must deliver to the module bucket, no key prefix, no SNS topic, SSE-S3 without a kms input."
  }

  assert {
    condition     = aws_config_delivery_channel.this["us-east-1"].snapshot_delivery_properties[0].delivery_frequency == "TwentyFour_Hours" && aws_config_configuration_recorder_status.this["us-east-1"].is_enabled && aws_config_retention_configuration.this["us-east-1"].retention_period_in_days == 2557
    error_message = "Daily snapshots, recorder started, 2557-day retention."
  }

  assert {
    condition     = output.recorder_names == { "us-east-1" = "default" } && output.service_linked_role_arn == aws_config_configuration_recorder.this["us-east-1"].role_arn
    error_message = "Outputs must expose the recorder names and the service-linked role ARN."
  }

  assert {
    condition     = length(aws_iam_service_linked_role.config) + length(aws_config_configuration_aggregator.this) + length(module.aggregator_role) + length(aws_config_organization_managed_rule.this) + length(aws_config_config_rule.this) + length(aws_config_organization_conformance_pack.this) + length(aws_config_remediation_configuration.this) + length(aws_organizations_aws_service_access.this) + length(aws_organizations_delegated_administrator.this) == 0
    error_message = "Every optional feature must be off by default."
  }
}

run "bucket_secure_defaults" {
  command = plan

  assert {
    condition     = length(module.bucket) == 1 && module.bucket[0].name == "platform-prod-config-123456789012-us-east-1" && output.bucket_name == module.bucket[0].name
    error_message = "storage/s3 bucket <application>-<environment>-config-<account>-<region>."
  }

  assert {
    condition     = module.bucket[0].kms_key_arn == null && output.kms_key_arn == null
    error_message = "No kms input means SSE-S3."
  }

  assert {
    condition     = local.bucket_lifecycle_rules[0].expiration_days == 2557 && local.bucket_lifecycle_rules[0].noncurrent_version_expiration_days == 90 && length(local.bucket_lifecycle_rules[0].transitions) == 0 && !var.bucket.access_logs.enabled
    error_message = "Lifecycle: 2557-day expiration, 90-day noncurrent versions; access logs off by default."
  }

  assert {
    condition     = [for s in jsondecode(module.bucket[0].policy_json).Statement : s.Sid] == ["DenyInsecureTransport", "DenyOutdatedTls", "AWSConfigBucketPermissionsCheck", "AWSConfigBucketExistenceCheck", "AWSConfigBucketDelivery"]
    error_message = "The bucket policy must hold the TLS denies and the AWS Config grants."
  }

  assert {
    condition     = jsondecode(module.bucket[0].policy_json).Statement[1].Condition.NumericLessThan["s3:TlsVersion"] == ["1.2"] && jsondecode(module.bucket[0].policy_json).Statement[4].Resource == ["arn:aws:s3:::platform-prod-config-123456789012-us-east-1/AWSLogs/123456789012/Config/*"] && jsondecode(module.bucket[0].policy_json).Statement[4].Condition.StringEquals["aws:SourceAccount"] == ["123456789012"]
    error_message = "Delivery must be limited to this account's Config prefix, TLS 1.2 or later."
  }

  assert {
    condition     = jsondecode(output.kms_key_policy_json).Statement[0].Principal.Service == ["config.amazonaws.com"] && jsondecode(output.kms_key_policy_json).Statement[0].Action == ["kms:Decrypt", "kms:GenerateDataKey"] && jsondecode(output.kms_key_policy_json).Statement[0].Condition.StringEquals["aws:SourceAccount"] == ["123456789012"]
    error_message = "kms_key_policy_json must grant AWS Config for this account."
  }
}

run "bucket_policy_accounts_and_organization" {
  command = plan

  variables {
    bucket = {
      enabled             = true
      key_prefix          = "/config/"
      allowed_account_ids = ["222222222222"]
      organization_id     = "o-a1b2c3d4e5"
    }
  }

  assert {
    condition     = length(jsondecode(module.bucket[0].policy_json).Statement) == 8 && jsondecode(module.bucket[0].policy_json).Statement[4].Resource == ["arn:aws:s3:::platform-prod-config-123456789012-us-east-1/config/AWSLogs/123456789012/Config/*", "arn:aws:s3:::platform-prod-config-123456789012-us-east-1/config/AWSLogs/222222222222/Config/*"]
    error_message = "Listed accounts must get a delivery path under the key prefix."
  }

  assert {
    condition     = jsondecode(module.bucket[0].policy_json).Statement[7].Resource == ["arn:aws:s3:::platform-prod-config-123456789012-us-east-1/config/AWSLogs/*/Config/*"] && jsondecode(module.bucket[0].policy_json).Statement[7].Condition.StringEquals["aws:SourceOrgID"] == ["o-a1b2c3d4e5"]
    error_message = "The organization must get a delivery grant scoped by aws:SourceOrgID."
  }

  assert {
    condition     = aws_config_delivery_channel.this["us-east-1"].s3_key_prefix == "config"
    error_message = "The channel must use the trimmed key prefix."
  }

  assert {
    condition     = [for s in jsondecode(output.kms_key_policy_json).Statement : s.Sid] == ["AWSConfigKMSPolicy", "AWSConfigKMSPolicyOrganization"] && jsondecode(output.kms_key_policy_json).Statement[0].Condition.StringEquals["aws:SourceAccount"] == ["123456789012", "222222222222"]
    error_message = "The key statements must follow the delivery accounts and organization."
  }
}

run "module_key_is_planned_safely" {
  command = plan

  variables {
    kms = { create = true }
  }

  assert {
    condition     = module.encryption.created && length(aws_config_delivery_channel.this) == 1
    error_message = "kms.create must plan without knowing the key ARN."
  }

  assert {
    condition     = length(module.bucket) == 1 && length(module.bucket[0].name) > 0
    error_message = "The bucket must plan with an unknown module key."
  }
}

run "caller_key_id" {
  command = plan

  variables {
    kms = { key_id = "11111111-2222-3333-4444-555555555555" }
  }

  assert {
    condition     = aws_config_delivery_channel.this["us-east-1"].s3_kms_key_arn == "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555" && module.bucket[0].kms_key_arn == "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    error_message = "A key ID must be used as the key ARN for delivery and the bucket."
  }

  assert {
    condition     = !module.encryption.created && output.kms_key_arn == "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    error_message = "A caller key creates no module key."
  }
}

run "regions_fan_out" {
  command = plan

  variables {
    regions = ["us-east-1", "eu-west-1", "us-east-1"]
  }

  assert {
    condition     = toset(keys(aws_config_configuration_recorder.this)) == toset(["us-east-1", "eu-west-1"]) && aws_config_configuration_recorder.this["eu-west-1"].region == "eu-west-1" && aws_config_delivery_channel.this["eu-west-1"].region == "eu-west-1" && aws_config_retention_configuration.this["eu-west-1"].region == "eu-west-1"
    error_message = "Every distinct Region must get its recorder, channel and retention."
  }

  assert {
    condition     = aws_config_configuration_recorder.this["us-east-1"].recording_group[0].include_global_resource_types && !aws_config_configuration_recorder.this["eu-west-1"].recording_group[0].include_global_resource_types
    error_message = "Global types must be recorded once."
  }
}

run "global_resource_region_override" {
  command = plan

  variables {
    regions  = ["us-east-1", "eu-west-1"]
    recorder = { global_resource_region = "eu-west-1" }
  }

  assert {
    condition     = !aws_config_configuration_recorder.this["us-east-1"].recording_group[0].include_global_resource_types && aws_config_configuration_recorder.this["eu-west-1"].recording_group[0].include_global_resource_types
    error_message = "global_resource_region must move global recording."
  }
}

run "recorder_overrides" {
  command = plan

  variables {
    recorder = {
      name                  = "main"
      delivery_channel_name = "main"
      recording_frequency   = "DAILY"
      recording_mode_override = {
        enabled             = true
        description         = "Instances continuously"
        recording_frequency = "CONTINUOUS"
        resource_types      = ["AWS::EC2::Instance"]
      }
      snapshot_delivery_frequency = "Six_Hours"
      retention_period_in_days    = 365
    }
  }

  assert {
    condition     = aws_config_configuration_recorder.this["us-east-1"].name == "main" && aws_config_delivery_channel.this["us-east-1"].name == "main" && aws_config_configuration_recorder_status.this["us-east-1"].name == "main"
    error_message = "Recorder and channel names must follow the input."
  }

  assert {
    condition     = aws_config_configuration_recorder.this["us-east-1"].recording_mode[0].recording_frequency == "DAILY" && aws_config_configuration_recorder.this["us-east-1"].recording_mode[0].recording_mode_override[0].recording_frequency == "CONTINUOUS" && aws_config_configuration_recorder.this["us-east-1"].recording_mode[0].recording_mode_override[0].resource_types == toset(["AWS::EC2::Instance"])
    error_message = "The recording override must be applied."
  }

  assert {
    condition     = aws_config_delivery_channel.this["us-east-1"].snapshot_delivery_properties[0].delivery_frequency == "Six_Hours" && aws_config_retention_configuration.this["us-east-1"].retention_period_in_days == 365
    error_message = "Snapshot frequency and retention must follow the input."
  }
}

run "existing_bucket" {
  command = plan

  variables {
    bucket = { enabled = false, name = "central-config-delivery" }
  }

  assert {
    condition     = length(module.bucket) == 0
    error_message = "An existing bucket means no bucket resources."
  }

  assert {
    condition     = aws_config_delivery_channel.this["us-east-1"].s3_bucket_name == "central-config-delivery" && output.bucket_name == "central-config-delivery" && output.bucket_arn == "arn:aws:s3:::central-config-delivery"
    error_message = "Delivery must go to the named bucket."
  }
}

run "admin_only_call" {
  command = plan

  variables {
    bucket             = {}
    recorder           = { enabled = false }
    organization_admin = { enabled = true, account_id = "222222222222" }
  }

  assert {
    condition     = toset(keys(aws_organizations_aws_service_access.this)) == toset(["config.amazonaws.com", "config-multiaccountsetup.amazonaws.com"])
    error_message = "Trusted access must be enabled for both AWS Config principals."
  }

  assert {
    condition     = aws_organizations_delegated_administrator.this["config.amazonaws.com"].account_id == "222222222222" && aws_organizations_delegated_administrator.this["config-multiaccountsetup.amazonaws.com"].account_id == "222222222222"
    error_message = "The account must be delegated administrator for both principals."
  }

  assert {
    condition     = length(aws_config_configuration_recorder.this) + length(module.bucket) == 0 && output.bucket_name == null && output.bucket_arn == null && output.recorder_names == {}
    error_message = "An admin-only call records nothing and has no bucket."
  }
}

run "admin_without_trusted_access" {
  command = plan

  variables {
    organization_admin = { enabled = true, account_id = "222222222222", manage_trusted_access = false }
  }

  assert {
    condition     = length(aws_organizations_aws_service_access.this) == 0 && length(aws_organizations_delegated_administrator.this) == 2
    error_message = "manage_trusted_access = false must leave trusted access alone."
  }
}

run "bucket_overrides" {
  command = plan

  variables {
    bucket = {
      enabled = true
      name    = "acme-config-history"
      lifecycle = {
        expiration_days = 3650
        transitions     = [{ days = 90, storage_class = "GLACIER" }]
      }
      access_logs = { enabled = true, bucket = "acme-access-logs" }
    }
  }

  assert {
    condition     = module.bucket[0].name == "acme-config-history" && aws_config_delivery_channel.this["us-east-1"].s3_bucket_name == "acme-config-history"
    error_message = "bucket.name must set the exact bucket name."
  }

  assert {
    condition     = local.bucket_lifecycle_rules[0].expiration_days == 3650 && [for tr in local.bucket_lifecycle_rules[0].transitions : tr.storage_class] == ["GLACIER"]
    error_message = "Lifecycle overrides must be applied."
  }

  assert {
    condition     = var.bucket.access_logs.enabled && var.bucket.access_logs.bucket == "acme-access-logs"
    error_message = "Access logs must go to the target bucket."
  }
}

run "service_linked_role" {
  command = plan

  variables {
    service_linked_role = { enabled = true }
  }

  assert {
    condition     = aws_iam_service_linked_role.config[0].aws_service_name == "config.amazonaws.com" && aws_iam_service_linked_role.config[0].tags["Name"] == "AWSServiceRoleForConfig"
    error_message = "The service-linked role must be created for AWS Config."
  }
}

run "aggregator_defaults" {
  command = plan

  variables {
    aggregator = { enabled = true }
  }

  assert {
    condition     = module.aggregator_role[0].name == "platform-prod-config-aggregator-us-east-1"
    error_message = "The role must be <application>-<environment>-config-aggregator-<region>."
  }

  assert {
    condition     = jsondecode(module.aggregator_role[0].trust_policy_json).Statement[0].Principal.Service == ["config.amazonaws.com"] && jsondecode(module.aggregator_role[0].trust_policy_json).Statement[0].Condition.StringEquals["aws:SourceAccount"] == ["123456789012"]
    error_message = "Only AWS Config in this account may assume the role."
  }

  assert {
    condition     = module.aggregator_role[0].policy_json == null
    error_message = "The role must carry no inline policy, only AWSConfigRoleForOrganizations."
  }

  assert {
    condition     = aws_config_configuration_aggregator.this[0].name == "platform-prod" && aws_config_configuration_aggregator.this[0].organization_aggregation_source[0].all_regions && aws_config_configuration_aggregator.this[0].tags["Name"] == "platform-prod"
    error_message = "The aggregator must cover every Region of the organization."
  }
}

run "aggregator_apply" {
  command   = apply
  state_key = "aggregator"

  variables {
    aggregator = { enabled = true, all_regions = false, regions = ["us-east-1", "eu-west-1"], region = "eu-west-1" }
  }

  assert {
    condition     = aws_config_configuration_aggregator.this[0].region == "eu-west-1" && aws_config_configuration_aggregator.this[0].organization_aggregation_source[0].regions == tolist(["us-east-1", "eu-west-1"])
    error_message = "The aggregator must follow region and regions."
  }

  assert {
    condition     = aws_config_configuration_aggregator.this[0].organization_aggregation_source[0].role_arn == "arn:aws:iam::123456789012:role/platform-prod-config-aggregator-us-east-1" && output.aggregator_role_arn == aws_config_configuration_aggregator.this[0].organization_aggregation_source[0].role_arn && output.aggregator_arn == "arn:aws:config:eu-west-1:123456789012:config-aggregator/config-aggregator-abcdefgh"
    error_message = "The aggregator must use the module role; outputs must expose both ARNs."
  }
}

run "module_key_apply" {
  command   = apply
  state_key = "module_key"

  variables {
    kms = { create = true }
  }

  assert {
    condition     = aws_config_delivery_channel.this["us-east-1"].s3_kms_key_arn == "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555" && module.bucket[0].kms_key_arn == aws_config_delivery_channel.this["us-east-1"].s3_kms_key_arn && output.kms_key_arn == aws_config_delivery_channel.this["us-east-1"].s3_kms_key_arn
    error_message = "The module key must encrypt delivery and the bucket."
  }

  assert {
    condition     = output.bucket_arn == "arn:aws:s3:::platform-prod-config-123456789012-us-east-1"
    error_message = "bucket_arn must be the created bucket."
  }
}

run "organization_rules_full_set" {
  command = plan

  variables {
    organization_rules = { enabled = true }
  }

  assert {
    condition     = length(local.managed_rules) == 209 && length(aws_config_organization_managed_rule.this) == 209 && length(aws_config_config_rule.this) == 0
    error_message = "All 209 rules must be deployed once in the provider Region, as organization rules only."
  }

  assert {
    condition     = alltrue([for key, rule in local.managed_rules : aws_config_organization_managed_rule.this["us-east-1/${key}"].rule_identifier == rule.identifier])
    error_message = "Every rule must use its identifier from rules.tf."
  }

  assert {
    condition     = aws_config_organization_managed_rule.this["us-east-1/required-tags"].name == "platform-prod-required-tags" && jsondecode(aws_config_organization_managed_rule.this["us-east-1/required-tags"].input_parameters) == { tag1Key = "Application", tag2Key = "Environment", tag3Key = "Name", tag4Key = "ManagedBy" }
    error_message = "REQUIRED_TAGS must check the governance tags."
  }

  assert {
    condition     = jsondecode(aws_config_organization_managed_rule.this["us-east-1/iam-password-policy"].input_parameters) == { MinimumPasswordLength = "14", PasswordReusePrevention = "24", MaxPasswordAge = "90", RequireUppercaseCharacters = "true", RequireLowercaseCharacters = "true", RequireSymbols = "true", RequireNumbers = "true" } && jsondecode(aws_config_organization_managed_rule.this["us-east-1/iam-policy-in-use"].input_parameters).policyARN == "arn:aws:iam::aws:policy/AWSSupportAccess"
    error_message = "Shipped parameters must match the library baselines."
  }

  assert {
    condition     = alltrue([for key, rule in local.managed_rules : jsondecode(aws_config_organization_managed_rule.this["us-east-1/${key}"].input_parameters)["requiredKeyTags"] == "Application,Environment,Name,ManagedBy" if contains(keys(rule.input_parameters), "requiredKeyTags")])
    error_message = "Every *_TAGGED rule must require the governance tag keys."
  }

  assert {
    condition     = alltrue([for key, rule in local.managed_rules : aws_config_organization_managed_rule.this["us-east-1/${key}"].maximum_execution_frequency == "TwentyFour_Hours" && aws_config_organization_managed_rule.this["us-east-1/${key}"].resource_types_scope == null if rule.trigger == "Periodic"])
    error_message = "Periodic rules run every 24 hours without scope."
  }

  assert {
    condition     = alltrue([for rule in aws_config_organization_managed_rule.this : length(rule.description) <= 256 && (rule.input_parameters == null ? true : length(rule.input_parameters) <= 1024)])
    error_message = "Descriptions and parameters must fit the API limits."
  }

  assert {
    condition     = aws_config_organization_managed_rule.this["us-east-1/alb-http-drop-invalid-header-enabled"].input_parameters == null && aws_config_organization_managed_rule.this["us-east-1/alb-http-drop-invalid-header-enabled"].excluded_accounts == null
    error_message = "Rules without parameters or exclusions leave them unset."
  }
}

run "organization_rules_tuning" {
  command = plan

  variables {
    regions = ["us-east-1", "eu-west-1"]
    organization_rules = {
      enabled           = true
      excluded_accounts = ["222222222222"]
      disabled_rules    = ["s3-bucket-mfa-delete-enabled", "VPC_ENDPOINT_ENABLED"]
      rule_parameter_overrides = {
        "access-keys-rotated"                = { maxAccessKeyAge = "45" }
        "CW_LOGGROUP_RETENTION_PERIOD_CHECK" = { MinRetentionTime = "731" }
      }
      required_tag_keys   = ["Application", "Owner"]
      required_tag_values = { Owner = "team-a,team-b" }
      additional_rules = {
        "instance-no-public-ip" = { rule_identifier = "EC2_INSTANCE_NO_PUBLIC_IP", regions = ["eu-west-1"], excluded_accounts = [] }
      }
    }
  }

  assert {
    condition     = !contains(keys(aws_config_organization_managed_rule.this), "us-east-1/s3-bucket-mfa-delete-enabled") && length([for key in keys(aws_config_organization_managed_rule.this) : key if strcontains(key, "vpc-endpoint-enabled")]) == 0
    error_message = "disabled_rules must drop rules by key and by identifier."
  }

  assert {
    condition     = jsondecode(aws_config_organization_managed_rule.this["us-east-1/access-keys-rotated"].input_parameters) == { maxAccessKeyAge = "45" } && jsondecode(aws_config_organization_managed_rule.this["eu-west-1/cw-loggroup-retention-period-check"].input_parameters) == { MinRetentionTime = "731" }
    error_message = "Overrides by key and identifier must apply."
  }

  assert {
    condition     = contains(keys(aws_config_organization_managed_rule.this), "us-east-1/access-keys-rotated") && !contains(keys(aws_config_organization_managed_rule.this), "eu-west-1/access-keys-rotated") && contains(keys(aws_config_organization_managed_rule.this), "eu-west-1/alb-http-drop-invalid-header-enabled")
    error_message = "Global rules run once in the global Region; regional rules in every Region."
  }

  assert {
    condition     = jsondecode(aws_config_organization_managed_rule.this["us-east-1/required-tags"].input_parameters) == { tag1Key = "Application", tag2Key = "Owner", tag2Value = "team-a,team-b" }
    error_message = "required_tag_keys and required_tag_values must drive REQUIRED_TAGS."
  }

  assert {
    condition     = aws_config_organization_managed_rule.this["us-east-1/alb-http-drop-invalid-header-enabled"].excluded_accounts == toset(["222222222222"]) && aws_config_organization_managed_rule.this["eu-west-1/instance-no-public-ip"].excluded_accounts == null && !contains(keys(aws_config_organization_managed_rule.this), "us-east-1/instance-no-public-ip")
    error_message = "Exclusions and additional rule Regions must apply."
  }
}

run "organization_rules_own_regions" {
  command = plan

  variables {
    regions            = ["us-east-1", "eu-west-1"]
    organization_rules = { enabled = true, regions = ["eu-west-1"] }
  }

  assert {
    condition     = contains(keys(aws_config_organization_managed_rule.this), "eu-west-1/access-keys-rotated") && length([for key in keys(aws_config_organization_managed_rule.this) : key if startswith(key, "us-east-1/")]) == 0
    error_message = "Global rules move to the first rule Region when the global Region is not listed."
  }

  assert {
    condition     = !contains(keys(aws_config_organization_managed_rule.this), "eu-west-1/cloudfront-viewer-policy-https")
    error_message = "Rules AWS does not offer in a Region must be skipped."
  }
}

run "account_rules" {
  command = plan

  variables {
    account_rules = { enabled = true }
  }

  assert {
    condition     = length(aws_config_config_rule.this) == 209 && length(aws_config_organization_managed_rule.this) == 0
    error_message = "Account rules must deploy the whole set in this account only."
  }

  assert {
    condition     = aws_config_config_rule.this["us-east-1/alb-desync-mode-check"].name == "platform-prod-alb-desync-mode-check" && aws_config_config_rule.this["us-east-1/alb-desync-mode-check"].source[0].source_identifier == "ALB_DESYNC_MODE_CHECK" && aws_config_config_rule.this["us-east-1/alb-desync-mode-check"].scope[0].compliance_resource_types == toset(["AWS::ElasticLoadBalancingV2::LoadBalancer"])
    error_message = "Account rules must use the identifier and the resource scope."
  }

  assert {
    condition     = aws_config_config_rule.this["us-east-1/alb-desync-mode-check"].tags["Name"] == "platform-prod-alb-desync-mode-check" && aws_config_config_rule.this["us-east-1/alb-desync-mode-check"].tags["Team"] == "security"
    error_message = "Account rules must carry caller and governance tags."
  }

  assert {
    condition     = output.account_rule_names["us-east-1/alb-desync-mode-check"] == "platform-prod-alb-desync-mode-check"
    error_message = "account_rule_names must be keyed by <region>/<rule key>."
  }
}

run "conformance_packs" {
  command = plan

  variables {
    regions = ["us-east-1", "eu-west-1"]
    conformance_packs = {
      operational = {
        template_s3_uri   = "s3://awsconfigconforms-templates/operational.yaml"
        input_parameters  = { MaxAge = "90" }
        excluded_accounts = ["222222222222"]
      }
    }
  }

  assert {
    condition     = toset(keys(aws_config_organization_conformance_pack.this)) == toset(["us-east-1/operational", "eu-west-1/operational"]) && aws_config_organization_conformance_pack.this["eu-west-1/operational"].name == "platform-prod-operational"
    error_message = "Packs must be named <application>-<environment>-<key> in every Region."
  }

  assert {
    condition     = aws_config_organization_conformance_pack.this["us-east-1/operational"].excluded_accounts == toset(["222222222222"]) && length(aws_config_organization_conformance_pack.this["us-east-1/operational"].input_parameter) == 1
    error_message = "Pack exclusions and parameters must be applied."
  }
}

run "remediations_manual_by_default" {
  command = plan

  variables {
    remediations = {
      public-buckets = {
        config_rule_name = "platform-prod-s3-bucket-level-public-access-prohibited"
        target_id        = "AWS-ConfigureS3BucketPublicAccessBlock"
        parameters = {
          BucketName = { resource_value = "RESOURCE_ID" }
        }
        execution_controls = { concurrent_execution_rate_percentage = 10, error_percentage = 10 }
      }
    }
  }

  assert {
    condition     = aws_config_remediation_configuration.this["public-buckets"].automatic == false && aws_config_remediation_configuration.this["public-buckets"].target_type == "SSM_DOCUMENT" && aws_config_remediation_configuration.this["public-buckets"].parameter[0].resource_value == "RESOURCE_ID"
    error_message = "Remediations must be manual SSM documents by default."
  }

  assert {
    condition     = aws_config_remediation_configuration.this["public-buckets"].execution_controls[0].ssm_controls[0].error_percentage == 10
    error_message = "Execution controls must be applied."
  }
}

run "automatic_remediation_allowed" {
  command = plan

  variables {
    allow_automatic_remediation = true
    remediations = {
      public-buckets = { config_rule_name = "rule", target_id = "AWS-ConfigureS3BucketPublicAccessBlock", automatic = true, maximum_automatic_attempts = 3, retry_attempt_seconds = 60 }
    }
  }

  assert {
    condition     = aws_config_remediation_configuration.this["public-buckets"].automatic
    error_message = "allow_automatic_remediation must allow automatic remediation."
  }
}

run "naming_truncation_and_tags" {
  command = plan

  variables {
    application   = "a-very-long-application1"
    environment   = "production12"
    tags          = { Team = "security", Application = "spoof", ManagedBy = "someone" }
    account_rules = { enabled = true }
    aggregator    = { enabled = true }
  }

  assert {
    condition     = length(module.bucket[0].name) <= 63 && startswith(module.bucket[0].name, "a-very-long-application1-production12-config") && endswith(module.bucket[0].name, substr(md5("a-very-long-application1-production12-config-123456789012-us-east-1"), 0, 6)) && module.bucket[0].name == local.bucket_name
    error_message = "Long bucket names must be cut with a hash of the full name."
  }

  assert {
    condition     = aws_config_config_rule.this["us-east-1/elasticache-redis-cluster-automatic-backup-check"].name == "${trimsuffix(substr("a-very-long-application1-production12-elasticache-redis-cluster-automatic-backup-check", 0, 57), "-")}-${substr(md5("a-very-long-application1-production12-elasticache-redis-cluster-automatic-backup-check"), 0, 6)}"
    error_message = "Long rule names must be cut to 64 characters with a hash."
  }

  assert {
    condition     = aws_config_configuration_aggregator.this[0].tags["Application"] == "a-very-long-application1" && aws_config_configuration_aggregator.this[0].tags["ManagedBy"] == "Terraform" && aws_config_configuration_aggregator.this[0].tags["Team"] == "security"
    error_message = "Governance tags must win over caller tags."
  }
}

run "rejects_management_account_as_admin" {
  command = plan

  variables {
    organization_admin = { enabled = true, account_id = "123456789012" }
  }

  expect_failures = [aws_organizations_delegated_administrator.this]
}

run "rejects_unlisted_global_resource_region" {
  command = plan

  variables {
    regions = ["eu-west-1"]
  }

  expect_failures = [aws_config_configuration_recorder.this]
}

run "rejects_automatic_remediation_without_opt_in" {
  command = plan

  variables {
    remediations = {
      public-buckets = { config_rule_name = "rule", target_id = "AWS-ConfigureS3BucketPublicAccessBlock", automatic = true }
    }
  }

  expect_failures = [aws_config_remediation_configuration.this]
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
    environment = "prod_1"
  }

  expect_failures = [var.environment]
}

run "rejects_invalid_region" {
  command = plan

  variables {
    regions = ["eu-west"]
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

run "rejects_invalid_kms_key_id" {
  command = plan

  variables {
    kms = { key_id = "alias/config" }
  }

  expect_failures = [var.kms]
}

run "rejects_retention_out_of_range" {
  command = plan

  variables {
    recorder = { retention_period_in_days = 10 }
  }

  expect_failures = [var.recorder]
}

run "rejects_invalid_recording_frequency" {
  command = plan

  variables {
    recorder = { recording_frequency = "HOURLY" }
  }

  expect_failures = [var.recorder]
}

run "rejects_override_without_resource_types" {
  command = plan

  variables {
    recorder = { recording_mode_override = { enabled = true } }
  }

  expect_failures = [var.recorder]
}

run "rejects_recorder_without_bucket" {
  command = plan

  variables {
    bucket = { enabled = false }
  }

  expect_failures = [var.bucket]
}

run "rejects_invalid_bucket_name" {
  command = plan

  variables {
    bucket = { enabled = true, name = "Config_Bucket" }
  }

  expect_failures = [var.bucket]
}

run "rejects_invalid_allowed_account" {
  command = plan

  variables {
    bucket = { enabled = true, allowed_account_ids = ["1234"] }
  }

  expect_failures = [var.bucket]
}

run "rejects_invalid_organization_id" {
  command = plan

  variables {
    bucket = { enabled = true, organization_id = "org-1" }
  }

  expect_failures = [var.bucket]
}

run "rejects_access_logs_without_bucket" {
  command = plan

  variables {
    bucket = { enabled = true, access_logs = { enabled = true } }
  }

  expect_failures = [var.bucket]
}

run "rejects_aggregator_without_regions" {
  command = plan

  variables {
    aggregator = { enabled = true, all_regions = false }
  }

  expect_failures = [var.aggregator]
}

run "rejects_unknown_rule_reference" {
  command = plan

  variables {
    organization_rules = { disabled_rules = ["no-such-rule"] }
  }

  expect_failures = [var.organization_rules]
}

run "rejects_too_many_required_tag_keys" {
  command = plan

  variables {
    organization_rules = { required_tag_keys = ["A", "B", "C", "D", "E", "F", "G"] }
  }

  expect_failures = [var.organization_rules]
}

run "rejects_invalid_additional_rule_key" {
  command = plan

  variables {
    organization_rules = { additional_rules = { Custom_Rule = { rule_identifier = "EC2_INSTANCE_NO_PUBLIC_IP" } } }
  }

  expect_failures = [var.organization_rules]
}

run "rejects_account_and_organization_rules" {
  command = plan

  variables {
    organization_rules = { enabled = true }
    account_rules      = { enabled = true }
  }

  expect_failures = [var.account_rules]
}

run "rejects_pack_with_both_templates" {
  command = plan

  variables {
    conformance_packs = {
      operational = { template_body = "Resources: {}", template_s3_uri = "s3://awsconfigconforms-templates/operational.yaml" }
    }
  }

  expect_failures = [var.conformance_packs]
}

run "rejects_invalid_pack_key" {
  command = plan

  variables {
    conformance_packs = {
      Operational_Pack = { template_body = "Resources: {}" }
    }
  }

  expect_failures = [var.conformance_packs]
}

run "rejects_invalid_admin_account_id" {
  command = plan

  variables {
    organization_admin = { enabled = true, account_id = "1234" }
  }

  expect_failures = [var.organization_admin]
}
