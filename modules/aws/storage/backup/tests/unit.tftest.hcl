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
      arn = "arn:aws:iam::123456789012:role/platform-prod-backup-eu-west-1"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    }
  }

  mock_resource "aws_backup_vault" {
    defaults = {
      arn = "arn:aws:backup:eu-west-1:123456789012:backup-vault:platform-prod"
    }
  }

  mock_resource "aws_backup_plan" {
    defaults = {
      id  = "8a8b8c8d-1111-2222-3333-444455556666"
      arn = "arn:aws:backup:eu-west-1:123456789012:backup-plan:8a8b8c8d-1111-2222-3333-444455556666"
    }
  }

  mock_resource "aws_backup_framework" {
    defaults = {
      arn = "arn:aws:backup:eu-west-1:123456789012:framework:platform_prod_backup-1a2b3c4d"
    }
  }

  mock_resource "aws_backup_report_plan" {
    defaults = {
      arn = "arn:aws:backup:eu-west-1:123456789012:report-plan:platform_prod_backup_report-1a2b3c4d"
    }
  }
}

variables {
  environment           = "prod"
  tags                  = { Team = "storage" }
  vault_admin_role_arns = ["arn:aws:iam::123456789012:role/terraform"]
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = keys(aws_backup_vault.this) == ["eu-west-1"] && aws_backup_vault.this["eu-west-1"].name == "platform-prod" && aws_backup_vault.this["eu-west-1"].region == "eu-west-1"
    error_message = "One vault <application>-<environment> in the provider Region."
  }

  assert {
    condition     = output.kms_key_arns["eu-west-1"] == null && aws_backup_vault.this["eu-west-1"].force_destroy == false
    error_message = "No kms input means the aws/backup key; deletion protection keeps recovery points."
  }

  assert {
    condition     = aws_backup_vault.this["eu-west-1"].tags["Name"] == "platform-prod" && aws_backup_vault.this["eu-west-1"].tags["Team"] == "storage" && aws_backup_vault.this["eu-west-1"].tags["Application"] == "platform" && aws_backup_vault.this["eu-west-1"].tags["ManagedBy"] == "Terraform"
    error_message = "Caller and governance tags must be applied."
  }

  assert {
    condition     = toset([for r in aws_backup_plan.this["eu-west-1"].rule : r.rule_name]) == toset(["daily", "monthly"]) && alltrue([for r in aws_backup_plan.this["eu-west-1"].rule : r.target_vault_name == "platform-prod" && r.recovery_point_tags["Environment"] == "prod"])
    error_message = "Default daily and monthly rules into the vault, recovery points tagged."
  }

  assert {
    condition     = { for r in aws_backup_plan.this["eu-west-1"].rule : r.rule_name => r.lifecycle[0].delete_after } == { daily = 35, monthly = 365 }
    error_message = "Daily kept 35 days, monthly 365."
  }

  assert {
    condition     = aws_backup_selection.this["eu-west-1"].resources == toset(["arn:aws:dynamodb:*:*:table/*", "arn:aws:ec2:*:*:volume/*", "arn:aws:elasticfilesystem:*:*:file-system/*", "arn:aws:rds:*:*:db:*"])
    error_message = "Default selection: DynamoDB, EBS, EFS and RDS; no EC2 instances."
  }

  assert {
    condition     = toset([for c in aws_backup_framework.this["eu-west-1"].control : c.name]) == toset(["BACKUP_RECOVERY_POINT_ENCRYPTED", "BACKUP_PLAN_MIN_FREQUENCY_AND_MIN_RETENTION_CHECK", "BACKUP_RECOVERY_POINT_MINIMUM_RETENTION_CHECK", "BACKUP_RESOURCES_PROTECTED_BY_BACKUP_PLAN", "BACKUP_RECOVERY_POINT_MANUAL_DELETION_DISABLED", "BACKUP_LAST_RECOVERY_POINT_CREATED"])
    error_message = "Six audit controls; no vault lock control without a lock."
  }

  assert {
    condition     = aws_backup_framework.this["eu-west-1"].name == "platform_prod_backup"
    error_message = "Framework name uses underscores."
  }

  assert {
    condition     = length(aws_backup_vault_lock_configuration.this) + length(aws_backup_vault_notifications.this) + length(aws_backup_report_plan.this) + length(aws_backup_region_settings.this) == 0
    error_message = "Lock, notifications, report plan and Region settings are off by default."
  }

  assert {
    condition     = length(aws_organizations_aws_service_access.this) + length(aws_organizations_delegated_administrator.this) + length(aws_backup_global_settings.this) == 0
    error_message = "No organization resources by default."
  }

  assert {
    condition     = output.report_bucket_policy_json == null && output.vault_name == "platform-prod"
    error_message = "No report bucket policy without a report plan."
  }
}

