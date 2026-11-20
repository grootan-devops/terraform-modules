module "log_group" {
  source = "../../observability/log-group"
  count  = local.query_logging ? 1 : 0

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

resource "aws_cloudwatch_log_resource_policy" "query_logging" {
  count = local.query_logging ? 1 : 0

  region          = local.region
  policy_name     = module.naming.names.query_log_policy
  policy_document = local.query_log_policy
}

resource "aws_route53_query_log" "this" {
  count = local.query_logging ? 1 : 0

  zone_id                  = aws_route53_zone.this.zone_id
  cloudwatch_log_group_arn = module.log_group[0].arn

  depends_on = [aws_cloudwatch_log_resource_policy.query_logging]
}
