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
      arn = "arn:aws:iam::123456789012:role/service-role/platform-prod-ssm-dhmc-eu-west-1"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-west-1:123456789012:log-group:/aws/ssm/platform-prod/sessions"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::platform-prod-ssm-inventory-123456789012-eu-west-1"
    }
  }

  mock_resource "aws_ssm_document" {
    defaults = {
      arn = "arn:aws:ssm:eu-west-1:123456789012:document/SSM-SessionManagerRunShell"
    }
  }

  mock_resource "aws_ssm_patch_baseline" {
    defaults = {
      id = "pb-0123456789abcdef0"
    }
  }

  mock_data "aws_ssm_patch_baselines" {
    defaults = {
      baseline_identities = [
        {
          baseline_id          = "arn:aws:ssm:eu-west-1:080255945899:patchbaseline/pb-0b8d4f5a6e3c2a1d7"
          baseline_name        = "AWS-AmazonLinux2023DefaultPatchBaseline"
          baseline_description = "Default Patch Baseline for Amazon Linux 2023 Provided by AWS."
          default_baseline     = true
          operating_system     = "AMAZON_LINUX_2023"
        },
        {
          baseline_id          = "arn:aws:ssm:eu-west-1:080255945899:patchbaseline/pb-06e3563bd35503f2b"
          baseline_name        = "AWS-UbuntuDefaultPatchBaseline"
          baseline_description = "Default Patch Baseline for Ubuntu Provided by AWS."
          default_baseline     = true
          operating_system     = "UBUNTU"
        },
        {
          baseline_id          = "arn:aws:ssm:eu-west-1:080255945899:patchbaseline/pb-0574b43a65ea646ed"
          baseline_name        = "AWS-DefaultPatchBaseline"
          baseline_description = "Default Patch Baseline Provided by AWS."
          default_baseline     = true
          operating_system     = "WINDOWS"
        },
      ]
    }
  }

  mock_resource "aws_ssmquicksetup_configuration_manager" {
    defaults = {
      manager_arn = "arn:aws:ssm-quicksetup:eu-west-1:123456789012:configuration-manager/11111111-2222-3333-4444-555555555555"
    }
  }
}

