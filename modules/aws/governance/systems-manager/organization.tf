resource "aws_organizations_aws_service_access" "ssm" {
  count = local.organization_admin_enabled && var.organization_admin.manage_trusted_access ? 1 : 0

  service_principal = "ssm.amazonaws.com"
}

resource "aws_organizations_delegated_administrator" "ssm" {
  count = local.organization_admin_enabled ? 1 : 0

  account_id        = var.organization_admin.account_id
  service_principal = "ssm.amazonaws.com"

  depends_on = [aws_organizations_aws_service_access.ssm]

  lifecycle {
    precondition {
      condition     = var.organization_admin.account_id != local.account_id
      error_message = "organization_admin.account_id: a member account, not this one."
    }
  }
}

resource "aws_ssmquicksetup_configuration_manager" "host_management" {
  count = local.quick_setup_enabled ? 1 : 0

  name        = module.naming.names.quick_setup
  description = "Organization-wide Systems Manager host management."

  configuration_definition {
    type       = "AWSQuickSetupType-SSMHostMgmt"
    parameters = local.quick_setup_parameters
  }

  tags = merge(module.naming.tags, { Name = module.naming.names.quick_setup })

  depends_on = [aws_organizations_delegated_administrator.ssm]
}