run "backup_role" {
  command = plan

  assert {
    condition     = module.role[0].name == "platform-prod-backup-eu-west-1"
    error_message = "The role must be <application>-<environment>-backup-<region>."
  }

  assert {
    condition     = jsondecode(module.role[0].trust_policy_json).Statement[0].Principal.Service == ["backup.amazonaws.com"] && jsondecode(module.role[0].trust_policy_json).Statement[0].Condition.StringEquals["aws:SourceAccount"] == ["123456789012"]
    error_message = "Only AWS Backup in this account may assume the role."
  }

  assert {
    condition     = module.role[0].policy_json == null
    error_message = "The role carries only the AWS managed backup policies by default."
  }
}

run "vault_policy_denies_deletion" {
  command = plan

  variables {
    copy_into_vault = { account_ids = ["210987654321"], organization_id = "o-a1b2c3d4e5" }
  }

  assert {
    condition     = jsondecode(aws_backup_vault_policy.this["eu-west-1"].policy).Statement[0].Effect == "Deny" && jsondecode(aws_backup_vault_policy.this["eu-west-1"].policy).Statement[0].Principal == "*" && jsondecode(aws_backup_vault_policy.this["eu-west-1"].policy).Statement[0].Condition.ArnNotEquals["aws:PrincipalArn"] == ["arn:aws:iam::123456789012:role/terraform"]
    error_message = "Everyone but the vault admins is denied."
  }

  assert {
    condition     = toset(jsondecode(aws_backup_vault_policy.this["eu-west-1"].policy).Statement[0].Action) == toset(["backup:DeleteBackupVaultAccessPolicy", "backup:DeleteRecoveryPoint", "backup:PutBackupVaultAccessPolicy", "backup:UpdateRecoveryPointLifecycle"])
    error_message = "The deny covers recovery point deletion, lifecycle and the policy itself."
  }

  assert {
    condition     = [for s in jsondecode(aws_backup_vault_policy.this["eu-west-1"].policy).Statement : s.Sid] == ["DenyRecoveryPointDeletion", "AllowCopyIntoVaultFromAccounts", "AllowCopyIntoVaultFromOrganization"]
    error_message = "copy_into_vault adds copy-in grants."
  }

  assert {
    condition     = jsondecode(aws_backup_vault_policy.this["eu-west-1"].policy).Statement[1].Principal.AWS == ["arn:aws:iam::210987654321:root"] && jsondecode(aws_backup_vault_policy.this["eu-west-1"].policy).Statement[2].Condition.StringEquals["aws:PrincipalOrgID"] == "o-a1b2c3d4e5" && jsondecode(aws_backup_vault_policy.this["eu-west-1"].policy).Statement[2].Action == ["backup:CopyIntoBackupVault"]
    error_message = "Copy-in grants only backup:CopyIntoBackupVault."
  }
}

run "module_key_is_planned_safely" {
  command = plan

  variables {
    kms = { create = true }
  }

  assert {
    condition     = module.encryption["eu-west-1"].created
    error_message = "kms.create must plan without knowing the key ARN."
  }
}

run "module_key_encrypts_vault" {
  command = apply

  variables {
    kms = { create = true }
  }

  assert {
    condition     = aws_backup_vault.this["eu-west-1"].kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && output.kms_key_arns["eu-west-1"] == aws_backup_vault.this["eu-west-1"].kms_key_arn
    error_message = "The module key must encrypt the vault."
  }

  assert {
    condition     = output.vault_arns["eu-west-1"] == "arn:aws:backup:eu-west-1:123456789012:backup-vault:platform-prod" && output.plan_ids["eu-west-1"] == "8a8b8c8d-1111-2222-3333-444455556666" && output.role_arn == "arn:aws:iam::123456789012:role/platform-prod-backup-eu-west-1"
    error_message = "Vault, plan and role outputs."
  }

  assert {
    condition     = aws_backup_selection.this["eu-west-1"].iam_role_arn == output.role_arn && aws_backup_selection.this["eu-west-1"].plan_id == output.plan_ids["eu-west-1"]
    error_message = "The selection uses the module role and plan."
  }
}

