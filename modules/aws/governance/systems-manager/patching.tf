data "aws_ssm_patch_baselines" "default" {
  count = local.patching_enabled ? 1 : 0

  default_baselines = true
}

resource "aws_ssm_patch_baseline" "this" {
  for_each = local.custom_baselines_enabled ? local.patch_baselines : {}

  name                    = each.value.name
  description             = each.value.description
  operating_system        = each.value.operating_system
  rejected_patches        = each.value.rejected_patches
  rejected_patches_action = each.value.rejected_patches_action

  approval_rule {
    approve_after_days  = each.value.approve_after_days
    compliance_level    = each.value.compliance_level
    enable_non_security = each.value.enable_non_security

    dynamic "patch_filter" {
      for_each = each.value.patch_filters

      content {
        key    = patch_filter.key
        values = patch_filter.value
      }
    }
  }

  tags = merge(module.naming.tags, { Name = each.value.name })
}

resource "aws_ssmquicksetup_configuration_manager" "patch_policy" {
  count = local.patching_enabled ? 1 : 0

  name        = module.naming.names.patch_policy
  description = "Systems Manager patch policy."

  configuration_definition {
    type                                     = "AWSQuickSetupType-PatchPolicy"
    local_deployment_administration_role_arn = module.patch_administration_role[0].arn
    local_deployment_execution_role_name     = module.patch_execution_role[0].name
    parameters                               = local.patch_policy_parameters
  }

  tags = merge(module.naming.tags, { Name = module.naming.names.patch_policy })

  depends_on = [
    module.patch_administration_role,
    module.patch_execution_role,
    aws_organizations_delegated_administrator.ssm,
  ]
}
