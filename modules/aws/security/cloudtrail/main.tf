module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  tags        = var.tags
  names = {
    trail  = { max_length = 128 }
    bucket = { suffix = "cloudtrail", uniqueness = "global", max_length = 63 }
  }
}

module "encryption" {
  source = "../../core/encryption"

  application        = var.application
  environment        = var.environment
  purpose            = "cloudtrail"
  tags               = var.tags
  kms                = merge(var.kms, { create = local.kms_create })
  service_statements = local.kms_service_statements
}

module "kms_policy" {
  source = "../../core/policy-document"

  default_resources = ["*"]
  statements        = local.kms_service_statements
}

module "log_group" {
  source = "../../observability/log-group"
  count  = local.cloudwatch_enabled ? 1 : 0

  application                 = var.application
  environment                 = var.environment
  tags                        = var.tags
  log_group_name              = local.log_group_name
  retention_in_days           = var.cloudwatch_logs.retention_in_days
  log_group_class             = var.cloudwatch_logs.log_group_class
  deletion_protection_enabled = var.cloudwatch_logs.deletion_protection_enabled
  kms_key_arn                 = try(coalesce(var.cloudwatch_logs.kms_key_arn, local.kms_key_arn), null)
}

module "role" {
  source = "../../security/iam-role"
  count  = local.role_enabled ? 1 : 0

  application              = var.application
  environment              = var.environment
  purpose                  = "trail-logs"
  tags                     = var.tags
  role_name                = var.iam_role.name
  path                     = var.iam_role.path
  permissions_boundary_arn = var.iam_role.permissions_boundary_arn
  managed_policy_arns      = var.iam_role.managed_policy_arns
  policy_statements        = var.iam_role.policy_statements
  policy_documents         = [jsonencode({ Version = "2012-10-17", Statement = local.role_statements })]
  trust = {
    services = ["cloudtrail.amazonaws.com"]
  }
}

resource "aws_organizations_aws_service_access" "this" {
  count = var.organization_admin.enabled && var.organization_admin.manage_trusted_access ? 1 : 0

  service_principal = "cloudtrail.amazonaws.com"
}

resource "aws_cloudtrail_organization_delegated_admin_account" "this" {
  count = var.organization_admin.enabled ? length(var.organization_admin.account_ids) : 0

  account_id = var.organization_admin.account_ids[count.index]

  depends_on = [aws_organizations_aws_service_access.this]

  lifecycle {
    precondition {
      condition     = var.organization_admin.account_ids[count.index] != module.naming.account_id
      error_message = "organization_admin.account_ids: member accounts only."
    }
  }
}

resource "aws_cloudtrail" "this" {
  count = var.trail.enabled ? 1 : 0

  name                          = local.trail_name
  s3_bucket_name                = local.bucket_name
  s3_key_prefix                 = local.key_prefix
  kms_key_id                    = local.kms_key_arn
  is_organization_trail         = var.trail.is_organization_trail
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
  enable_logging                = true
  cloud_watch_logs_group_arn    = local.cloudwatch_enabled ? "${module.log_group[0].arn}:*" : null
  cloud_watch_logs_role_arn     = local.role_arn

  dynamic "advanced_event_selector" {
    for_each = local.advanced_event_selectors

    content {
      name = advanced_event_selector.value.name

      dynamic "field_selector" {
        for_each = advanced_event_selector.value.field_selectors

        content {
          field       = field_selector.value.field
          equals      = field_selector.value.equals
          not_equals  = field_selector.value.not_equals
          starts_with = field_selector.value.starts_with
        }
      }
    }
  }

  dynamic "insight_selector" {
    for_each = var.trail.insight_types

    content {
      insight_type = insight_selector.value
    }
  }

  tags = merge(module.naming.tags, { Name = local.trail_name })

  depends_on = [
    aws_organizations_aws_service_access.this,
    module.bucket,
    module.role,
  ]

  lifecycle {
    precondition {
      condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", local.trail_name))
      error_message = "Trail name: letters, digits, single hyphens."
    }

    precondition {
      condition     = split(":", local.kms_key_arn)[3] == module.naming.region
      error_message = "kms: key in the provider Region."
    }
  }
}