run "caller_key_id" {
  command = plan

  variables {
    kms = { key_id = "11111111-2222-3333-4444-555555555555" }
  }

  assert {
    condition     = aws_backup_vault.this["eu-west-1"].kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    error_message = "A key ID must be used as the key ARN in the vault Region."
  }

  assert {
    condition     = [for s in jsondecode(output.kms_key_policy_json).Statement : s.Sid] == ["AllowBackupUseOfKey", "AllowBackupCreateGrant", "DenyBackupStorageConfusedDeputy"]
    error_message = "kms_key_policy_json lists what a caller key must grant."
  }

  assert {
    condition     = jsondecode(output.kms_key_policy_json).Statement[0].Condition.StringEquals["kms:ViaService"] == ["backup.eu-west-1.amazonaws.com"] && jsondecode(output.kms_key_policy_json).Statement[2].Principal.Service == ["backup-storage.amazonaws.com"] && jsondecode(output.kms_key_policy_json).Statement[2].Effect == "Deny"
    error_message = "Key use only through AWS Backup; backup-storage limited to this account's vaults."
  }
}

run "several_regions" {
  command = plan

  variables {
    regions = ["eu-west-1", "us-east-1"]
    kms     = { key_id = "mrk-1234567890abcdef1234567890abcdef" }
  }

  assert {
    condition     = toset(keys(aws_backup_vault.this)) == toset(["eu-west-1", "us-east-1"]) && aws_backup_vault.this["us-east-1"].region == "us-east-1"
    error_message = "One vault per Region."
  }

  assert {
    condition     = aws_backup_vault.this["us-east-1"].kms_key_arn == "arn:aws:kms:us-east-1:123456789012:key/mrk-1234567890abcdef1234567890abcdef" && aws_backup_vault.this["eu-west-1"].kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/mrk-1234567890abcdef1234567890abcdef"
    error_message = "A multi-Region key ID resolves in each Region."
  }

  assert {
    condition     = length(aws_backup_plan.this) == 2 && length(aws_backup_selection.this) == 2 && length(aws_backup_framework.this) == 2 && length(module.role) == 1
    error_message = "Plan, selection and framework per Region; one global role."
  }

  assert {
    condition     = toset(jsondecode(output.kms_key_policy_json).Statement[0].Condition.StringEquals["kms:ViaService"]) == toset(["backup.eu-west-1.amazonaws.com", "backup.us-east-1.amazonaws.com"])
    error_message = "kms_key_policy_json covers every Region."
  }
}

run "several_regions_module_keys" {
  command = plan

  variables {
    regions = ["eu-west-1", "us-east-1"]
    kms     = { create = true }
  }

  assert {
    condition     = toset(keys(module.encryption)) == toset(["eu-west-1", "us-east-1"]) && module.encryption["us-east-1"].created
    error_message = "One module key per Region."
  }
}

run "vault_lock_governance" {
  command = plan

  variables {
    vault_lock = { enabled = true, max_retention_days = 3650 }
  }

  assert {
    condition     = aws_backup_vault_lock_configuration.this["eu-west-1"].min_retention_days == 7 && aws_backup_vault_lock_configuration.this["eu-west-1"].max_retention_days == 3650 && aws_backup_vault_lock_configuration.this["eu-west-1"].changeable_for_days == null
    error_message = "GOVERNANCE lock without a grace time."
  }

  assert {
    condition     = contains([for c in aws_backup_framework.this["eu-west-1"].control : c.name], "BACKUP_RESOURCES_PROTECTED_BY_BACKUP_VAULT_LOCK")
    error_message = "The vault lock control comes with the lock."
  }
}

run "vault_lock_compliance" {
  command = plan

  variables {
    vault_lock = { enabled = true, mode = "COMPLIANCE", changeable_for_days = 14 }
  }

  assert {
    condition     = aws_backup_vault_lock_configuration.this["eu-west-1"].changeable_for_days == 14
    error_message = "COMPLIANCE sets the grace time."
  }
}

run "plan_off_keeps_vault_and_role" {
  command = plan

  variables {
    plan = { enabled = false }
  }

  assert {
    condition     = length(aws_backup_plan.this) == 0 && length(aws_backup_selection.this) == 0 && length(aws_backup_vault.this) == 1 && length(module.role) == 1 && length(aws_backup_framework.this) == 1
    error_message = "plan.enabled = false drops only the plan and selection."
  }
}

