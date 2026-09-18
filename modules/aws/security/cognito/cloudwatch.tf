resource "aws_cloudwatch_log_group" "this" {
  count             = var.user_pool_tier != "ESSENTIALS" ? 1 : 0
  name              = "/aws/cognito/${var.application}-${var.environment}-${var.name}"
  retention_in_days = var.cloudwatch_logs.retention_in_days
  kms_key_id        = coalesce(var.cloudwatch_logs.kms_key_arn, var.kms_key_arn)
  log_group_class   = "STANDARD"

  tags = merge(local.tags, { Name = "/aws/cognito/${var.application}-${var.environment}-${var.name}" })
}

resource "aws_cognito_log_delivery_configuration" "this" {
  count        = var.user_pool_tier != "ESSENTIALS" ? 1 : 0
  user_pool_id = aws_cognito_user_pool.this.id

  log_configurations {
    event_source = "userNotification"
    log_level    = var.cloudwatch_logs.log_level

    cloud_watch_logs_configuration {
      log_group_arn = aws_cloudwatch_log_group.this[0].arn
    }
  }

  log_configurations {
    event_source = "userAuthEvents"
    log_level    = var.cloudwatch_logs.log_level

    cloud_watch_logs_configuration {
      log_group_arn = aws_cloudwatch_log_group.this[0].arn
    }
  }
}