variables {
  environment = "prod"
  tags        = { Team = "platform" }
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = aws_ssm_service_setting.document_public_sharing["eu-west-1"].setting_value == "Disable" && aws_ssm_service_setting.document_public_sharing["eu-west-1"].setting_id == "/ssm/documents/console/public-sharing-permission"
    error_message = "Public document sharing must be blocked (SSM.7)."
  }

  assert {
    condition     = module.automation_log_group["eu-west-1"].name == "/aws/ssm/platform-prod/automation" && aws_ssm_service_setting.automation_log_group["eu-west-1"].setting_value == "/aws/ssm/platform-prod/automation" && aws_ssm_service_setting.automation_log_destination["eu-west-1"].setting_value == "CloudWatch"
    error_message = "Automation output must go to the module log group (SSM.6)."
  }

  assert {
    condition     = module.automation_log_group["eu-west-1"].retention_in_days == 365 && module.session_log_group["eu-west-1"].retention_in_days == 365 && module.session_log_group["eu-west-1"].kms_key_arn == null
    error_message = "Logs keep 365 days with service encryption by default."
  }

  assert {
    condition     = keys(output.kms_key_arns) == ["eu-west-1"] && output.kms_key_arns["eu-west-1"] == null
    error_message = "No kms input means AWS managed encryption."
  }

  assert {
    condition     = jsondecode(aws_ssm_document.session_manager["eu-west-1"].content).inputs.kmsKeyId == "" && jsondecode(aws_ssm_document.session_manager["eu-west-1"].content).inputs.cloudWatchEncryptionEnabled && jsondecode(aws_ssm_document.session_manager["eu-west-1"].content).inputs.cloudWatchLogGroupName == "/aws/ssm/platform-prod/sessions"
    error_message = "Sessions log to the encrypted session log group; no KMS session key by default."
  }

  assert {
    condition     = jsondecode(aws_ssm_document.session_manager["eu-west-1"].content).inputs.idleSessionTimeout == "20" && jsondecode(aws_ssm_document.session_manager["eu-west-1"].content).inputs.maxSessionDuration == "60" && !jsondecode(aws_ssm_document.session_manager["eu-west-1"].content).inputs.runAsEnabled
    error_message = "Sessions end after 20 idle and 60 total minutes and run as ssm-user."
  }

  assert {
    condition     = aws_ssm_document.session_manager["eu-west-1"].name == "SSM-SessionManagerRunShell" && aws_ssm_document.session_manager["eu-west-1"].document_type == "Session"
    error_message = "Preferences live in SSM-SessionManagerRunShell."
  }

  assert {
    condition     = aws_ssmquicksetup_configuration_manager.patch_policy[0].name == "platform-prod-patch-policy" && aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].type == "AWSQuickSetupType-PatchPolicy" && aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["PatchPolicyName"] == "platform-prod-patch-policy"
    error_message = "One Quick Setup patch policy named <application>-<environment>-patch-policy."
  }

  assert {
    condition     = aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["ConfigurationOptionsPatchOperation"] == "ScanAndInstall" && aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["ConfigurationOptionsScanValue"] == "cron(0 1 * * ? *)" && aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["ConfigurationOptionsInstallValue"] == "cron(0 2 ? * SUN *)" && aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["RebootOption"] == "RebootIfNeeded"
    error_message = "Daily scan at 01:00 UTC, weekly install on Sunday 02:00 UTC with reboot if needed (SSM.2)."
  }

  assert {
    condition     = aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["ConfigurationOptionsScanNextInterval"] == "false" && aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["ConfigurationOptionsInstallNextInterval"] == "true"
    error_message = "New nodes are scanned at once and patched in the next install window."
  }

  assert {
    condition     = aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["TargetType"] == "*" && aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["TargetAccounts"] == "123456789012" && aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["TargetRegions"] == "eu-west-1"
    error_message = "The patch policy targets every node of this account in the module Regions."
  }

  assert {
    condition     = length(setintersection(keys(aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters), ["TargetOrganizationalUnits", "TargetTagKey", "TargetTagValue", "ResourceGroupName", "TargetInstances", "OutputS3Location"])) == 0
    error_message = "No OU, tag, resource group, instance or S3 log parameters by default."
  }

  assert {
    condition     = aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["OutputLogEnableS3"] == "false" && aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["IsPolicyAttachAllowed"] == "false"
    error_message = "No S3 output and no policy attachment to existing instance profiles by default."
  }

  assert {
    condition     = aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["PatchBaselineUseDefault"] == "default" && aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["PatchBaselineRegion"] == "eu-west-1" && length(aws_ssm_patch_baseline.this) == 0
    error_message = "AWS default baselines from the provider Region; no custom baselines."
  }

  assert {
    condition = jsondecode(aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["SelectedPatchBaselines"]) == {
      AMAZON_LINUX_2023 = { value = "arn:aws:ssm:eu-west-1:080255945899:patchbaseline/pb-0b8d4f5a6e3c2a1d7", label = "AWS-AmazonLinux2023DefaultPatchBaseline", description = "Default Patch Baseline for Amazon Linux 2023 Provided by AWS.", disabled = false }
      UBUNTU            = { value = "arn:aws:ssm:eu-west-1:080255945899:patchbaseline/pb-06e3563bd35503f2b", label = "AWS-UbuntuDefaultPatchBaseline", description = "Default Patch Baseline for Ubuntu Provided by AWS.", disabled = false }
      WINDOWS           = { value = "arn:aws:ssm:eu-west-1:080255945899:patchbaseline/pb-0574b43a65ea646ed", label = "AWS-DefaultPatchBaseline", description = "Default Patch Baseline Provided by AWS.", disabled = false }
    }
    error_message = "SelectedPatchBaselines lists the AWS default baseline per operating system."
  }

  assert {
    condition     = aws_ssm_association.inventory["eu-west-1"].association_name == "platform-prod-inventory" && aws_ssm_association.agent_update["eu-west-1"].association_name == "platform-prod-ssm-agent-update" && aws_ssm_association.inventory["eu-west-1"].targets[0].values == tolist(["*"])
    error_message = "Inventory and agent update associations cover every managed node."
  }

  assert {
    condition     = length(aws_ssm_resource_data_sync.this) + length(module.bucket) + length(aws_ssmquicksetup_configuration_manager.host_management) + length(aws_organizations_delegated_administrator.ssm) + length(aws_organizations_aws_service_access.ssm) == 0
    error_message = "No sync, bucket, Quick Setup or organization resources by default."
  }

  assert {
    condition     = aws_ssmquicksetup_configuration_manager.patch_policy[0].tags["Team"] == "platform" && aws_ssmquicksetup_configuration_manager.patch_policy[0].tags["Application"] == "platform" && aws_ssmquicksetup_configuration_manager.patch_policy[0].tags["Environment"] == "prod" && aws_ssmquicksetup_configuration_manager.patch_policy[0].tags["Name"] == "platform-prod-patch-policy" && aws_ssm_document.session_manager["eu-west-1"].tags["ManagedBy"] == "Terraform"
    error_message = "Caller and governance tags must be applied."
  }
}