run "selection_options" {
  command = plan

  variables {
    resource_types       = ["ebs", "ec2", "s3"]
    additional_resources = ["arn:aws:rds:*:*:cluster:*"]
    not_resources        = ["arn:aws:ec2:*:*:volume/vol-0a1b2c3d4e5f67890"]
    selection_tags = [
      { key = "Backup", value = "true" },
      { operator = "string_not_like", key = "Tier", value = "scratch*" },
    ]
  }

  assert {
    condition     = aws_backup_selection.this["eu-west-1"].resources == toset(["arn:aws:ec2:*:*:volume/*", "arn:aws:ec2:*:*:instance/*", "arn:aws:s3:::*", "arn:aws:rds:*:*:cluster:*"])
    error_message = "Selected types plus additional resources."
  }

  assert {
    condition     = aws_backup_selection.this["eu-west-1"].not_resources == toset(["arn:aws:ec2:*:*:volume/vol-0a1b2c3d4e5f67890"])
    error_message = "not_resources excludes."
  }

  assert {
    condition     = one(aws_backup_selection.this["eu-west-1"].condition).string_equals == toset([{ key = "aws:ResourceTag/Backup", value = "true" }]) && one(aws_backup_selection.this["eu-west-1"].condition).string_not_like == toset([{ key = "aws:ResourceTag/Tier", value = "scratch*" }])
    error_message = "Tag conditions are prefixed with aws:ResourceTag/."
  }
}

run "rules_with_copies" {
  command = plan

  variables {
    rules = {
      continuous = { schedule = "cron(0 * ? * * *)", delete_after = 14, enable_continuous_backup = true }
      monthly = {
        schedule           = "cron(0 5 1 * ? *)"
        delete_after       = 400
        cold_storage_after = 30
        copy_to            = [{ destination_vault_arn = "arn:aws:backup:us-west-2:123456789012:backup-vault:platform-prod" }]
      }
    }
  }

  assert {
    condition     = one([for r in aws_backup_plan.this["eu-west-1"].rule : r if r.rule_name == "continuous"]).enable_continuous_backup
    error_message = "Continuous backup on its rule."
  }

  assert {
    condition     = one(one([for r in aws_backup_plan.this["eu-west-1"].rule : r if r.rule_name == "monthly"]).copy_action).destination_vault_arn == "arn:aws:backup:us-west-2:123456789012:backup-vault:platform-prod" && one(one([for r in aws_backup_plan.this["eu-west-1"].rule : r if r.rule_name == "monthly"]).copy_action).lifecycle[0].delete_after == 400
    error_message = "Copies inherit the rule retention."
  }
}

run "reports_notifications_region_settings" {
  command = apply

  variables {
    regions             = ["eu-west-1", "us-east-1"]
    report_plan         = { enabled = true, s3_bucket_name = "platform-prod-reports", s3_key_prefix = "/audit/" }
    vault_notifications = { enabled = true, sns_topic_arns = { "eu-west-1" = "arn:aws:sns:eu-west-1:123456789012:platform-prod-alarms" } }
    region_settings     = { enabled = true, resource_type_opt_in_preference = { DynamoDB = true, EBS = true, EFS = true, RDS = true } }
  }

  assert {
    condition     = length(aws_backup_report_plan.this) == 2 && aws_backup_report_plan.this["us-east-1"].report_delivery_channel[0].s3_key_prefix == "audit" && aws_backup_report_plan.this["eu-west-1"].report_setting[0].framework_arns == toset([aws_backup_framework.this["eu-west-1"].arn])
    error_message = "One report plan per Region on that Region's framework."
  }

  assert {
    condition     = jsondecode(output.report_bucket_policy_json).Statement[0].Resource == "arn:aws:s3:::platform-prod-reports/audit/Backup/*"
    error_message = "The report bucket statement covers <prefix>/Backup/."
  }

  assert {
    condition     = keys(aws_backup_vault_notifications.this) == ["eu-west-1"] && contains(aws_backup_vault_notifications.this["eu-west-1"].backup_vault_events, "BACKUP_JOB_FAILED")
    error_message = "Notifications only where a Region has a topic."
  }

  assert {
    condition     = length(aws_backup_region_settings.this) == 2 && aws_backup_region_settings.this["us-east-1"].resource_type_opt_in_preference["EFS"]
    error_message = "Region settings in every Region."
  }

  assert {
    condition     = toset(keys(output.report_plan_arns)) == toset(["eu-west-1", "us-east-1"]) && toset(keys(output.framework_arns)) == toset(["eu-west-1", "us-east-1"])
    error_message = "Report plan and framework outputs by Region."
  }
}

