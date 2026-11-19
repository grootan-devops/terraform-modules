module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags
  region      = var.region
}

resource "aws_cloudwatch_log_group" "this" {
  region                      = var.region
  name                        = var.log_group_name
  retention_in_days           = var.retention_in_days
  kms_key_id                  = var.kms_key_arn
  log_group_class             = var.log_group_class
  deletion_protection_enabled = var.deletion_protection_enabled

  tags = merge(module.naming.tags, { Name = var.log_group_name })
}
