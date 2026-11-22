module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  tags        = var.tags
  names = {
    vault = { max_length = 50 }
  }
}

module "encryption" {
  source   = "../../core/encryption"
  for_each = local.vault_regs

  application        = var.application
  environment        = var.environment
  purpose            = "backup"
  tags               = var.tags
  region             = each.key
  kms                = var.kms
  service_statements = local.kms_statement_sets[each.key]
}

module "kms_policy" {
  source = "../../core/policy-document"

  default_resources = ["*"]
  statements        = local.kms_statement_sets["all"]
}

module "role" {
  source = "../../security/iam-role"
  count  = local.create_role ? 1 : 0

  application              = var.application
  environment              = var.environment
  purpose                  = "backup"
  tags                     = var.tags
  role_name                = var.iam_role.name
  path                     = var.iam_role.path
  permissions_boundary_arn = var.iam_role.permissions_boundary_arn
  managed_policy_arns      = local.managed_policy_arns
  policy_statements        = var.iam_role.policy_statements
  trust = {
    services   = ["backup.${module.naming.dns_suffix}"]
    conditions = [{ test = "StringEquals", variable = "aws:SourceAccount", values = [local.account_id] }]
  }
}

resource "aws_backup_vault" "this" {
  for_each = local.vault_regs

  region        = each.key
  name          = local.vault_name
  kms_key_arn   = local.kms_key_arns[each.key]
  force_destroy = !var.deletion_protection

  tags = merge(module.naming.tags, { Name = local.vault_name })
}

resource "aws_backup_vault_policy" "this" {
  for_each = local.vault_regs

  region            = each.key
  backup_vault_name = aws_backup_vault.this[each.key].name
  policy            = local.vault_policy
}

resource "aws_backup_vault_lock_configuration" "this" {
  for_each = var.vault_lock.enabled ? local.vault_regs : toset([])

  region              = each.key
  backup_vault_name   = aws_backup_vault.this[each.key].name
  min_retention_days  = var.vault_lock.min_retention_days
  max_retention_days  = var.vault_lock.max_retention_days
  changeable_for_days = var.vault_lock.mode == "COMPLIANCE" ? var.vault_lock.changeable_for_days : null
}

resource "aws_backup_vault_notifications" "this" {
  for_each = var.vault_notifications.enabled ? { for r in local.vault_regs : r => var.vault_notifications.sns_topic_arns[r] if contains(keys(var.vault_notifications.sns_topic_arns), r) } : {}

  region              = each.key
  backup_vault_name   = aws_backup_vault.this[each.key].name
  sns_topic_arn       = each.value
  backup_vault_events = var.vault_notifications.events
}

resource "aws_backup_plan" "this" {
  for_each = local.plan_regs

  region = each.key
  name   = local.plan_name

  dynamic "rule" {
    for_each = var.rules

    content {
      rule_name                    = rule.key
      target_vault_name            = aws_backup_vault.this[each.key].name
      schedule                     = rule.value.schedule
      schedule_expression_timezone = rule.value.schedule_expression_timezone
      start_window                 = rule.value.start_window
      completion_window            = rule.value.completion_window
      enable_continuous_backup     = rule.value.enable_continuous_backup
      recovery_point_tags          = module.naming.tags

      lifecycle {
        delete_after                              = rule.value.delete_after
        cold_storage_after                        = rule.value.cold_storage_after
        opt_in_to_archive_for_supported_resources = rule.value.opt_in_to_archive_for_supported_resources
      }

      dynamic "copy_action" {
        for_each = rule.value.copy_to

        content {
          destination_vault_arn = copy_action.value.destination_vault_arn

          lifecycle {
            delete_after       = coalesce(copy_action.value.delete_after, rule.value.delete_after)
            cold_storage_after = copy_action.value.cold_storage_after
          }
        }
      }
    }
  }

  tags = merge(module.naming.tags, { Name = local.plan_name })

  depends_on = [aws_backup_vault_lock_configuration.this]
}

resource "aws_backup_selection" "this" {
  for_each = local.plan_regs

  region        = each.key
  name          = local.plan_name
  plan_id       = aws_backup_plan.this[each.key].id
  iam_role_arn  = local.role_arn
  resources     = local.selection_resources
  not_resources = length(var.not_resources) > 0 ? var.not_resources : null

  dynamic "condition" {
    for_each = length(var.selection_tags) > 0 ? [local.selection_conditions] : []

    content {
      dynamic "string_equals" {
        for_each = condition.value.string_equals

        content {
          key   = string_equals.value.key
          value = string_equals.value.value
        }
      }

      dynamic "string_like" {
        for_each = condition.value.string_like

        content {
          key   = string_like.value.key
          value = string_like.value.value
        }
      }

      dynamic "string_not_equals" {
        for_each = condition.value.string_not_equals

        content {
          key   = string_not_equals.value.key
          value = string_not_equals.value.value
        }
      }

      dynamic "string_not_like" {
        for_each = condition.value.string_not_like

        content {
          key   = string_not_like.value.key
          value = string_not_like.value.value
        }
      }
    }
  }

  depends_on = [module.role]
}

resource "aws_backup_region_settings" "this" {
  for_each = var.region_settings.enabled ? local.vault_regs : toset([])

  region                              = each.key
  resource_type_opt_in_preference     = var.region_settings.resource_type_opt_in_preference
  resource_type_management_preference = var.region_settings.resource_type_management_preference
}
