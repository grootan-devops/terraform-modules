resource "aws_sfn_state_machine" "this" {
  name       = local.rendered_name
  role_arn   = aws_iam_role.this.arn
  type       = var.type
  definition = var.definition

  encryption_configuration {
    type       = "CUSTOMER_MANAGED_KMS_KEY"
    kms_key_id = var.kms_key_arn
  }

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.this.arn}:*"
    include_execution_data = true
    level                  = var.cloudwatch_logs.level
  }

  tracing_configuration {
    enabled = var.tracing_enabled
  }

  tags = local.tags
}
