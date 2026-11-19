resource "aws_organizations_aws_service_access" "this" {
  count = var.organization_admin.enabled && var.organization_admin.manage_trusted_access ? 1 : 0

  service_principal = "guardduty.amazonaws.com"
}

resource "aws_guardduty_organization_admin_account" "this" {
  for_each = local.admin_regions

  region           = each.key
  admin_account_id = var.organization_admin.account_id

  depends_on = [aws_organizations_aws_service_access.this]

  lifecycle {
    precondition {
      condition     = var.organization_admin.account_id != local.account_id
      error_message = "organization_admin.account_id: a member account."
    }
  }
}
