resource "aws_backup_framework" "this" {
  for_each = var.audit_framework.enabled ? local.vault_regs : toset([])

  region      = each.key
  name        = local.framework_name
  description = "${local.vault_name} backup controls"

  dynamic "control" {
    for_each = local.framework_controls

    content {
      name = control.key

      dynamic "input_parameter" {
        for_each = control.value.parameters

        content {
          name  = input_parameter.key
          value = input_parameter.value
        }
      }

      dynamic "scope" {
        for_each = control.value.resource_ids == null && control.value.resource_types == null ? [] : [control.value]

        content {
          compliance_resource_ids   = scope.value.resource_ids
          compliance_resource_types = scope.value.resource_types
        }
      }
    }
  }

  tags = merge(module.naming.tags, { Name = local.framework_name })

  depends_on = [
    aws_backup_vault_policy.this,
    aws_backup_selection.this,
  ]
}

resource "aws_backup_report_plan" "this" {
  for_each = var.report_plan.enabled ? local.vault_regs : toset([])

  region      = each.key
  name        = local.report_plan_name
  description = "${local.vault_name} ${lower(var.report_plan.report_template)}"

  report_delivery_channel {
    formats        = var.report_plan.formats
    s3_bucket_name = var.report_plan.s3_bucket_name
    s3_key_prefix  = local.report_key_prefix == "" ? null : local.report_key_prefix
  }

  report_setting {
    report_template = var.report_plan.report_template
    framework_arns  = local.compliance_report ? [aws_backup_framework.this[each.key].arn] : null
  }

  tags = merge(module.naming.tags, { Name = local.report_plan_name })
}