run "roles" {
  command = plan

  assert {
    condition     = module.dhmc_role[0].name == "platform-prod-ssm-dhmc-eu-west-1" && aws_ssm_service_setting.default_host_management["eu-west-1"].setting_value == "service-role/platform-prod-ssm-dhmc-eu-west-1"
    error_message = "DHMC role is <application>-<environment>-ssm-dhmc-<region> under service-role/ (SSM.1)."
  }

  assert {
    condition     = jsondecode(module.dhmc_role[0].trust_policy_json).Statement[0].Principal.Service == ["ssm.amazonaws.com"]
    error_message = "The DHMC role is trusted by Systems Manager only."
  }

  assert {
    condition     = [for s in jsondecode(module.dhmc_role[0].policy_json).Statement : s.Sid] == ["WriteSessionLogs", "CheckSessionLogGroupEncryption"] && contains(jsondecode(module.dhmc_role[0].policy_json).Statement[0].Resource, "arn:aws:logs:eu-west-1:123456789012:log-group:/aws/ssm/platform-prod/sessions:*")
    error_message = "Without a key the DHMC role only writes session logs."
  }

  assert {
    condition     = module.patch_administration_role[0].name == "platform-prod-ssm-patch-admin-eu-west-1" && module.patch_execution_role[0].name == "platform-prod-ssm-patch-exec-eu-west-1"
    error_message = "Patch policy roles are <application>-<environment>-ssm-patch-admin|exec-<region>."
  }

  assert {
    condition     = jsondecode(module.patch_administration_role[0].trust_policy_json).Statement[0].Principal.Service == ["cloudformation.amazonaws.com"] && jsondecode(module.patch_administration_role[0].trust_policy_json).Statement[0].Condition.StringEquals["aws:SourceAccount"] == ["123456789012"] && jsondecode(module.patch_administration_role[0].trust_policy_json).Statement[0].Condition.ArnLike["aws:SourceArn"] == ["arn:aws:cloudformation:*:123456789012:stackset/AWS-QuickSetup-*"]
    error_message = "The administration role is trusted by CloudFormation for this account's Quick Setup stack sets only."
  }

  assert {
    condition     = jsondecode(module.patch_administration_role[0].policy_json).Statement == [{ Sid = "AssumePatchPolicyExecutionRole", Effect = "Allow", Action = ["sts:AssumeRole"], Resource = ["arn:aws:iam::123456789012:role/platform-prod-ssm-patch-exec-eu-west-1"] }]
    error_message = "The administration role may only assume the execution role."
  }

  assert {
    condition     = module.patch_execution_role[0].policy_json == null && aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].local_deployment_execution_role_name == module.patch_execution_role[0].name
    error_message = "The execution role has no inline policy and is the patch policy's execution role."
  }

  assert {
    condition     = local.dhmc_managed_policy_arns == ["arn:aws:iam::aws:policy/AmazonSSMManagedEC2InstanceDefaultPolicy", "arn:aws:iam::aws:policy/AWSQuickSetupPatchPolicyBaselineAccess"]
    error_message = "DHMC nodes may read the patch policy baselines."
  }
}

run "patch_policy_role_wiring" {
  command   = apply
  state_key = "patch_roles"

  override_resource {
    target = module.patch_administration_role[0].aws_iam_role.this
    values = {
      arn = "arn:aws:iam::123456789012:role/platform-prod-ssm-patch-admin-eu-west-1"
    }
  }

  assert {
    condition     = aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].local_deployment_administration_role_arn == "arn:aws:iam::123456789012:role/platform-prod-ssm-patch-admin-eu-west-1" && output.patch_policy_administration_role_arn == module.patch_administration_role[0].arn
    error_message = "The patch policy uses the module administration role."
  }

  assert {
    condition     = jsondecode(module.patch_execution_role[0].trust_policy_json).Statement[0].Principal.AWS == ["arn:aws:iam::123456789012:role/platform-prod-ssm-patch-admin-eu-west-1"] && !can(jsondecode(module.patch_execution_role[0].trust_policy_json).Statement[0].Principal.Service)
    error_message = "Only the administration role may assume the execution role."
  }

  assert {
    condition     = output.patch_policy_manager_arn == "arn:aws:ssm-quicksetup:eu-west-1:123456789012:configuration-manager/11111111-2222-3333-4444-555555555555"
    error_message = "The patch policy manager ARN is exported."
  }
}

run "module_key_is_planned_safely" {
  command = plan

  variables {
    kms              = { create = true }
    inventory_bucket = { enabled = true }
  }

  assert {
    condition     = length([for e in module.encryption : e if e.created]) == 1
    error_message = "kms.create must plan without knowing the key ARN."
  }
}

run "module_key_encrypts_logs_sessions_and_bucket" {
  command   = apply
  state_key = "kms"

  variables {
    kms              = { create = true }
    inventory_bucket = { enabled = true }
    inventory        = { resource_data_sync = { enabled = true } }
  }

  assert {
    condition     = module.session_log_group["eu-west-1"].kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && module.automation_log_group["eu-west-1"].kms_key_arn == module.session_log_group["eu-west-1"].kms_key_arn
    error_message = "The module key must encrypt both log groups."
  }

  assert {
    condition     = jsondecode(aws_ssm_document.session_manager["eu-west-1"].content).inputs.kmsKeyId == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    error_message = "The module key must encrypt session data."
  }

  assert {
    condition     = contains([for s in jsondecode(module.dhmc_role[0].policy_json).Statement : s.Sid], "DecryptSessionData")
    error_message = "Nodes must be able to decrypt session data."
  }

  assert {
    condition     = module.bucket[0].kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    error_message = "The bucket uses the module key (SSE-KMS)."
  }

  assert {
    condition     = aws_ssm_resource_data_sync.this["eu-west-1"].s3_destination[0].kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && aws_ssm_resource_data_sync.this["eu-west-1"].s3_destination[0].bucket_name == "platform-prod-ssm-inventory-123456789012-eu-west-1"
    error_message = "The sync writes to the module bucket with the module key."
  }

  assert {
    condition     = jsondecode(module.bucket[0].policy_json).Statement[3].Condition.StringEquals["s3:x-amz-server-side-encryption"] == ["aws:kms"] && jsondecode(module.bucket[0].policy_json).Statement[3].Condition.StringEquals["s3:x-amz-server-side-encryption-aws-kms-key-id"] == ["arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"]
    error_message = "Delivery must require SSE-KMS when a key is used."
  }
}

