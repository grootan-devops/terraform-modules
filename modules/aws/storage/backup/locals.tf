locals {
  regions     = length(var.regions) > 0 ? distinct(var.regions) : [module.naming.region]
  vault_regs  = var.vault.enabled ? toset(local.regions) : toset([])
  plan_regs   = var.vault.enabled && var.plan.enabled ? toset(local.regions) : toset([])
  arn_prefix  = "arn:${module.naming.partition}"
  account_id  = module.naming.account_id
  root_arn    = "${local.arn_prefix}:iam::${local.account_id}:root"
  vault_name  = coalesce(var.vault.name, module.naming.names.vault)
  plan_name   = module.naming.names.vault
  create_role = var.vault.enabled && var.iam_role.create
  role_arn    = var.vault.enabled ? (var.iam_role.create ? module.role[0].arn : var.iam_role.arn) : null

  kms_key_arns = { for region in local.vault_regs : region => module.encryption[region].key_arn }

  framework_name   = "${replace(module.naming.name, "-", "_")}_backup"
  report_plan_name = "${local.framework_name}_report"

  resource_type_arns = {
    dynamodb = "${local.arn_prefix}:dynamodb:*:*:table/*"
    ebs      = "${local.arn_prefix}:ec2:*:*:volume/*"
    ec2      = "${local.arn_prefix}:ec2:*:*:instance/*"
    efs      = "${local.arn_prefix}:elasticfilesystem:*:*:file-system/*"
    rds      = "${local.arn_prefix}:rds:*:*:db:*"
    s3       = "${local.arn_prefix}:s3:::*"
  }

  resource_type_names = {
    dynamodb = "DynamoDB"
    ebs      = "EBS"
    ec2      = "EC2"
    efs      = "EFS"
    rds      = "RDS"
    s3       = "S3"
  }

  resource_types      = sort(distinct(var.resource_types))
  s3_selected         = contains(local.resource_types, "s3")
  selection_resources = distinct(concat([for t in local.resource_types : local.resource_type_arns[t]], var.additional_resources))
  compliance_types    = [for t in local.resource_types : local.resource_type_names[t]]

  selection_conditions = {
    for operator in ["string_equals", "string_like", "string_not_equals", "string_not_like"] : operator => [
      for tag in var.selection_tags : { key = "aws:ResourceTag/${tag.key}", value = tag.value } if tag.operator == operator
    ]
  }

  managed_policy_arns = concat(
    [
      "${local.arn_prefix}:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup",
      "${local.arn_prefix}:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores",
    ],
    local.s3_selected ? [
      "${local.arn_prefix}:iam::aws:policy/AWSBackupServiceRolePolicyForS3Backup",
      "${local.arn_prefix}:iam::aws:policy/AWSBackupServiceRolePolicyForS3Restore",
    ] : [],
    var.iam_role.managed_policy_arns
  )

  vault_statement_candidates = [
    {
      when = true
      statement = {
        Sid       = "DenyRecoveryPointDeletion"
        Effect    = "Deny"
        Principal = "*"
        Action    = ["backup:DeleteBackupVaultAccessPolicy", "backup:DeleteRecoveryPoint", "backup:PutBackupVaultAccessPolicy", "backup:UpdateRecoveryPointLifecycle"]
        Resource  = "*"
        Condition = { ArnNotEquals = { "aws:PrincipalArn" = var.vault_admin_role_arns } }
      }
    },
    {
      when = length(var.copy_into_vault.account_ids) > 0
      statement = {
        Sid       = "AllowCopyIntoVaultFromAccounts"
        Effect    = "Allow"
        Principal = { AWS = [for id in var.copy_into_vault.account_ids : "${local.arn_prefix}:iam::${id}:root"] }
        Action    = ["backup:CopyIntoBackupVault"]
        Resource  = "*"
      }
    },
    {
      when = var.copy_into_vault.organization_id != null
      statement = {
        Sid       = "AllowCopyIntoVaultFromOrganization"
        Effect    = "Allow"
        Principal = "*"
        Action    = ["backup:CopyIntoBackupVault"]
        Resource  = "*"
        Condition = { StringEquals = { "aws:PrincipalOrgID" = var.copy_into_vault.organization_id } }
      }
    },
  ]

  vault_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [for c in local.vault_statement_candidates : c.statement if c.when]
  })

  kms_statement_sets = {
    for scope, regions in merge({ for r in local.regions : r => [r] }, { all = local.regions }) : scope => [
      {
        sid        = "AllowBackupUseOfKey"
        actions    = ["kms:Decrypt", "kms:DescribeKey", "kms:GenerateDataKey"]
        principals = { AWS = [local.root_arn] }
        conditions = [
          { test = "StringEquals", variable = "kms:ViaService", values = tolist([for r in regions : "backup.${r}.${module.naming.dns_suffix}"]) },
          { test = "StringEquals", variable = "kms:CallerAccount", values = [local.account_id] },
        ]
      },
      {
        sid        = "AllowBackupCreateGrant"
        actions    = ["kms:CreateGrant"]
        principals = { AWS = [local.root_arn] }
        conditions = [
          { test = "Bool", variable = "kms:GrantIsForAWSResource", values = ["true"] },
          { test = "StringEquals", variable = "kms:ViaService", values = tolist([for r in regions : "backup.${r}.${module.naming.dns_suffix}"]) },
          { test = "StringEquals", variable = "kms:CallerAccount", values = [local.account_id] },
          { test = "ForAnyValue:StringEquals", variable = "kms:EncryptionContextKeys", values = ["aws:backup:backup-vault"] },
        ]
      },
      {
        sid        = "DenyBackupStorageConfusedDeputy"
        effect     = "Deny"
        actions    = ["kms:Decrypt", "kms:GenerateDataKey", "kms:RetireGrant"]
        principals = { Service = ["backup-storage.${module.naming.dns_suffix}"] }
        conditions = [
          { test = "StringNotEquals", variable = "aws:SourceAccount", values = [local.account_id] },
          { test = "ArnNotLike", variable = "aws:SourceArn", values = tolist([for r in regions : "${local.arn_prefix}:backup:${r}:${local.account_id}:backup-vault:*"]) },
        ]
      },
    ]
  }

  report_key_prefix = var.report_plan.s3_key_prefix == null ? "" : trim(var.report_plan.s3_key_prefix, "/")
  compliance_report = contains(["RESOURCE_COMPLIANCE_REPORT", "CONTROL_COMPLIANCE_REPORT"], var.report_plan.report_template)

  report_bucket_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowBackupReportDelivery"
      Effect    = "Allow"
      Principal = { AWS = "${local.arn_prefix}:iam::${local.account_id}:role/aws-service-role/reports.backup.amazonaws.com/AWSServiceRoleForBackupReports" }
      Action    = "s3:PutObject"
      Resource  = "${local.arn_prefix}:s3:::${coalesce(var.report_plan.s3_bucket_name, "unset")}/${local.report_key_prefix == "" ? "" : "${local.report_key_prefix}/"}Backup/*"
      Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" } }
    }]
  })

  framework_control_candidates = {
    BACKUP_RECOVERY_POINT_ENCRYPTED = {
      when           = true
      parameters     = {}
      resource_ids   = null
      resource_types = null
    }
    BACKUP_PLAN_MIN_FREQUENCY_AND_MIN_RETENTION_CHECK = {
      when = true
      parameters = {
        requiredFrequencyUnit  = var.audit_framework.required_frequency_unit
        requiredFrequencyValue = tostring(var.audit_framework.required_frequency_value)
        requiredRetentionDays  = tostring(var.audit_framework.required_retention_days)
      }
      resource_ids   = null
      resource_types = null
    }
    BACKUP_RECOVERY_POINT_MINIMUM_RETENTION_CHECK = {
      when           = true
      parameters     = { requiredRetentionDays = tostring(var.audit_framework.required_retention_days) }
      resource_ids   = null
      resource_types = null
    }
    BACKUP_RESOURCES_PROTECTED_BY_BACKUP_PLAN = {
      when           = true
      parameters     = {}
      resource_ids   = null
      resource_types = local.compliance_types
    }
    BACKUP_RECOVERY_POINT_MANUAL_DELETION_DISABLED = {
      when           = true
      parameters     = { principalArnList = join(",", var.vault_admin_role_arns) }
      resource_ids   = [local.vault_name]
      resource_types = ["AWS::Backup::BackupVault"]
    }
    BACKUP_LAST_RECOVERY_POINT_CREATED = {
      when = true
      parameters = {
        recoveryPointAgeUnit  = var.audit_framework.recovery_point_age_unit
        recoveryPointAgeValue = tostring(var.audit_framework.recovery_point_age_value)
      }
      resource_ids   = null
      resource_types = local.compliance_types
    }
    BACKUP_RESOURCES_PROTECTED_BY_BACKUP_VAULT_LOCK = {
      when = var.vault_lock.enabled
      parameters = merge(
        { minRetentionDays = tostring(var.vault_lock.min_retention_days) },
        var.vault_lock.max_retention_days == null ? {} : { maxRetentionDays = tostring(var.vault_lock.max_retention_days) }
      )
      resource_ids   = null
      resource_types = local.compliance_types
    }
  }

  framework_controls = {
    for name, control in local.framework_control_candidates : name => control
    if control.when && !contains(var.audit_framework.disabled_controls, name)
  }

  global_settings = {
    isCrossAccountBackupEnabled     = tostring(var.organization_admin.global_settings.cross_account_backup)
    isDelegatedAdministratorEnabled = tostring(var.organization_admin.global_settings.delegated_administrator)
    isMpaEnabled                    = tostring(var.organization_admin.global_settings.multi_party_approval)
  }
}
