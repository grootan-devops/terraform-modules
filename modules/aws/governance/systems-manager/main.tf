module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  tags        = var.tags
  names = merge(
    {
      inventory    = { suffix = "inventory", max_length = 128 }
      agent_update = { suffix = "ssm-agent-update", max_length = 128 }
      sync         = { suffix = "inventory", max_length = 64 }
      quick_setup  = { suffix = "host-management", max_length = 64 }
      patch_policy = { suffix = "patch-policy", max_length = 64 }
      bucket       = { suffix = "ssm-inventory", uniqueness = "global", max_length = 63 }
    },
    { for key in keys(var.patching.baselines.custom) : "baseline-${key}" => { suffix = key, max_length = 128 } }
  )
}

module "encryption" {
  source   = "../../core/encryption"
  for_each = local.key_regions

  application        = var.application
  environment        = var.environment
  purpose            = "ssm"
  tags               = var.tags
  region             = each.key
  kms                = var.kms
  service_statements = local.kms_service_statements[each.key]
}

resource "aws_ssm_service_setting" "document_public_sharing" {
  for_each = local.public_sharing_regions

  region        = each.key
  setting_id    = local.setting_ids.document_public_sharing
  setting_value = "Disable"
}

module "automation_log_group" {
  source   = "../../observability/log-group"
  for_each = local.automation_logging_regions

  application                 = var.application
  environment                 = var.environment
  tags                        = var.tags
  region                      = each.key
  log_group_name              = local.automation_log_group_name
  retention_in_days           = var.cloudwatch_logs.retention_in_days
  log_group_class             = var.cloudwatch_logs.log_group_class
  deletion_protection_enabled = var.cloudwatch_logs.deletion_protection_enabled
  kms_key_arn                 = local.kms_key_arns[each.key]
}

resource "aws_ssm_service_setting" "automation_log_destination" {
  for_each = local.automation_logging_regions

  region        = each.key
  setting_id    = local.setting_ids.automation_log_destination
  setting_value = "CloudWatch"
}

resource "aws_ssm_service_setting" "automation_log_group" {
  for_each = local.automation_logging_regions

  region        = each.key
  setting_id    = local.setting_ids.automation_log_group
  setting_value = module.automation_log_group[each.key].name

  depends_on = [aws_ssm_service_setting.automation_log_destination]
}

resource "aws_ssm_service_setting" "default_host_management" {
  for_each = local.dhmc_regions

  region        = each.key
  setting_id    = local.setting_ids.default_host_management
  setting_value = "service-role/${module.dhmc_role[0].name}"
}

module "session_log_group" {
  source   = "../../observability/log-group"
  for_each = local.session_regions

  application                 = var.application
  environment                 = var.environment
  tags                        = var.tags
  region                      = each.key
  log_group_name              = local.session_log_group_name
  retention_in_days           = var.cloudwatch_logs.retention_in_days
  log_group_class             = var.cloudwatch_logs.log_group_class
  deletion_protection_enabled = var.cloudwatch_logs.deletion_protection_enabled
  kms_key_arn                 = local.kms_key_arns[each.key]
}

resource "aws_ssm_document" "session_manager" {
  for_each = local.session_regions

  region          = each.key
  name            = "SSM-SessionManagerRunShell"
  document_type   = "Session"
  document_format = "JSON"
  content         = local.session_document_content[each.key]

  tags = merge(module.naming.tags, { Name = "SSM-SessionManagerRunShell" })
}