run "multi_region_key_id" {
  command = plan

  variables {
    regions = ["eu-west-1", "us-east-1"]
    kms     = { key_id = "mrk-1234567890abcdef1234567890abcdef" }
  }

  assert {
    condition     = output.kms_key_arns["us-east-1"] == "arn:aws:kms:us-east-1:123456789012:key/mrk-1234567890abcdef1234567890abcdef" && output.kms_key_arns["eu-west-1"] == "arn:aws:kms:eu-west-1:123456789012:key/mrk-1234567890abcdef1234567890abcdef"
    error_message = "An mrk- key ID resolves to the replica in each Region."
  }

  assert {
    condition     = module.session_log_group["us-east-1"].kms_key_arn == "arn:aws:kms:us-east-1:123456789012:key/mrk-1234567890abcdef1234567890abcdef"
    error_message = "Each Region's logs use that Region's key."
  }

  assert {
    condition     = length(aws_ssm_service_setting.document_public_sharing) == 2 && length(module.dhmc_role) == 1 && length(aws_ssmquicksetup_configuration_manager.patch_policy) == 1
    error_message = "Regional resources repeat per Region; roles and the patch policy are global."
  }

  assert {
    condition     = aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["TargetRegions"] == "eu-west-1,us-east-1" && aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["PatchBaselineRegion"] == "eu-west-1"
    error_message = "One patch policy covers every Region; baselines come from the provider Region."
  }
}

run "inventory_bucket" {
  command = plan

  variables {
    inventory_bucket = {
      enabled             = true
      allowed_account_ids = ["222222222222"]
      organization_id     = "o-abc123def4"
      access_logs         = { enabled = true, bucket = "platform-prod-access-logs" }
    }
    inventory = { resource_data_sync = { enabled = true, organization = true } }
  }

  assert {
    condition     = module.bucket[0].name == "platform-prod-ssm-inventory-123456789012-eu-west-1" && output.inventory_bucket_name == module.bucket[0].name
    error_message = "Bucket is <application>-<environment>-ssm-inventory-<account>-<region>."
  }

  assert {
    condition     = module.bucket[0].kms_key_arn == null
    error_message = "Without a key the bucket uses SSE-S3."
  }

  assert {
    condition     = [for s in jsondecode(module.bucket[0].policy_json).Statement : s.Sid] == ["DenyInsecureTransport", "DenyOutdatedTls", "SSMBucketPermissionsCheck", "SSMBucketDelivery", "SSMBucketDeliveryTagging", "SSMBucketPermissionsCheckOrganization", "SSMBucketDeliveryOrganization", "SSMBucketDeliveryTaggingOrganization"]
    error_message = "Bucket policy: TLS guards first, then account and organization delivery."
  }

  assert {
    condition     = jsondecode(module.bucket[0].policy_json).Statement[3].Condition.StringEquals["aws:SourceAccount"] == ["123456789012", "222222222222"] && jsondecode(module.bucket[0].policy_json).Statement[3].Resource == ["arn:aws:s3:::platform-prod-ssm-inventory-123456789012-eu-west-1/inventory/*/accountid=123456789012/*", "arn:aws:s3:::platform-prod-ssm-inventory-123456789012-eu-west-1/inventory/*/accountid=222222222222/*"] && !can(jsondecode(module.bucket[0].policy_json).Statement[3].Condition.StringEquals["s3:x-amz-server-side-encryption"])
    error_message = "Delivery is limited to the listed accounts; no KMS condition without a key."
  }

  assert {
    condition     = aws_ssm_resource_data_sync.this["eu-west-1"].s3_destination[0].kms_key_arn == null && aws_ssm_resource_data_sync.this["eu-west-1"].s3_destination[0].destination_data_sharing[0].destination_data_sharing_type == "Organization" && output.resource_data_sync_name == "platform-prod-inventory"
    error_message = "The organization sync writes to the module bucket."
  }
}

run "bucket_name_truncation" {
  command = plan

  variables {
    application      = "a23456789012345678901234"
    environment      = "abcdefghijkl"
    inventory_bucket = { enabled = true }
  }

  assert {
    condition     = length(module.bucket[0].name) == 63 && startswith(module.bucket[0].name, "a23456789012345678901234-abcdefghijkl-ssm-inventory-")
    error_message = "Long bucket names are truncated to 63 characters with a hash."
  }
}

run "external_sync_bucket" {
  command = plan

  variables {
    inventory = {
      resource_data_sync = {
        enabled       = true
        bucket_name   = "central-inventory"
        bucket_region = "us-east-1"
        kms_key_arn   = "arn:aws:kms:us-east-1:123456789012:key/99999999-2222-3333-4444-555555555555"
        prefix        = "/inv/"
      }
    }
  }

  assert {
    condition     = aws_ssm_resource_data_sync.this["eu-west-1"].s3_destination[0].bucket_name == "central-inventory" && aws_ssm_resource_data_sync.this["eu-west-1"].s3_destination[0].region == "us-east-1" && aws_ssm_resource_data_sync.this["eu-west-1"].s3_destination[0].prefix == "inv"
    error_message = "The sync writes to the external bucket."
  }

  assert {
    condition     = aws_ssm_resource_data_sync.this["eu-west-1"].s3_destination[0].kms_key_arn == "arn:aws:kms:us-east-1:123456789012:key/99999999-2222-3333-4444-555555555555" && length(module.bucket) == 0
    error_message = "The sync uses the bucket's key; no module bucket."
  }
}

