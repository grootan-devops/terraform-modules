data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${local.rendered_name}-execution-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = local.tags
}

data "aws_iam_policy_document" "this" {
  # Base CloudWatch Logs permissions
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }

  dynamic "statement" {
    for_each = length(var.secret_arns) > 0 ? [1] : []
    content {
      sid       = "ReadSecrets"
      effect    = "Allow"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = var.secret_arns
    }
  }

  dynamic "statement" {
    for_each = length(var.secret_arns) > 0 && var.kms_key_arn != null ? [1] : []
    content {
      sid       = "DecryptSecrets"
      effect    = "Allow"
      actions   = ["kms:Decrypt"]
      resources = [var.kms_key_arn]
    }
  }

  # VPC Permissions
  dynamic "statement" {
    for_each = var.vpc_config != null ? [1] : []
    content {
      sid    = "VPCAccess"
      effect = "Allow"
      actions = [
        "ec2:CreateNetworkInterface",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DeleteNetworkInterface",
        "ec2:AssignPrivateIpAddresses",
        "ec2:UnassignPrivateIpAddresses"
      ]
      resources = ["*"] # ec2:CreateNetworkInterface cannot easily be constrained without specific tag-based conditions
    }
  }

  # Tracing Permissions
  dynamic "statement" {
    for_each = var.tracing_config_mode == "Active" ? [1] : []
    content {
      sid    = "XRayTracing"
      effect = "Allow"
      actions = [
        "xray:PutTraceSegments",
        "xray:PutTelemetryRecords"
      ]
      resources = ["*"]
    }
  }

  # Dead Letter Queue Permissions
  dynamic "statement" {
    for_each = var.dead_letter_config_target_arn != null ? [1] : []
    content {
      sid    = "DeadLetterConfig"
      effect = "Allow"
      actions = [
        "sns:Publish",
        "sqs:SendMessage"
      ]
      resources = [var.dead_letter_config_target_arn]
    }
  }

  # SQS Event Source Mapping Permissions
  dynamic "statement" {
    for_each = length(var.sqs_event_sources) > 0 ? [1] : []
    content {
      sid    = "SQSEventSourceMapping"
      effect = "Allow"
      actions = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ]
      resources = [for sqs in var.sqs_event_sources : sqs.arn]
    }
  }

  # Async Invoke Config Destinations Permissions
  dynamic "statement" {
    for_each = var.async_invoke_config != null ? [1] : []
    content {
      sid    = "AsyncInvokeConfigDestinations"
      effect = "Allow"
      actions = [
        "sns:Publish",
        "sqs:SendMessage",
        "events:PutEvents"
      ]
      resources = compact([
        var.async_invoke_config.on_success_destination_arn,
        var.async_invoke_config.on_failure_destination_arn
      ])
    }
  }
}

resource "aws_iam_policy" "this" {
  name        = "${local.rendered_name}-execution-policy"
  description = "IAM policy for ${local.rendered_name} lambda execution"
  policy      = data.aws_iam_policy_document.this.json
  tags        = local.tags
}

resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.this.arn
}

resource "aws_iam_role_policy_attachment" "custom" {
  for_each = {
    for index, policy_arn in var.custom_iam_policies :
    tostring(index) => policy_arn
  }

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_role_policy_attachment" "application_signals" {
  count      = var.enable_application_signals ? 1 : 0
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLambdaApplicationSignalsExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "lambda_insights" {
  count      = var.enable_lambda_insights ? 1 : 0
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLambdaInsightsExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "xray" {
  count      = var.tracing_config_mode == "Active" ? 1 : 0
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}
