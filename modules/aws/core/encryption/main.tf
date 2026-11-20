module "naming" {
  source = "../naming"

  application = var.application
  environment = var.environment
  name        = var.name
  region      = var.region
}

module "key" {
  source = "../../security/kms"
  count  = var.kms.create ? 1 : 0

  application             = var.application
  environment             = var.environment
  name                    = coalesce(var.name, var.purpose)
  purpose                 = var.name == null ? null : var.purpose
  tags                    = var.tags
  region                  = var.region
  deletion_window_in_days = var.kms.deletion_window_in_days
  policy_statements       = concat(var.service_statements, var.kms.policy_statements)
}