run "session_s3_logs_and_run_as" {
  command = plan

  variables {
    session_manager = {
      run_as_enabled       = true
      run_as_default_user  = "ec2-user"
      idle_session_timeout = 10
      s3_logs = {
        enabled     = true
        bucket      = "platform-prod-session-logs"
        prefix      = "/ssm/"
        kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/99999999-2222-3333-4444-555555555555"
      }
    }
  }

  assert {
    condition     = jsondecode(aws_ssm_document.session_manager["eu-west-1"].content).inputs.s3BucketName == "platform-prod-session-logs" && jsondecode(aws_ssm_document.session_manager["eu-west-1"].content).inputs.s3KeyPrefix == "ssm" && jsondecode(aws_ssm_document.session_manager["eu-west-1"].content).inputs.runAsDefaultUser == "ec2-user"
    error_message = "S3 logs and run-as preferences reach the Session document."
  }

  assert {
    condition     = [for s in jsondecode(module.dhmc_role[0].policy_json).Statement : s.Sid] == ["WriteSessionLogs", "CheckSessionLogGroupEncryption", "WriteSessionLogObjects", "CheckSessionLogBucketEncryption", "EncryptSessionLogObjects"]
    error_message = "S3 session logs add only the S3 and key permissions."
  }

  assert {
    condition     = jsondecode(module.dhmc_role[0].policy_json).Statement[2].Resource == ["arn:aws:s3:::platform-prod-session-logs/ssm/*"]
    error_message = "Session log uploads are limited to the prefix."
  }
}

run "custom_baselines_plan_safely" {
  command = plan

  variables {
    kms = { create = true }
    patching = {
      baselines = {
        use_default = false
        custom = {
          amazon-linux-2023 = { operating_system = "AMAZON_LINUX_2023" }
          ubuntu            = { operating_system = "UBUNTU" }
        }
      }
    }
  }

  assert {
    condition     = length(aws_ssm_patch_baseline.this) == 2 && length(aws_ssmquicksetup_configuration_manager.patch_policy) == 1 && aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["PatchBaselineUseDefault"] == "custom"
    error_message = "Custom baselines plan before their IDs are known."
  }
}

run "custom_baselines" {
  command   = apply
  state_key = "custom_baselines"

  variables {
    patching = {
      baselines = {
        use_default = false
        custom = {
          amazon-linux-2023 = { operating_system = "AMAZON_LINUX_2023" }
          ubuntu            = { operating_system = "UBUNTU" }
          windows           = { operating_system = "WINDOWS", approve_after_days = 3, rejected_patches = ["KB123456"] }
          oracle            = { operating_system = "ORACLE_LINUX", patch_filters = { CLASSIFICATION = ["Security"] } }
        }
      }
    }
  }

  assert {
    condition     = aws_ssm_patch_baseline.this["amazon-linux-2023"].name == "platform-prod-amazon-linux-2023" && aws_ssm_patch_baseline.this["amazon-linux-2023"].approval_rule[0].approve_after_days == 7 && aws_ssm_patch_baseline.this["ubuntu"].approval_rule[0].approve_after_days == 0
    error_message = "Security baselines: Amazon Linux 2023 after 7 days, Ubuntu at once."
  }

  assert {
    condition     = aws_ssm_patch_baseline.this["windows"].approval_rule[0].approve_after_days == 3 && aws_ssm_patch_baseline.this["windows"].approval_rule[0].patch_filter[0].key == "CLASSIFICATION" && aws_ssm_patch_baseline.this["windows"].rejected_patches_action == "BLOCK"
    error_message = "Windows baseline: critical and security updates, rejected patches blocked."
  }

  assert {
    condition     = aws_ssm_patch_baseline.this["ubuntu"].tags["Name"] == "platform-prod-ubuntu" && aws_ssm_patch_baseline.this["ubuntu"].tags["Team"] == "platform" && output.patch_baseline_ids["oracle"] == "pb-0123456789abcdef0"
    error_message = "Custom baselines are named, tagged and exported."
  }

  assert {
    condition     = aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["PatchBaselineUseDefault"] == "custom"
    error_message = "The patch policy uses the custom baselines."
  }

  assert {
    condition     = jsondecode(aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["SelectedPatchBaselines"]).WINDOWS == { value = "pb-0123456789abcdef0", label = "platform-prod-windows", description = "Security patch baseline for WINDOWS.", disabled = false }
    error_message = "A custom baseline replaces the AWS default for its operating system."
  }

  assert {
    condition     = keys(jsondecode(aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["SelectedPatchBaselines"])) == ["AMAZON_LINUX_2023", "ORACLE_LINUX", "UBUNTU", "WINDOWS"] && jsondecode(aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["SelectedPatchBaselines"]).ORACLE_LINUX.label == "platform-prod-oracle"
    error_message = "Custom baselines join the AWS defaults of the other operating systems."
  }
}

