module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags
  region      = var.region
  names = {
    alias = { suffix = var.purpose, max_length = 250 }
  }
}

module "policy" {
  source = "../../core/policy-document"

  default_resources = ["*"]
  statements        = concat([local.root_statement], var.policy_statements)
}

resource "aws_kms_key" "this" {
  region                             = var.region
  description                        = local.description
  key_usage                          = var.key_usage
  customer_master_key_spec           = var.key_spec
  deletion_window_in_days            = var.deletion_window_in_days
  enable_key_rotation                = local.rotates
  rotation_period_in_days            = local.rotates ? var.rotation_period_in_days : null
  multi_region                       = var.multi_region
  policy                             = module.policy.json
  bypass_policy_lockout_safety_check = false

  tags = module.naming.tags
}

resource "aws_kms_alias" "this" {
  for_each = toset(concat([local.alias], [for a in var.additional_aliases : "alias/${a}"]))

  region        = var.region
  name          = each.key
  target_key_id = aws_kms_key.this.key_id
}
