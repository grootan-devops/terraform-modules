module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags
}

module "bucket" {
  source = "../s3"

  application                   = var.application
  environment                   = var.environment
  name                          = var.name
  tags                          = var.tags
  bucket_name                   = var.bucket_name
  access_logs                   = var.access_logs
  policy_statements             = local.policy_statements
  noncurrent_version_expiration = local.noncurrent_version_expiration
  lifecycle_rules               = local.lifecycle_rules
}
