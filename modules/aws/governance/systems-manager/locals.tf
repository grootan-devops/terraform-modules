locals {
  partition       = module.naming.partition
  dns_suffix      = module.naming.dns_suffix
  account_id      = module.naming.account_id
  provider_region = module.naming.region
  base_name       = module.naming.name

  regions     = length(var.regions) > 0 ? distinct(var.regions) : [local.provider_region]
  kms_enabled = var.kms.create || var.kms.key_id != null

  public_sharing_enabled     = var.account_settings.enabled && var.account_settings.block_public_document_sharing
  automation_logging_enabled = var.account_settings.enabled && var.account_settings.automation_logging.enabled
  dhmc_enabled               = var.account_settings.enabled && var.account_settings.default_host_management.enabled
  session_enabled            = var.session_manager.enabled
  s3_logs_enabled            = var.session_manager.enabled && var.session_manager.s3_logs.enabled
  patching_enabled           = var.patching.enabled
  custom_baselines_enabled   = var.patching.enabled && !var.patching.baselines.use_default
  patch_logs_enabled         = var.patching.enabled && var.patching.output_logs.enabled
  inventory_enabled          = var.inventory.enabled
  sync_enabled               = var.inventory.enabled && var.inventory.resource_data_sync.enabled
  bucket_enabled             = var.inventory_bucket.enabled
  agent_update_enabled       = var.agent_update.enabled
  quick_setup_enabled        = var.quick_setup_host_management.enabled
  organization_admin_enabled = var.organization_admin.enabled

  key_regions = toset(concat(local.regions, local.bucket_enabled ? [local.provider_region] : []))

  public_sharing_regions     = local.public_sharing_enabled ? toset(local.regions) : toset([])
  automation_logging_regions = local.automation_logging_enabled ? toset(local.regions) : toset([])
  dhmc_regions               = local.dhmc_enabled ? toset(local.regions) : toset([])
  session_regions            = local.session_enabled ? toset(local.regions) : toset([])
  inventory_regions          = local.inventory_enabled ? toset(local.regions) : toset([])
  sync_regions               = local.sync_enabled ? toset(local.regions) : toset([])
  agent_update_regions       = local.agent_update_enabled ? toset(local.regions) : toset([])

  kms_key_arns = { for region, encryption in module.encryption : region => encryption.key_arn }

  setting_ids = {
    document_public_sharing    = "/ssm/documents/console/public-sharing-permission"
    automation_log_destination = "/ssm/automation/customer-script-log-destination"
    automation_log_group       = "/ssm/automation/customer-script-log-group-name"
    default_host_management    = "/ssm/managed-instance/default-ec2-instance-management-role"
  }

  automation_log_group_name = "/aws/ssm/${local.base_name}/automation"
  session_log_group_name    = "/aws/ssm/${local.base_name}/sessions"

  log_group_arns = {
    for region in local.key_regions : region => [
      for name in [local.automation_log_group_name, local.session_log_group_name] :
      "arn:${local.partition}:logs:${region}:${local.account_id}:log-group:${name}"
    ]
  }

  session_log_group_arns = [
    for region in local.session_regions : "arn:${local.partition}:logs:${region}:${local.account_id}:log-group:${local.session_log_group_name}"
  ]

  sync_source_accounts = distinct(concat([local.account_id], local.bucket_enabled ? var.inventory_bucket.allowed_account_ids : []))
  sync_source_arns     = [for account_id in local.sync_source_accounts : "arn:${local.partition}:ssm:*:${account_id}:resource-data-sync/*"]
  organization_id      = var.inventory_bucket.organization_id

  kms_service_statement_candidates = {
    for region in local.key_regions : region => [
      {
        when = true
        statement = {
          sid        = "AllowCloudWatchLogs"
          actions    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
          principals = { Service = ["logs.${region}.${local.dns_suffix}"] }
          conditions = [{ test = "ArnEquals", variable = "kms:EncryptionContext:aws:logs:arn", values = local.log_group_arns[region] }]
        }
      },
      {
        when = true
        statement = {
          sid        = "AllowResourceDataSync"
          actions    = ["kms:GenerateDataKey"]
          principals = { Service = ["ssm.amazonaws.com"] }
          conditions = [
            { test = "StringEquals", variable = "aws:SourceAccount", values = local.sync_source_accounts },
            { test = "ArnLike", variable = "aws:SourceArn", values = local.sync_source_arns },
          ]
        }
      },
      {
        when = local.bucket_enabled && local.organization_id != null
        statement = {
          sid        = "AllowResourceDataSyncOrganization"
          actions    = ["kms:GenerateDataKey"]
          principals = { Service = ["ssm.amazonaws.com"] }
          conditions = [{ test = "StringEquals", variable = "aws:SourceOrgID", values = [coalesce(local.organization_id, "none")] }]
        }
      },
    ]
  }

  kms_service_statements = { for region, candidates in local.kms_service_statement_candidates : region => [for c in candidates : c.statement if c.when] }

  session_kms_key_arns = [for region in local.session_regions : local.kms_key_arns[region]]
  s3_logs              = var.session_manager.s3_logs
  s3_logs_prefix       = trim(local.s3_logs.prefix, "/")
  s3_logs_bucket_arn   = "arn:${local.partition}:s3:::${coalesce(local.s3_logs.bucket, "none")}"

  session_statement_candidates = [
    {
      when = local.session_enabled && local.kms_enabled
      statement = {
        Sid      = "DecryptSessionData"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = local.session_kms_key_arns
      }
    },
    {
      when = local.session_enabled
      statement = {
        Sid      = "WriteSessionLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:DescribeLogStreams", "logs:PutLogEvents"]
        Resource = flatten([for arn in local.session_log_group_arns : [arn, "${arn}:*"]])
      }
    },
    {
      when = local.session_enabled
      statement = {
        Sid      = "CheckSessionLogGroupEncryption"
        Effect   = "Allow"
        Action   = ["logs:DescribeLogGroups"]
        Resource = ["*"]
      }
    },
    {
      when = local.s3_logs_enabled
      statement = {
        Sid      = "WriteSessionLogObjects"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = ["${local.s3_logs_bucket_arn}/${local.s3_logs_prefix == "" ? "" : "${local.s3_logs_prefix}/"}*"]
      }
    },
    {
      when = local.s3_logs_enabled
      statement = {
        Sid      = "CheckSessionLogBucketEncryption"
        Effect   = "Allow"
        Action   = ["s3:GetEncryptionConfiguration"]
        Resource = [local.s3_logs_bucket_arn]
      }
    },
    {
      when = local.s3_logs_enabled && local.s3_logs.kms_key_arn != null
      statement = {
        Sid      = "EncryptSessionLogObjects"
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey"]
        Resource = [local.s3_logs.kms_key_arn]
      }
    },
  ]

  session_policy_json = jsonencode({
    Version   = "2012-10-17"
    Statement = [for c in local.session_statement_candidates : c.statement if c.when]
  })

  patch_logs            = var.patching.output_logs
  patch_logs_prefix     = trim(local.patch_logs.prefix, "/")
  patch_logs_bucket_arn = "arn:${local.partition}:s3:::${coalesce(local.patch_logs.bucket, "none")}"

  patch_node_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "WritePatchLogObjects"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = ["${local.patch_logs_bucket_arn}/${local.patch_logs_prefix == "" ? "" : "${local.patch_logs_prefix}/"}*"]
      },
      {
        Sid      = "CheckPatchLogBucketEncryption"
        Effect   = "Allow"
        Action   = ["s3:GetEncryptionConfiguration"]
        Resource = [local.patch_logs_bucket_arn]
      },
    ]
  })

  dhmc_managed_policy_arns = concat(
    ["arn:${local.partition}:iam::aws:policy/AmazonSSMManagedEC2InstanceDefaultPolicy"],
    local.patching_enabled ? ["arn:${local.partition}:iam::aws:policy/AWSQuickSetupPatchPolicyBaselineAccess"] : [],
  )

  dhmc_policy_documents = concat(
    local.session_enabled ? [local.session_policy_json] : [],
    local.patch_logs_enabled ? [local.patch_node_policy_json] : [],
  )

  patch_administration_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AssumePatchPolicyExecutionRole"
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = [for role in module.patch_execution_role : "arn:${local.partition}:iam::${local.account_id}:role/${role.name}"]
      },
    ]
  })

  session_document_content = {
    for region in local.session_regions : region => jsonencode({
      schemaVersion = "1.0"
      description   = "Session Manager preferences for ${local.base_name}"
      sessionType   = "Standard_Stream"
      inputs = {
        s3BucketName                = local.s3_logs_enabled ? local.s3_logs.bucket : ""
        s3KeyPrefix                 = local.s3_logs_enabled ? local.s3_logs_prefix : ""
        s3EncryptionEnabled         = true
        cloudWatchLogGroupName      = module.session_log_group[region].name
        cloudWatchEncryptionEnabled = true
        cloudWatchStreamingEnabled  = var.session_manager.cloudwatch_streaming_enabled
        kmsKeyId                    = try(coalesce(local.kms_key_arns[region]), "")
        runAsEnabled                = var.session_manager.run_as_enabled
        runAsDefaultUser            = var.session_manager.run_as_enabled ? var.session_manager.run_as_default_user : ""
        idleSessionTimeout          = tostring(var.session_manager.idle_session_timeout)
        maxSessionDuration          = tostring(var.session_manager.max_session_duration)
        shellProfile = {
          linux   = var.session_manager.shell_profile.linux
          windows = var.session_manager.shell_profile.windows
        }
      }
    })
  }

  patch_operating_system_family = {
    AMAZON_LINUX_2          = "rpm"
    AMAZON_LINUX_2023       = "rpm"
    REDHAT_ENTERPRISE_LINUX = "rpm"
    ROCKY_LINUX             = "rpm"
    ALMA_LINUX              = "rpm"
    SUSE                    = "rpm"
    UBUNTU                  = "deb"
    DEBIAN                  = "deb"
    WINDOWS                 = "windows"
  }

  patch_default_filters = {
    rpm = {
      CLASSIFICATION = ["Security"]
      SEVERITY       = ["Critical", "Important"]
    }
    deb = {
      PRIORITY = ["Required", "Important", "Standard", "Optional", "Extra"]
    }
    windows = {
      CLASSIFICATION = ["CriticalUpdates", "SecurityUpdates"]
      MSRC_SEVERITY  = ["Critical", "Important"]
    }
  }

  patch_baselines = {
    for key, baseline in var.patching.baselines.custom : key => {
      name                    = module.naming.names["baseline-${key}"]
      operating_system        = baseline.operating_system
      description             = coalesce(baseline.description, "Security patch baseline for ${baseline.operating_system}.")
      approve_after_days      = baseline.approve_after_days != null ? baseline.approve_after_days : (contains(["UBUNTU", "DEBIAN"], baseline.operating_system) ? 0 : 7)
      patch_filters           = baseline.patch_filters != null ? baseline.patch_filters : try(local.patch_default_filters[local.patch_operating_system_family[baseline.operating_system]], {})
      compliance_level        = baseline.compliance_level
      enable_non_security     = baseline.enable_non_security
      rejected_patches        = baseline.rejected_patches
      rejected_patches_action = baseline.rejected_patches_action
    }
  }

  default_patch_baseline_groups = {
    for baseline in try(data.aws_ssm_patch_baselines.default[0].baseline_identities, []) : baseline.operating_system => baseline...
  }

  default_patch_baselines = {
    for operating_system, baselines in local.default_patch_baseline_groups : operating_system => {
      value       = baselines[0].baseline_id
      label       = baselines[0].baseline_name
      description = baselines[0].baseline_description
      disabled    = !baselines[0].default_baseline
    }
  }

  custom_patch_baselines = {
    for key, baseline in aws_ssm_patch_baseline.this : local.patch_baselines[key].operating_system => {
      value       = baseline.id
      label       = local.patch_baselines[key].name
      description = local.patch_baselines[key].description
      disabled    = false
    }
  }

  patch_target                       = var.patching.target
  patch_organizational_units_enabled = length(var.patching.target_organizational_units) > 0

  patch_policy_parameters = merge(
    {
      PatchPolicyName                      = module.naming.names.patch_policy
      SelectedPatchBaselines               = jsonencode(merge(local.default_patch_baselines, local.custom_patch_baselines))
      PatchBaselineUseDefault              = var.patching.baselines.use_default ? "default" : "custom"
      PatchBaselineRegion                  = local.provider_region
      ConfigurationOptionsPatchOperation   = var.patching.operation
      ConfigurationOptionsScanValue        = var.patching.scan_schedule
      ConfigurationOptionsScanNextInterval = "false"
      RebootOption                         = var.patching.reboot_option
      IsPolicyAttachAllowed                = tostring(var.patching.attach_instance_policies)
      OutputLogEnableS3                    = tostring(var.patching.output_logs.enabled)
      TargetType                           = local.patch_target.type
      TargetRegions                        = join(",", local.regions)
    },
    var.patching.operation == "ScanAndInstall" ? {
      ConfigurationOptionsInstallValue        = var.patching.install_schedule
      ConfigurationOptionsInstallNextInterval = "true"
    } : {},
    var.patching.output_logs.enabled ? {
      OutputS3Location = jsonencode({
        OutputBucketRegion = local.provider_region
        OutputS3BucketName = local.patch_logs.bucket
        OutputS3KeyPrefix  = local.patch_logs_prefix
      })
    } : {},
    local.patch_target.type == "Tags" ? {
      TargetTagKey   = local.patch_target.tag_key
      TargetTagValue = local.patch_target.tag_value
    } : {},
    local.patch_target.type == "ResourceGroups" ? {
      ResourceGroupName = local.patch_target.resource_group_name
    } : {},
    local.patch_target.type == "InstanceIds" ? {
      TargetInstances = join(",", local.patch_target.instance_ids)
    } : {},
    local.patch_organizational_units_enabled ? { TargetOrganizationalUnits = join(",", var.patching.target_organizational_units) } : { TargetAccounts = local.account_id },
  )

  inventory_parameters = merge({
    applications                = "Enabled"
    awsComponents               = "Enabled"
    customInventory             = "Enabled"
    instanceDetailedInformation = "Enabled"
    networkConfig               = "Enabled"
    services                    = "Enabled"
    windowsRoles                = "Enabled"
    windowsUpdates              = "Enabled"
  }, var.inventory.parameters)

  agent_update_parameters = var.agent_update.version == null ? {} : { version = var.agent_update.version }

  bucket_name        = module.naming.names.bucket
  bucket_arn         = "arn:${local.partition}:s3:::${local.bucket_name}"
  bucket_kms_key_arn = local.bucket_enabled ? local.kms_key_arns[local.provider_region] : null

  sync               = var.inventory.resource_data_sync
  sync_prefix        = trim(local.sync.prefix, "/")
  sync_prefix_path   = local.sync_prefix == "" ? "" : "${local.sync_prefix}/"
  sync_bucket_name   = coalesce(local.sync.bucket_name, local.bucket_name)
  sync_bucket_region = local.sync.bucket_name != null ? coalesce(local.sync.bucket_region, local.provider_region) : local.provider_region
  sync_kms_key_arn   = local.sync.kms_key_arn != null ? local.sync.kms_key_arn : try(local.kms_key_arns[local.sync_bucket_region], null)

  bucket_delivery_resources = [for account_id in local.sync_source_accounts : "${local.bucket_arn}/${local.sync_prefix_path}*/accountid=${account_id}/*"]
  bucket_org_resources      = ["${local.bucket_arn}/${local.sync_prefix_path}*/accountid=*/*"]

  bucket_encryption_conditions = local.kms_enabled ? [
    { test = "StringEquals", variable = "s3:x-amz-server-side-encryption", values = ["aws:kms"] },
    { test = "StringEquals", variable = "s3:x-amz-server-side-encryption-aws-kms-key-id", values = [local.bucket_kms_key_arn] },
  ] : []

  bucket_lifecycle_rules = var.inventory_bucket.lifecycle.expiration_days == null ? [] : [
    { id = "expire-inventory", expiration_days = var.inventory_bucket.lifecycle.expiration_days }
  ]

  bucket_statement_candidates = [
    {
      when = true
      statement = {
        sid        = "SSMBucketPermissionsCheck"
        actions    = ["s3:GetBucketAcl"]
        resources  = [local.bucket_arn]
        principals = { Service = ["ssm.amazonaws.com"] }
        conditions = [{ test = "StringEquals", variable = "aws:SourceAccount", values = local.sync_source_accounts }]
      }
    },
    {
      when = true
      statement = {
        sid        = "SSMBucketDelivery"
        actions    = ["s3:PutObject"]
        resources  = local.bucket_delivery_resources
        principals = { Service = ["ssm.amazonaws.com"] }
        conditions = concat([
          { test = "StringEquals", variable = "s3:x-amz-acl", values = ["bucket-owner-full-control"] },
          { test = "StringEquals", variable = "aws:SourceAccount", values = local.sync_source_accounts },
          { test = "ArnLike", variable = "aws:SourceArn", values = local.sync_source_arns },
        ], local.bucket_encryption_conditions)
      }
    },
    {
      when = true
      statement = {
        sid        = "SSMBucketDeliveryTagging"
        actions    = ["s3:PutObjectTagging"]
        resources  = local.bucket_delivery_resources
        principals = { Service = ["ssm.amazonaws.com"] }
        conditions = [
          { test = "StringEquals", variable = "aws:SourceAccount", values = local.sync_source_accounts },
          { test = "ArnLike", variable = "aws:SourceArn", values = local.sync_source_arns },
        ]
      }
    },
    {
      when = local.organization_id != null
      statement = {
        sid        = "SSMBucketPermissionsCheckOrganization"
        actions    = ["s3:GetBucketAcl"]
        resources  = [local.bucket_arn]
        principals = { Service = ["ssm.amazonaws.com"] }
        conditions = [{ test = "StringEquals", variable = "aws:SourceOrgID", values = [coalesce(local.organization_id, "-")] }]
      }
    },
    {
      when = local.organization_id != null
      statement = {
        sid        = "SSMBucketDeliveryOrganization"
        actions    = ["s3:PutObject"]
        resources  = local.bucket_org_resources
        principals = { Service = ["ssm.amazonaws.com"] }
        conditions = concat([
          { test = "StringEquals", variable = "s3:x-amz-acl", values = ["bucket-owner-full-control"] },
          { test = "StringEquals", variable = "aws:SourceOrgID", values = [coalesce(local.organization_id, "-")] },
        ], local.bucket_encryption_conditions)
      }
    },
    {
      when = local.organization_id != null
      statement = {
        sid        = "SSMBucketDeliveryTaggingOrganization"
        actions    = ["s3:PutObjectTagging"]
        resources  = local.bucket_org_resources
        principals = { Service = ["ssm.amazonaws.com"] }
        conditions = [{ test = "StringEquals", variable = "aws:SourceOrgID", values = [coalesce(local.organization_id, "-")] }]
      }
    },
  ]

  bucket_policy_statements = [for c in local.bucket_statement_candidates : c.statement if c.when]

  quick_setup_parameters = {
    UpdateSsmAgent            = tostring(var.quick_setup_host_management.update_ssm_agent)
    CollectInventory          = tostring(var.quick_setup_host_management.collect_inventory)
    ScanInstances             = tostring(var.quick_setup_host_management.scan_instances && !local.patching_enabled)
    UpdateEc2LaunchAgent      = tostring(var.quick_setup_host_management.update_ec2_launch_agent)
    InstallCloudWatchAgent    = tostring(var.quick_setup_host_management.install_cloudwatch_agent)
    UpdateCloudWatchAgent     = tostring(var.quick_setup_host_management.update_cloudwatch_agent)
    IsPolicyAttachAllowed     = tostring(var.quick_setup_host_management.is_policy_attach_allowed)
    TargetOrganizationalUnits = join(",", var.quick_setup_host_management.target_organizational_units)
    TargetRegions             = join(",", coalesce(var.quick_setup_host_management.target_regions, local.regions))
  }
}
