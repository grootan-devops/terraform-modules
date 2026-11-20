module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  tags        = var.tags
  names       = { for key in keys(var.configuration_policies) : key => { suffix = key, max_length = 128 } }
}

resource "aws_securityhub_organization_admin_account" "this" {
  count = var.organization_admin.enabled ? 1 : 0

  admin_account_id = var.organization_admin.account_id

  lifecycle {
    precondition {
      condition     = var.organization_admin.account_id != module.naming.account_id
      error_message = "organization_admin.account_id: a member account."
    }
  }
}

resource "aws_securityhub_account" "this" {
  count = var.hub.enabled ? 1 : 0

  enable_default_standards  = false
  control_finding_generator = "SECURITY_CONTROL"
  auto_enable_controls      = true

  lifecycle {
    ignore_changes = [enable_default_standards]
  }
}

resource "aws_securityhub_finding_aggregator" "this" {
  count = var.hub.enabled ? 1 : 0

  linking_mode      = var.finding_aggregator.linking_mode
  specified_regions = length(var.finding_aggregator.specified_regions) > 0 ? toset(var.finding_aggregator.specified_regions) : null

  depends_on = [aws_securityhub_account.this]
}

resource "aws_securityhub_organization_configuration" "this" {
  count = local.central_enabled ? 1 : 0

  auto_enable           = false
  auto_enable_standards = "NONE"

  organization_configuration {
    configuration_type = "CENTRAL"
  }

  depends_on = [aws_securityhub_finding_aggregator.this]
}

resource "aws_securityhub_configuration_policy" "this" {
  for_each = local.policies

  name        = module.naming.names[each.key]
  description = coalesce(each.value.description, "${module.naming.names[each.key]} configuration policy")

  configuration_policy {
    service_enabled       = each.value.service_enabled
    enabled_standard_arns = each.value.service_enabled ? local.policy_standard_arns[each.key] : null

    dynamic "security_controls_configuration" {
      for_each = each.value.service_enabled ? [each.value] : []
      iterator = controls

      content {
        disabled_control_identifiers = controls.value.enabled_control_identifiers == null ? controls.value.disabled_control_identifiers : null
        enabled_control_identifiers  = controls.value.enabled_control_identifiers

        dynamic "security_control_custom_parameter" {
          for_each = controls.value.custom_parameters
          iterator = control

          content {
            security_control_id = control.value.security_control_id

            dynamic "parameter" {
              for_each = control.value.parameters
              iterator = param

              content {
                name       = param.value.name
                value_type = param.value.value_type

                dynamic "bool" {
                  for_each = param.value.bool != null ? [param.value.bool] : []
                  iterator = v
                  content {
                    value = v.value
                  }
                }

                dynamic "double" {
                  for_each = param.value.double != null ? [param.value.double] : []
                  iterator = v
                  content {
                    value = v.value
                  }
                }

                dynamic "enum" {
                  for_each = param.value.enum != null ? [param.value.enum] : []
                  iterator = v
                  content {
                    value = v.value
                  }
                }

                dynamic "enum_list" {
                  for_each = param.value.enum_list != null ? [param.value.enum_list] : []
                  iterator = v
                  content {
                    value = v.value
                  }
                }

                dynamic "int" {
                  for_each = param.value.int != null ? [param.value.int] : []
                  iterator = v
                  content {
                    value = v.value
                  }
                }

                dynamic "int_list" {
                  for_each = param.value.int_list != null ? [param.value.int_list] : []
                  iterator = v
                  content {
                    value = v.value
                  }
                }

                dynamic "string" {
                  for_each = param.value.string != null ? [param.value.string] : []
                  iterator = v
                  content {
                    value = v.value
                  }
                }

                dynamic "string_list" {
                  for_each = param.value.string_list != null ? [param.value.string_list] : []
                  iterator = v
                  content {
                    value = v.value
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  depends_on = [aws_securityhub_organization_configuration.this]
}

resource "aws_securityhub_configuration_policy_association" "this" {
  for_each = local.associations

  target_id = each.value.target_id
  policy_id = each.value.policy == local.self_managed ? local.self_managed : aws_securityhub_configuration_policy.this[each.value.policy].id

  depends_on = [aws_securityhub_organization_configuration.this]
}

resource "aws_securityhub_product_subscription" "this" {
  for_each = var.hub.enabled ? toset(var.product_subscriptions) : toset([])

  product_arn = each.value

  depends_on = [aws_securityhub_account.this]
}
