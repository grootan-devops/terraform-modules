locals {
  flow_logs_enabled   = lookup(var.cloudwatch_logs, "enabled", true)
  flow_logs_exports   = lookup(var.cloudwatch_logs, "exports", ["vpc_flow"])
  flow_logs_retention = lookup(var.cloudwatch_logs, "retention_in_days", { vpc_flow = 90 })
  flow_logs_kms_key   = lookup(var.cloudwatch_logs, "kms_key_arn", null)

  create_vpc_flow_log = local.flow_logs_enabled && contains(local.flow_logs_exports, "vpc_flow")
}

resource "aws_cloudwatch_log_group" "flow_log" {
  count = local.create_vpc_flow_log ? 1 : 0

  name              = "/aws/vpc/${local.rendered_name}/flow-logs"
  retention_in_days = lookup(local.flow_logs_retention, "vpc_flow", 90)
  kms_key_id        = coalesce(local.flow_logs_kms_key, var.kms_key_arn)
  log_group_class   = "STANDARD"

  tags = merge(local.tags, {
    Name = "${local.rendered_name}-vpc-flow-logs"
  })
}

resource "aws_iam_role" "flow_log" {
  count = local.create_vpc_flow_log ? 1 : 0

  name = "${local.rendered_name}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "vpc-flow-logs.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.tags, {
    Name = "${local.rendered_name}-vpc-flow-logs-role"
  })
}

resource "aws_iam_role_policy" "flow_log" {
  count = local.create_vpc_flow_log ? 1 : 0

  name = "${local.rendered_name}-vpc-flow-logs-policy"
  role = aws_iam_role.flow_log[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
        ]
        Effect   = "Allow"
        Resource = "${aws_cloudwatch_log_group.flow_log[0].arn}:*"
      }
    ]
  })
}

resource "aws_flow_log" "this" {
  count = local.create_vpc_flow_log ? 1 : 0

  iam_role_arn    = aws_iam_role.flow_log[0].arn
  log_destination = aws_cloudwatch_log_group.flow_log[0].arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${local.rendered_name}-vpc-flow-logs"
  })
}
