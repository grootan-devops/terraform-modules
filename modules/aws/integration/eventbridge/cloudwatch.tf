resource "aws_cloudwatch_log_group" "this" {
  count = var.cloudwatch_logs != null ? 1 : 0

  name                        = "/aws/events/${local.rendered_name}"
  retention_in_days           = var.cloudwatch_logs.retention_in_days
  kms_key_id                  = var.cloudwatch_logs.kms_key_arn
  log_group_class             = "STANDARD"
  deletion_protection_enabled = var.cloudwatch_logs.deletion_protection_enabled

  tags = merge(local.tags, { Name = "/aws/events/${local.rendered_name}" })
}

resource "aws_cloudwatch_log_resource_policy" "this" {
  count = var.cloudwatch_logs != null ? 1 : 0

  policy_name     = "${local.rendered_name}-eb-log-policy"
  policy_document = data.aws_iam_policy_document.eventbridge_log_policy[0].json
}

data "aws_iam_policy_document" "eventbridge_log_policy" {
  count = var.cloudwatch_logs != null ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "${aws_cloudwatch_log_group.this[0].arn}:*"
    ]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "delivery.logs.amazonaws.com"]
    }
  }
}
