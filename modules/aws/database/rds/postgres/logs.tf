module "log_group" {
  source   = "../../../observability/log-group"
  for_each = local.log_group_names

  application                 = var.application
  environment                 = var.environment
  name                        = var.name
  tags                        = var.tags
  log_group_name              = each.value
  retention_in_days           = var.cloudwatch_logs.retention_in_days
  log_group_class             = var.cloudwatch_logs.log_group_class
  deletion_protection_enabled = var.cloudwatch_logs.deletion_protection_enabled
  kms_key_arn                 = try(coalesce(var.cloudwatch_logs.kms_key_arn, local.kms_key_arn), null)
}

resource "aws_cloudwatch_query_definition" "recent_errors" {
  name            = "RDS/${local.identifier}/RecentErrors"
  log_group_names = [module.log_group["postgresql"].name]
  query_string    = <<-EOT
    fields @timestamp, @message
    | filter @message like /ERROR:|FATAL:|PANIC:/
    | sort @timestamp desc
    | limit 200
  EOT
}

resource "aws_cloudwatch_query_definition" "slow_queries" {
  name            = "RDS/${local.identifier}/SlowQueries"
  log_group_names = [module.log_group["postgresql"].name]
  query_string    = <<-EOT
    fields @timestamp, @message
    | filter @message like /duration:/
    | parse @message "* duration: * ms  *" as timestamp, duration, query
    | sort duration desc
    | limit 100
  EOT
}