run "tag_targets_and_scan_only" {
  command = plan

  variables {
    patching = {
      operation     = "Scan"
      reboot_option = "NoReboot"
      target        = { type = "Tags", tag_key = "Patch", tag_value = "web" }
    }
  }

  assert {
    condition     = aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["TargetType"] == "Tags" && aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["TargetTagKey"] == "Patch" && aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["TargetTagValue"] == "web"
    error_message = "Tag targeting passes the tag key and value."
  }

  assert {
    condition     = aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["ConfigurationOptionsPatchOperation"] == "Scan" && !contains(keys(aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters), "ConfigurationOptionsInstallValue") && !contains(keys(aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters), "ConfigurationOptionsInstallNextInterval")
    error_message = "Scan-only policies carry no install schedule."
  }

  assert {
    condition     = aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["RebootOption"] == "NoReboot"
    error_message = "The reboot option reaches the patch policy."
  }
}

run "resource_group_targets" {
  command = plan

  variables {
    patching = {
      target = { type = "ResourceGroups", resource_group_name = "web-servers" }
    }
  }

  assert {
    condition     = aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["TargetType"] == "ResourceGroups" && aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["ResourceGroupName"] == "web-servers" && !contains(keys(aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters), "TargetTagKey")
    error_message = "Resource group targeting passes the group name only."
  }
}

run "instance_targets" {
  command = plan

  variables {
    patching = {
      target = { type = "InstanceIds", instance_ids = ["i-0123456789abcdef0", "i-0fedcba9876543210"] }
    }
  }

  assert {
    condition     = aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["TargetType"] == "InstanceIds" && aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["TargetInstances"] == "i-0123456789abcdef0,i-0fedcba9876543210"
    error_message = "Instance targeting passes a comma-separated ID list."
  }
}

run "organization_patch_policy" {
  command = plan

  variables {
    account_settings   = { enabled = false }
    session_manager    = { enabled = false }
    inventory          = { enabled = false }
    agent_update       = { enabled = false }
    organization_admin = { enabled = true, account_id = "222222222222" }
    regions            = ["eu-west-1", "eu-central-1"]
    patching = {
      target_organizational_units = ["ou-ab12-abcdefgh", "ou-ab12-ijklmnop"]
    }
  }

  assert {
    condition     = aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["TargetOrganizationalUnits"] == "ou-ab12-abcdefgh,ou-ab12-ijklmnop" && aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["TargetRegions"] == "eu-west-1,eu-central-1"
    error_message = "The patch policy targets the OUs in the module Regions."
  }

  assert {
    condition     = !contains(keys(aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters), "TargetAccounts")
    error_message = "OU policies do not set TargetAccounts."
  }

  assert {
    condition     = length(module.patch_administration_role) == 1 && length(module.patch_execution_role) == 1 && aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].local_deployment_execution_role_name == "platform-prod-ssm-patch-exec-eu-west-1"
    error_message = "Organization patch policies still need the local deployment roles."
  }

  assert {
    condition     = length(module.dhmc_role) == 0 && length(aws_organizations_delegated_administrator.ssm) == 1
    error_message = "An OU patch policy runs in the management-account call."
  }
}

run "patch_output_logs" {
  command = plan

  variables {
    patching = {
      attach_instance_policies = true
      output_logs              = { enabled = true, bucket = "platform-prod-patch-logs", prefix = "/patching/" }
    }
  }

  assert {
    condition     = aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["OutputLogEnableS3"] == "true" && jsondecode(aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["OutputS3Location"]) == { OutputBucketRegion = "eu-west-1", OutputS3BucketName = "platform-prod-patch-logs", OutputS3KeyPrefix = "patching" }
    error_message = "Patch output goes to the bucket and prefix."
  }

  assert {
    condition     = aws_ssmquicksetup_configuration_manager.patch_policy[0].configuration_definition[0].parameters["IsPolicyAttachAllowed"] == "true"
    error_message = "attach_instance_policies lets Quick Setup extend existing instance profiles."
  }

  assert {
    condition     = [for s in jsondecode(module.dhmc_role[0].policy_json).Statement : s.Sid] == ["WriteSessionLogs", "CheckSessionLogGroupEncryption", "WritePatchLogObjects", "CheckPatchLogBucketEncryption"]
    error_message = "DHMC nodes may write patch output."
  }

  assert {
    condition     = jsondecode(module.dhmc_role[0].policy_json).Statement[2].Resource == ["arn:aws:s3:::platform-prod-patch-logs/patching/*"] && jsondecode(module.dhmc_role[0].policy_json).Statement[3].Resource == ["arn:aws:s3:::platform-prod-patch-logs"]
    error_message = "Patch output writes are limited to the prefix."
  }
}