run "organization_admin_call" {
  command   = plan
  state_key = "management"

  variables {
    vault_admin_role_arns = []
    vault                 = { enabled = false }
    organization_admin    = { enabled = true, account_id = "210987654321", global_settings = { enabled = true } }
  }

  assert {
    condition     = aws_organizations_aws_service_access.this[0].service_principal == "backup.amazonaws.com" && aws_organizations_delegated_administrator.this[0].account_id == "210987654321"
    error_message = "Trusted access and the delegated administrator."
  }

  assert {
    condition     = aws_backup_global_settings.this[0].global_settings == tomap({ isCrossAccountBackupEnabled = "true", isDelegatedAdministratorEnabled = "true", isMpaEnabled = "false" })
    error_message = "All three global settings are written."
  }

  assert {
    condition     = length(aws_backup_vault.this) + length(aws_backup_plan.this) + length(aws_backup_framework.this) + length(module.role) + length(module.encryption) == 0
    error_message = "The management call creates no vault, plan, role or key."
  }

  assert {
    condition     = output.role_arn == null && output.vault_name == null && output.kms_key_policy_json == null && length(output.kms_key_arns) == 0
    error_message = "Vault outputs are empty in the management call."
  }
}

run "organization_admin_without_trusted_access" {
  command   = plan
  state_key = "management"

  variables {
    vault_admin_role_arns = []
    vault                 = { enabled = false }
    organization_admin    = { enabled = true, account_id = "210987654321", manage_trusted_access = false }
  }

  assert {
    condition     = length(aws_organizations_aws_service_access.this) == 0 && length(aws_organizations_delegated_administrator.this) == 1 && length(aws_backup_global_settings.this) == 0
    error_message = "manage_trusted_access = false and no global settings."
  }
}

run "rejects_management_account_as_admin" {
  command   = plan
  state_key = "management"

  variables {
    vault_admin_role_arns = []
    vault                 = { enabled = false }
    organization_admin    = { enabled = true, account_id = "123456789012" }
  }

  expect_failures = [aws_organizations_delegated_administrator.this]
}

run "caller_role_and_exact_names" {
  command = plan

  variables {
    iam_role            = { create = false, arn = "arn:aws:iam::123456789012:role/backup" }
    vault               = { name = "central_vault" }
    deletion_protection = false
  }

  assert {
    condition     = length(module.role) == 0 && aws_backup_selection.this["eu-west-1"].iam_role_arn == "arn:aws:iam::123456789012:role/backup" && output.role_name == null
    error_message = "A caller role replaces the module role."
  }

  assert {
    condition     = aws_backup_vault.this["eu-west-1"].name == "central_vault" && aws_backup_vault.this["eu-west-1"].force_destroy
    error_message = "vault.name is exact; deletion_protection = false allows force_destroy."
  }

  assert {
    condition     = one([for c in aws_backup_framework.this["eu-west-1"].control : c if c.name == "BACKUP_RECOVERY_POINT_MANUAL_DELETION_DISABLED"]).scope[0].compliance_resource_ids == toset(["central_vault"])
    error_message = "The manual deletion control targets this vault."
  }
}

run "governance_tags_win" {
  command = plan

  variables {
    application = "data"
    tags        = { Environment = "spoofed", Owner = "storage" }
  }

  assert {
    condition     = aws_backup_vault.this["eu-west-1"].tags["Environment"] == "prod" && aws_backup_vault.this["eu-west-1"].tags["Owner"] == "storage" && aws_backup_vault.this["eu-west-1"].name == "data-prod"
    error_message = "Governance tags win over caller tags."
  }
}

run "rejects_invalid_application" {
  command = plan

  variables {
    application = "Data"
  }

  expect_failures = [var.application]
}

