locals {
  partition  = module.naming.partition
  dns_suffix = module.naming.dns_suffix
  account_id = module.naming.account_id
  regions    = length(var.regions) > 0 ? distinct(var.regions) : [module.naming.region]

  detector_regions     = var.detector.enabled ? local.regions : []
  organization_regions = var.organization_configuration.enabled ? local.detector_regions : []
  admin_regions        = var.organization_admin.enabled ? toset(local.regions) : toset([])
  auto_enable_members  = var.organization_configuration.auto_enable_members

  feature_catalog = {
    S3_DATA_EVENTS = {
      enabled    = var.features.s3_data_events
      additional = []
    }
    EKS_AUDIT_LOGS = {
      enabled    = var.features.eks_audit_logs
      additional = []
    }
    EBS_MALWARE_PROTECTION = {
      enabled    = var.features.ebs_malware_protection
      additional = []
    }
    RDS_LOGIN_EVENTS = {
      enabled = var.features.rds_login_events
      additional = [
        { name = "RDS_DATA_RISK", enabled = var.features.rds_login_events && var.features.rds_data_risk },
      ]
    }
    LAMBDA_NETWORK_LOGS = {
      enabled    = var.features.lambda_network_logs
      additional = []
    }
    RUNTIME_MONITORING = {
      enabled = var.features.runtime_monitoring
      additional = [
        { name = "EKS_ADDON_MANAGEMENT", enabled = var.features.runtime_monitoring && var.features.eks_addon_management },
        { name = "ECS_FARGATE_AGENT_MANAGEMENT", enabled = var.features.runtime_monitoring && var.features.ecs_fargate_agent_management },
        { name = "EC2_AGENT_MANAGEMENT", enabled = var.features.runtime_monitoring && var.features.ec2_agent_management },
      ]
    }
    AI_PROTECTION = {
      enabled    = var.features.ai_protection
      additional = []
    }
  }

  feature_instances = {
    for pair in setproduct(local.detector_regions, keys(local.feature_catalog)) : "${pair[0]}/${pair[1]}" => {
      region = pair[0]
      name   = pair[1]
    }
  }

  organization_feature_instances = var.organization_configuration.enabled ? local.feature_instances : {}

  filter_ranks = { for index, key in sort(keys(var.filters)) : key => coalesce(var.filters[key].rank, index + 1) }

  filter_criteria = {
    for key, filter in var.filters : key => {
      for field, condition in filter.criteria : field => {
        equals                = try(length(condition.equals) > 0, false) ? condition.equals : null
        not_equals            = try(length(condition.not_equals) > 0, false) ? condition.not_equals : null
        matches               = try(length(condition.matches) > 0, false) ? condition.matches : null
        not_matches           = try(length(condition.not_matches) > 0, false) ? condition.not_matches : null
        greater_than          = condition.greater_than
        greater_than_or_equal = condition.greater_than_or_equal
        less_than             = condition.less_than
        less_than_or_equal    = condition.less_than_or_equal
      }
    }
  }

  filter_instances = {
    for pair in setproduct(local.detector_regions, keys(var.filters)) : "${pair[0]}/${pair[1]}" => {
      region = pair[0]
      key    = pair[1]
    }
  }

  export_enabled     = var.detector.enabled && var.publishing_destination.enabled
  export_regions     = local.export_enabled && !var.publishing_destination.policies_only ? toset(local.regions) : toset([])
  bucket_arn         = var.publishing_destination.bucket_arn == null ? "" : var.publishing_destination.bucket_arn
  destination_prefix = trim(coalesce(var.publishing_destination.prefix, "/"), "/")
  destination_arn    = local.destination_prefix == "" ? local.bucket_arn : "${local.bucket_arn}/${local.destination_prefix}"
  kms_key_arn        = module.encryption.key_arn

  opt_in_regions = toset(try(data.aws_regions.opt_in[0].names, []))
  service_principals = sort(distinct([
    for region in local.regions : contains(local.opt_in_regions, region) ? "guardduty.${region}.${local.dns_suffix}" : "guardduty.${local.dns_suffix}"
  ]))
  detector_source_arns = [for region in local.regions : "arn:${local.partition}:guardduty:${region}:${local.account_id}:detector/*"]

  service_conditions = [
    { test = "StringEquals", variable = "aws:SourceAccount", values = [local.account_id] },
    { test = "ArnLike", variable = "aws:SourceArn", values = local.detector_source_arns },
  ]

  kms_statement_candidates = [{
    sid        = "AllowGuardDutyEncryptFindings"
    actions    = ["kms:GenerateDataKey"]
    principals = { Service = local.service_principals }
    conditions = local.service_conditions
  }]

  kms_service_statements = [for s in local.kms_statement_candidates : s if local.export_enabled]

  destination_statement_candidates = [
    {
      sid        = "AllowGuardDutyGetBucketLocation"
      actions    = ["s3:GetBucketLocation"]
      resources  = [local.bucket_arn]
      principals = { Service = local.service_principals }
      conditions = local.service_conditions
    },
    {
      sid        = "AllowGuardDutyPutObject"
      actions    = ["s3:PutObject"]
      resources  = ["${local.destination_arn}/*"]
      principals = { Service = local.service_principals }
      conditions = local.service_conditions
    },
    {
      sid        = "DenyGuardDutyUnencryptedObjectUploads"
      effect     = "Deny"
      actions    = ["s3:PutObject"]
      resources  = ["${local.destination_arn}/*"]
      principals = { Service = local.service_principals }
      conditions = [{ test = "StringNotEquals", variable = "s3:x-amz-server-side-encryption", values = ["aws:kms"] }]
    },
    {
      sid        = "DenyGuardDutyIncorrectEncryptionKey"
      effect     = "Deny"
      actions    = ["s3:PutObject"]
      resources  = ["${local.destination_arn}/*"]
      principals = { Service = local.service_principals }
      conditions = [{ test = "StringNotEquals", variable = "s3:x-amz-server-side-encryption-aws-kms-key-id", values = [local.kms_key_arn] }]
    },
    {
      sid        = "DenyInsecureTransport"
      effect     = "Deny"
      actions    = ["s3:*"]
      resources  = [local.bucket_arn, "${local.destination_arn}/*"]
      principals = { AWS = ["*"] }
      conditions = [{ test = "Bool", variable = "aws:SecureTransport", values = ["false"] }]
    },
    {
      sid        = "DenyOutdatedTls"
      effect     = "Deny"
      actions    = ["s3:*"]
      resources  = [local.bucket_arn, "${local.destination_arn}/*"]
      principals = { AWS = ["*"] }
      conditions = [{ test = "NumericLessThan", variable = "s3:TlsVersion", values = ["1.2"] }]
    },
  ]

  destination_statements = [for s in local.destination_statement_candidates : s if local.export_enabled]
}
