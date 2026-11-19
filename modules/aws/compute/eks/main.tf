module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags
  names       = local.names
}

module "encryption" {
  source = "../../core/encryption"

  application        = var.application
  environment        = var.environment
  name               = var.name
  purpose            = "eks"
  tags               = var.tags
  kms                = var.kms
  service_statements = local.kms_service_statements
}

module "log_group" {
  source = "../../observability/log-group"
  count  = local.logs_enabled ? 1 : 0

  application                 = var.application
  environment                 = var.environment
  name                        = var.name
  tags                        = var.tags
  log_group_name              = local.log_group_name
  retention_in_days           = var.cloudwatch_logs.retention_in_days
  log_group_class             = var.cloudwatch_logs.log_group_class
  deletion_protection_enabled = var.cloudwatch_logs.deletion_protection_enabled
  kms_key_arn                 = try(coalesce(var.cloudwatch_logs.kms_key_arn, local.kms_key_arn), null)
}

module "insights_log_group" {
  source   = "../../observability/log-group"
  for_each = local.insights_log_names

  application                 = var.application
  environment                 = var.environment
  name                        = var.name
  tags                        = var.tags
  log_group_name              = each.value
  retention_in_days           = var.cloudwatch_logs.retention_in_days
  log_group_class             = var.cloudwatch_logs.log_group_class
  deletion_protection_enabled = var.cloudwatch_logs.deletion_protection_enabled
  kms_key_arn                 = try(coalesce(var.cloudwatch_logs.kms_key_arn, local.kms_key_arn), null)
}

module "security_group" {
  source = "../../network/security-group"
  count  = var.security_group.create ? 1 : 0

  application   = var.application
  environment   = var.environment
  name          = var.name
  purpose       = "api"
  tags          = var.tags
  vpc_id        = var.vpc_id
  ingress_rules = local.api_ingress_rules
  egress_rules  = local.api_egress_rules
}

#trivy:ignore:AVD-AWS-0039
resource "aws_eks_cluster" "this" {
  name                          = local.cluster_name
  version                       = var.cluster_version
  role_arn                      = module.cluster_role.arn
  deletion_protection           = var.deletion_protection
  bootstrap_self_managed_addons = false
  enabled_cluster_log_types     = var.cloudwatch_logs.log_types

  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = length(var.endpoint_public_access_cidrs) > 0
    public_access_cidrs     = length(var.endpoint_public_access_cidrs) > 0 ? var.endpoint_public_access_cidrs : null
    subnet_ids              = var.subnet_ids
    security_group_ids      = local.security_group_ids
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = var.bootstrap_cluster_creator_admin_permissions
  }

  dynamic "encryption_config" {
    for_each = local.kms_encrypted ? [1] : []
    content {
      resources = ["secrets"]

      provider {
        key_arn = local.kms_key_arn
      }
    }
  }

  upgrade_policy {
    support_type = var.upgrade_support_type
  }

  tags = merge(module.naming.tags, { Name = local.cluster_name })

  depends_on = [module.log_group, module.cluster_role]
}