run "rejects_invalid_environment" {
  command = plan

  variables {
    environment = "Production"
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

run "rejects_invalid_vault_name" {
  command = plan

  variables {
    vault = { name = "a" }
  }

  expect_failures = [var.vault]
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
    kms = { key_id = "alias/backup" }
  }

  expect_failures = [var.kms]
}

run "rejects_single_region_key_for_several_regions" {
  command = plan

  variables {
    regions = ["eu-west-1", "us-east-1"]
    kms     = { key_id = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" }
  }

  expect_failures = [var.kms]
}

run "rejects_invalid_admin_arn" {
  command = plan

  variables {
    vault_admin_role_arns = ["terraform"]
  }

  expect_failures = [var.vault_admin_role_arns]
}

run "rejects_missing_admin_arn" {
  command = plan

  variables {
    vault_admin_role_arns = []
  }

  expect_failures = [var.vault_admin_role_arns]
}

run "rejects_too_many_admin_arns" {
  command = plan

  variables {
    vault_admin_role_arns = [for i in range(6) : "arn:aws:iam::123456789012:role/admin-${i}"]
  }

  expect_failures = [var.vault_admin_role_arns]
}

run "rejects_invalid_copy_into_vault" {
  command = plan

  variables {
    copy_into_vault = { organization_id = "org-1" }
  }

  expect_failures = [var.copy_into_vault]
}

run "rejects_invalid_lock_mode" {
  command = plan

  variables {
    vault_lock = { mode = "STRICT" }
  }

  expect_failures = [var.vault_lock]
}

run "rejects_invalid_lock_range" {
  command = plan

  variables {
    vault_lock = { min_retention_days = 30, max_retention_days = 10 }
  }

  expect_failures = [var.vault_lock]
}

run "rejects_rule_outside_lock_range" {
  command = plan

  variables {
    vault_lock = { enabled = true, min_retention_days = 60 }
  }

  expect_failures = [var.vault_lock]
}

run "rejects_notifications_without_topic" {
  command = plan

  variables {
    vault_notifications = { enabled = true }
  }

  expect_failures = [var.vault_notifications]
}

run "rejects_invalid_rule_name" {
  command = plan

  variables {
    rules = { "daily backup" = { schedule = "cron(0 5 ? * * *)", delete_after = 35 } }
  }

  expect_failures = [var.rules]
}

run "rejects_short_windows" {
  command = plan

  variables {
    rules = { daily = { schedule = "cron(0 5 ? * * *)", delete_after = 35, start_window = 30 } }
  }

  expect_failures = [var.rules]
}

run "rejects_short_cold_storage" {
  command = plan

  variables {
    rules = { monthly = { schedule = "cron(0 5 1 * ? *)", delete_after = 100, cold_storage_after = 30 } }
  }

  expect_failures = [var.rules]
}

run "rejects_long_continuous_backup" {
  command = plan

  variables {
    rules = { continuous = { schedule = "cron(0 * ? * * *)", delete_after = 60, enable_continuous_backup = true } }
  }

  expect_failures = [var.rules]
}

run "rejects_invalid_copy_destination" {
  command = plan

  variables {
    rules = { daily = { schedule = "cron(0 5 ? * * *)", delete_after = 35, copy_to = [{ destination_vault_arn = "platform-prod" }] } }
  }

  expect_failures = [var.rules]
}

run "rejects_invalid_resource_type" {
  command = plan

  variables {
    resource_types = ["redshift"]
  }

  expect_failures = [var.resource_types]
}

run "rejects_empty_selection" {
  command = plan

  variables {
    resource_types = []
  }

  expect_failures = [var.resource_types]
}

run "rejects_invalid_selection_tag_operator" {
  command = plan

  variables {
    selection_tags = [{ operator = "equals", key = "Backup", value = "true" }]
  }

  expect_failures = [var.selection_tags]
}

run "rejects_caller_role_without_arn" {
  command = plan

  variables {
    iam_role = { create = false }
  }

  expect_failures = [var.iam_role]
}

run "rejects_region_settings_without_types" {
  command = plan

  variables {
    region_settings = { enabled = true }
  }

  expect_failures = [var.region_settings]
}

run "rejects_unknown_disabled_control" {
  command = plan

  variables {
    audit_framework = { disabled_controls = ["BACKUP_EVERYTHING"] }
  }

  expect_failures = [var.audit_framework]
}

run "rejects_report_plan_without_bucket" {
  command = plan

  variables {
    report_plan = { enabled = true }
  }

  expect_failures = [var.report_plan]
}

run "rejects_compliance_report_without_framework" {
  command = plan

  variables {
    audit_framework = { enabled = false }
    report_plan     = { enabled = true, s3_bucket_name = "platform-prod-reports" }
  }

  expect_failures = [var.report_plan]
}

run "rejects_invalid_admin_account_id" {
  command = plan

  variables {
    vault_admin_role_arns = []
    vault                 = { enabled = false }
    organization_admin    = { enabled = true, account_id = "12345" }
  }

  expect_failures = [var.organization_admin]
}

run "rejects_admin_call_with_vault" {
  command = plan

  variables {
    organization_admin = { enabled = true, account_id = "210987654321" }
  }

  expect_failures = [var.organization_admin]
}
