locals {
  enabled_postgresql_exports = toset([
    for log in var.cloudwatch_logs.exports : log
  ])

  cloudwatch_log_retention_by_type = tomap(var.cloudwatch_logs.retention_in_days)
}

resource "aws_cloudwatch_log_group" "this" {
  for_each = local.enabled_postgresql_exports

  name                        = "/aws/rds/instance/${local.rendered_name}/${each.key}"
  retention_in_days           = local.cloudwatch_log_retention_by_type[each.key]
  kms_key_id                  = var.cloudwatch_logs.kms_key_arn
  log_group_class             = "STANDARD"
  deletion_protection_enabled = var.cloudwatch_logs.deletion_protection_enabled

  tags = merge(local.tags, { Name = "/aws/rds/instance/${local.rendered_name}/${each.key}" })
}

resource "aws_cloudwatch_log_metric_filter" "postgresql_error_warning_fatal_panic" {
  count = contains(local.enabled_postgresql_exports, "postgresql") ? 1 : 0

  name                      = "${local.rendered_name}-error-warning-fatal-panic"
  pattern                   = "?PANIC ?FATAL ?ERROR ?WARNING"
  log_group_name            = aws_cloudwatch_log_group.this["postgresql"].name
  apply_on_transformed_logs = false

  metric_transformation {
    name          = "PostgreSQLErrorWarningFatalPanicCount"
    namespace     = "Custom/RDSPostgreSQLLogs/${local.rendered_name}"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_log_metric_filter" "postgresql_auth_failure" {
  count = (contains(local.enabled_postgresql_exports, "iam-db-auth-error") || contains(local.enabled_postgresql_exports, "postgresql")) ? 1 : 0

  name                      = "${local.rendered_name}-auth-failures"
  pattern                   = "\"?authentication failed\" ?\"password authentication failed\""
  log_group_name            = contains(local.enabled_postgresql_exports, "iam-db-auth-error") ? aws_cloudwatch_log_group.this["iam-db-auth-error"].name : aws_cloudwatch_log_group.this["postgresql"].name
  apply_on_transformed_logs = false

  metric_transformation {
    name          = "PostgreSQLAuthFailures"
    namespace     = "Custom/RDSPostgreSQLLogs/${local.rendered_name}"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_query_definition" "recent_errors" {
  count = contains(local.enabled_postgresql_exports, "postgresql") ? 1 : 0

  name            = "RDS/${local.rendered_name}/RecentErrors"
  log_group_names = [aws_cloudwatch_log_group.this["postgresql"].name]
  query_string    = <<EOF
fields @timestamp, @message
| filter @message like /ERROR:|FATAL:|PANIC:/
| sort @timestamp desc
| limit 200
EOF
}

resource "aws_cloudwatch_query_definition" "slow_queries" {
  count = contains(local.enabled_postgresql_exports, "postgresql") ? 1 : 0

  name            = "RDS/${local.rendered_name}/SlowQueries"
  log_group_names = [aws_cloudwatch_log_group.this["postgresql"].name]
  query_string    = <<EOF
fields @timestamp, @message
| filter @message like /duration:/
| parse @message "* duration: * ms  *" as timestamp, duration, query
| sort duration desc
| limit 100
EOF
}