run "features_off" {
  command = plan

  variables {
    account_settings = { enabled = false }
    session_manager  = { enabled = false }
    patching         = { enabled = false }
    inventory        = { enabled = false }
    agent_update     = { enabled = false }
  }

  assert {
    condition     = length(module.dhmc_role) + length(module.patch_administration_role) + length(module.patch_execution_role) + length(aws_ssmquicksetup_configuration_manager.patch_policy) + length(data.aws_ssm_patch_baselines.default) + length(module.automation_log_group) + length(module.session_log_group) + length(aws_ssm_service_setting.document_public_sharing) + length(aws_ssm_document.session_manager) + length(aws_ssm_patch_baseline.this) + length(aws_ssm_association.inventory) + length(aws_ssm_association.agent_update) == 0
    error_message = "Every feature must be switchable off."
  }

  assert {
    condition     = output.session_kms_iam_policy_json == null && output.patch_policy_manager_arn == null && output.patch_policy_administration_role_arn == null && output.resource_data_sync_name == null
    error_message = "Outputs of disabled features are null."
  }
}

run "account_settings_parts" {
  command = plan

  variables {
    account_settings = { block_public_document_sharing = false, automation_logging = { enabled = false } }
  }

  assert {
    condition     = length(aws_ssm_service_setting.document_public_sharing) == 0 && length(module.automation_log_group) == 0 && length(aws_ssm_service_setting.default_host_management) == 1
    error_message = "Each account setting has its own switch."
  }
}

run "quick_setup" {
  command = plan

  variables {
    inventory    = { enabled = false }
    agent_update = { enabled = false }
    quick_setup_host_management = {
      enabled                     = true
      target_organizational_units = ["ou-ab12-abcdefgh"]
    }
  }

  assert {
    condition     = aws_ssmquicksetup_configuration_manager.host_management[0].name == "platform-prod-host-management" && aws_ssmquicksetup_configuration_manager.host_management[0].configuration_definition[0].type == "AWSQuickSetupType-SSMHostMgmt"
    error_message = "Quick Setup host management is named and typed."
  }

  assert {
    condition     = aws_ssmquicksetup_configuration_manager.host_management[0].configuration_definition[0].parameters["TargetRegions"] == "eu-west-1" && aws_ssmquicksetup_configuration_manager.host_management[0].configuration_definition[0].parameters["TargetOrganizationalUnits"] == "ou-ab12-abcdefgh"
    error_message = "Quick Setup targets the OUs in the module Regions."
  }

  assert {
    condition     = aws_ssmquicksetup_configuration_manager.host_management[0].configuration_definition[0].parameters["ScanInstances"] == "false" && length(aws_ssmquicksetup_configuration_manager.patch_policy) == 1
    error_message = "Host management stops scanning while the patch policy runs."
  }
}

run "quick_setup_scans_without_patch_policy" {
  command = plan

  variables {
    inventory    = { enabled = false }
    agent_update = { enabled = false }
    patching     = { enabled = false }
    quick_setup_host_management = {
      enabled                     = true
      target_organizational_units = ["ou-ab12-abcdefgh"]
    }
  }

  assert {
    condition     = aws_ssmquicksetup_configuration_manager.host_management[0].configuration_definition[0].parameters["ScanInstances"] == "true"
    error_message = "Host management scans when no patch policy runs."
  }

  assert {
    condition     = local.dhmc_managed_policy_arns == ["arn:aws:iam::aws:policy/AmazonSSMManagedEC2InstanceDefaultPolicy"]
    error_message = "Without a patch policy the DHMC role keeps only the default policy."
  }
}

run "organization_admin" {
  command   = apply
  state_key = "organization"

  variables {
    account_settings   = { enabled = false }
    session_manager    = { enabled = false }
    patching           = { enabled = false }
    inventory          = { enabled = false }
    agent_update       = { enabled = false }
    organization_admin = { enabled = true, account_id = "222222222222" }
  }

  assert {
    condition     = aws_organizations_aws_service_access.ssm[0].service_principal == "ssm.amazonaws.com" && aws_organizations_delegated_administrator.ssm[0].account_id == "222222222222"
    error_message = "Trusted access and the delegated administrator are registered."
  }
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
    environment = "PROD"
  }

  expect_failures = [var.environment]
}

run "rejects_invalid_region" {
  command = plan

  variables {
    regions = ["Europe"]
  }

  expect_failures = [var.regions]
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
    kms = { key_id = "alias/ssm" }
  }

  expect_failures = [var.kms]
}

run "rejects_single_region_key_for_several_regions" {
  command = plan

  variables {
    regions = ["eu-west-1", "us-east-1"]
    kms     = { key_id = "11111111-2222-3333-4444-555555555555" }
  }

  expect_failures = [var.kms]
}

run "rejects_invalid_idle_timeout" {
  command = plan

  variables {
    session_manager = { idle_session_timeout = 90 }
  }

  expect_failures = [var.session_manager]
}

run "rejects_invalid_session_duration" {
  command = plan

  variables {
    session_manager = { max_session_duration = 2000 }
  }

  expect_failures = [var.session_manager]
}

run "rejects_run_as_without_user" {
  command = plan

  variables {
    session_manager = { run_as_enabled = true }
  }

  expect_failures = [var.session_manager]
}

run "rejects_s3_logs_without_bucket" {
  command = plan

  variables {
    session_manager = { s3_logs = { enabled = true } }
  }

  expect_failures = [var.session_manager]
}

run "rejects_invalid_patch_operation" {
  command = plan

  variables {
    patching = { operation = "Install" }
  }

  expect_failures = [var.patching]
}

