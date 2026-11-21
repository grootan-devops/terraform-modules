module "log_group" {
  source = "../../observability/log-group"
  count  = local.logs_to_cloudwatch ? 1 : 0

  application                 = var.application
  environment                 = var.environment
  name                        = var.name
  tags                        = var.tags
  region                      = local.region
  log_group_name              = local.log_group_name
  retention_in_days           = var.cloudwatch_logs.retention_in_days
  log_group_class             = var.cloudwatch_logs.log_group_class
  deletion_protection_enabled = var.cloudwatch_logs.deletion_protection_enabled
  kms_key_arn                 = try(coalesce(var.cloudwatch_logs.kms_key_arn, local.kms_key_arn), null)
}

resource "aws_cloudwatch_log_delivery_source" "this" {
  region       = local.region
  name         = module.naming.names.delivery
  log_type     = "ACCESS_LOGS"
  resource_arn = aws_cloudfront_distribution.this.arn

  tags = merge(module.naming.tags, { Name = module.naming.names.delivery })
}

resource "aws_cloudwatch_log_delivery_destination" "this" {
  region        = local.region
  name          = module.naming.names.delivery
  output_format = "json"

  delivery_destination_configuration {
    destination_resource_arn = local.logs_to_s3 ? "${var.logging.s3_bucket_arn}/${var.logging.prefix}" : one(module.log_group[*].arn)
  }

  tags = merge(module.naming.tags, { Name = module.naming.names.delivery })
}

resource "aws_cloudwatch_log_delivery" "this" {
  region                   = local.region
  delivery_source_name     = aws_cloudwatch_log_delivery_source.this.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.this.arn
  record_fields            = local.record_fields

  s3_delivery_configuration = local.logs_to_s3 ? [{
    suffix_path                 = local.s3_suffix_path
    enable_hive_compatible_path = false
  }] : null

  tags = merge(module.naming.tags, { Name = module.naming.names.delivery })
}
