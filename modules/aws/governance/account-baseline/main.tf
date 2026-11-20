module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  tags        = var.tags
}

resource "aws_iam_account_password_policy" "this" {
  count = var.password_policy.enabled ? 1 : 0

  minimum_password_length        = var.password_policy.minimum_password_length
  require_uppercase_characters   = true
  require_lowercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  password_reuse_prevention      = var.password_policy.password_reuse_prevention
  max_password_age               = var.password_policy.max_password_age
  allow_users_to_change_password = var.password_policy.allow_users_to_change_password
  hard_expiry                    = var.password_policy.hard_expiry
}

resource "aws_account_alternate_contact" "this" {
  for_each = local.alternate_contacts

  account_id             = var.alternate_contacts.account_id
  alternate_contact_type = each.key
  name                   = each.value.name
  title                  = each.value.title
  email_address          = each.value.email_address
  phone_number           = each.value.phone_number

  lifecycle {
    precondition {
      condition     = var.alternate_contacts.account_id != local.account_id
      error_message = "alternate_contacts.account_id: omit it for the calling account."
    }
  }
}

resource "aws_s3_account_public_access_block" "this" {
  count = var.s3_account_public_access_block.enabled ? 1 : 0

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

module "support_role" {
  source = "../../security/iam-role"
  count  = var.support_role.enabled ? 1 : 0

  application              = var.application
  environment              = var.environment
  purpose                  = "support"
  tags                     = var.tags
  description              = "AWS Support incident management (IAM.18)."
  max_session_duration     = var.support_role.max_session_duration
  permissions_boundary_arn = var.permissions_boundary_arn
  managed_policy_arns      = ["${local.arn_prefix}:iam::aws:policy/AWSSupportAccess"]
  trust = {
    aws_principals = length(var.support_role.trusted_principal_arns) > 0 ? var.support_role.trusted_principal_arns : ["arn:${module.naming.partition}:iam::${module.naming.account_id}:root"]
    conditions     = local.support_trust_conditions
  }
}
