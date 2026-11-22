resource "aws_organizations_aws_service_access" "this" {
  count = var.organization_admin.enabled && var.organization_admin.manage_trusted_access ? 1 : 0

  service_principal = "backup.amazonaws.com"
}

resource "aws_organizations_delegated_administrator" "this" {
  count = var.organization_admin.enabled ? 1 : 0

  account_id        = var.organization_admin.account_id
  service_principal = "backup.amazonaws.com"

  depends_on = [aws_organizations_aws_service_access.this]

  lifecycle {
    precondition {
      condition     = var.organization_admin.account_id != local.account_id
      error_message = "organization_admin.account_id: a member account."
    }
  }
}

resource "aws_backup_global_settings" "this" {
  count = var.organization_admin.enabled && var.organization_admin.global_settings.enabled ? 1 : 0

  global_settings = local.global_settings

  depends_on = [aws_organizations_aws_service_access.this]
}
