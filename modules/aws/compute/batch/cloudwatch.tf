resource "aws_cloudwatch_log_group" "this" {
  count = var.cloudwatch_logs != null ? 1 : 0

  name                        = "/aws/batch/${local.rendered_name}"
  retention_in_days           = var.cloudwatch_logs.retention_in_days
  kms_key_id                  = coalesce(var.cloudwatch_logs.kms_key_arn, var.kms_key_arn)
  log_group_class             = "STANDARD"
  deletion_protection_enabled = var.cloudwatch_logs.deletion_protection_enabled

  tags = merge(local.tags, { Name = "/aws/batch/${local.rendered_name}" })
}