run "rejects_rate_schedule" {
  command = plan

  variables {
    patching = { scan_schedule = "rate(1 day)" }
  }

  expect_failures = [var.patching]
}

run "rejects_invalid_reboot_option" {
  command = plan

  variables {
    patching = { reboot_option = "Always" }
  }

  expect_failures = [var.patching]
}

run "rejects_custom_baselines_with_defaults" {
  command = plan

  variables {
    patching = { baselines = { custom = { ubuntu = { operating_system = "UBUNTU" } } } }
  }

  expect_failures = [var.patching]
}

run "rejects_custom_mode_without_baselines" {
  command = plan

  variables {
    patching = { baselines = { use_default = false } }
  }

  expect_failures = [var.patching]
}

run "rejects_invalid_baseline_key" {
  command = plan

  variables {
    patching = { baselines = { use_default = false, custom = { "Amazon_Linux" = { operating_system = "AMAZON_LINUX_2023" } } } }
  }

  expect_failures = [var.patching]
}

run "rejects_two_baselines_for_one_os" {
  command = plan

  variables {
    patching = {
      baselines = {
        use_default = false
        custom = {
          one = { operating_system = "UBUNTU" }
          two = { operating_system = "UBUNTU" }
        }
      }
    }
  }

  expect_failures = [var.patching]
}

run "rejects_baseline_without_filters" {
  command = plan

  variables {
    patching = { baselines = { use_default = false, custom = { oracle = { operating_system = "ORACLE_LINUX" } } } }
  }

  expect_failures = [var.patching]
}

run "rejects_ubuntu_approval_delay" {
  command = plan

  variables {
    patching = { baselines = { use_default = false, custom = { ubuntu = { operating_system = "UBUNTU", approve_after_days = 7 } } } }
  }

  expect_failures = [var.patching]
}

run "rejects_invalid_target_type" {
  command = plan

  variables {
    patching = { target = { type = "Tag" } }
  }

  expect_failures = [var.patching]
}

run "rejects_tag_target_without_value" {
  command = plan

  variables {
    patching = { target = { type = "Tags", tag_key = "Patch" } }
  }

  expect_failures = [var.patching]
}

run "rejects_resource_group_for_ous" {
  command = plan

  variables {
    patching = {
      target                      = { type = "ResourceGroups", resource_group_name = "web-servers" }
      target_organizational_units = ["ou-ab12-abcdefgh"]
    }
  }

  expect_failures = [var.patching]
}

run "rejects_invalid_instance_ids" {
  command = plan

  variables {
    patching = { target = { type = "InstanceIds", instance_ids = ["mi-0123456789abcdef0"] } }
  }

  expect_failures = [var.patching]
}

run "rejects_invalid_patch_ou" {
  command = plan

  variables {
    patching = { target_organizational_units = ["prod"] }
  }

  expect_failures = [var.patching]
}

run "rejects_patch_logs_without_bucket" {
  command = plan

  variables {
    patching = { output_logs = { enabled = true } }
  }

  expect_failures = [var.patching]
}

run "rejects_sync_without_bucket" {
  command = plan

  variables {
    inventory = { resource_data_sync = { enabled = true } }
  }

  expect_failures = [var.inventory]
}

run "rejects_invalid_allowed_account" {
  command = plan

  variables {
    inventory_bucket = { enabled = true, allowed_account_ids = ["12345"] }
  }

  expect_failures = [var.inventory_bucket]
}

run "rejects_invalid_organization_id" {
  command = plan

  variables {
    inventory_bucket = { enabled = true, organization_id = "abc" }
  }

  expect_failures = [var.inventory_bucket]
}

run "rejects_access_logs_without_bucket" {
  command = plan

  variables {
    inventory_bucket = { enabled = true, access_logs = { enabled = true } }
  }

  expect_failures = [var.inventory_bucket]
}

run "rejects_quick_setup_without_targets" {
  command = plan

  variables {
    inventory                   = { enabled = false }
    agent_update                = { enabled = false }
    quick_setup_host_management = { enabled = true }
  }

  expect_failures = [var.quick_setup_host_management]
}

run "rejects_quick_setup_with_individual_features" {
  command = plan

  variables {
    quick_setup_host_management = { enabled = true, target_organizational_units = ["ou-ab12-abcdefgh"] }
  }

  expect_failures = [var.quick_setup_host_management]
}

run "rejects_invalid_admin_account" {
  command = plan

  variables {
    account_settings   = { enabled = false }
    session_manager    = { enabled = false }
    patching           = { enabled = false }
    inventory          = { enabled = false }
    agent_update       = { enabled = false }
    organization_admin = { enabled = true, account_id = "2222" }
  }

  expect_failures = [var.organization_admin]
}

run "rejects_admin_with_account_features" {
  command = plan

  variables {
    organization_admin = { enabled = true, account_id = "222222222222" }
  }

  expect_failures = [var.organization_admin]
}

run "rejects_admin_with_account_patch_policy" {
  command = plan

  variables {
    account_settings   = { enabled = false }
    session_manager    = { enabled = false }
    inventory          = { enabled = false }
    agent_update       = { enabled = false }
    organization_admin = { enabled = true, account_id = "222222222222" }
  }

  expect_failures = [var.organization_admin]
}
