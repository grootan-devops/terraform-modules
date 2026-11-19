module "log_group" {
  source = "../../observability/log-group"
  count  = local.flow_logs_to_cloudwatch ? 1 : 0

  application                 = var.application
  environment                 = var.environment
  name                        = var.name
  tags                        = var.tags
  log_group_name              = local.log_group_name
  retention_in_days           = var.cloudwatch_logs.retention_in_days
  log_group_class             = var.cloudwatch_logs.log_group_class
  deletion_protection_enabled = var.cloudwatch_logs.deletion_protection_enabled
  kms_key_arn                 = try(coalesce(var.cloudwatch_logs.kms_key_arn, local.kms_key_arn), null)
}

module "role" {
  source = "../../security/iam-role"
  count  = local.flow_logs_to_cloudwatch && var.iam_role.create ? 1 : 0

  application              = var.application
  environment              = var.environment
  name                     = var.name
  purpose                  = "flow-logs"
  tags                     = var.tags
  role_name                = var.iam_role.name
  path                     = var.iam_role.path
  permissions_boundary_arn = var.iam_role.permissions_boundary_arn
  managed_policy_arns      = var.iam_role.managed_policy_arns
  policy_statements        = var.iam_role.policy_statements
  policy_documents         = [jsonencode({ Version = "2012-10-17", Statement = local.flow_log_statements })]
  trust = {
    services = ["vpc-flow-logs.${module.naming.dns_suffix}"]
    conditions = [
      { test = "StringEquals", variable = "aws:SourceAccount", values = [module.naming.account_id] },
      { test = "ArnLike", variable = "aws:SourceArn", values = ["arn:${module.naming.partition}:ec2:${module.naming.region}:${module.naming.account_id}:vpc-flow-log/*"] }
    ]
  }
}

resource "aws_flow_log" "this" {
  count = var.flow_logs.enabled ? 1 : 0

  vpc_id                   = aws_vpc.this.id
  traffic_type             = var.flow_logs.traffic_type
  max_aggregation_interval = var.flow_logs.max_aggregation_interval
  log_destination_type     = local.flow_logs_to_cloudwatch ? "cloud-watch-logs" : "s3"
  log_destination          = local.flow_logs_to_cloudwatch ? one(module.log_group[*].arn) : var.flow_logs.s3_bucket_arn
  iam_role_arn             = local.flow_logs_to_cloudwatch ? local.flow_log_role_arn : null

  tags = module.naming.tags
}
