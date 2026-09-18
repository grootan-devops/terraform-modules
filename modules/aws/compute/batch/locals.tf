locals {
  rendered_name = var.name != null && var.name != "" ? "${var.application}-${var.environment}-${var.name}" : "${var.application}-${var.environment}"

  tags = merge(
    {
      Application = var.application
      Environment = var.environment
      Name        = local.rendered_name
    },
    var.tags
  )

  job_definitions_processed = {
    for k, v in var.job_definitions : k => merge(v, {
      container_properties = jsonencode(merge(
        {
          executionRoleArn = aws_iam_role.ecs_execution_role.arn
          jobRoleArn       = aws_iam_role.ecs_job_role.arn
        },
        var.cloudwatch_logs != null ? {
          logConfiguration = {
            logDriver = "awslogs"
            options = {
              "awslogs-group"         = aws_cloudwatch_log_group.this[0].name
              "awslogs-region"        = data.aws_region.current.name
              "awslogs-stream-prefix" = k
            }
          }
        } : {},
        v.container_properties != null ? jsondecode(v.container_properties) : {}
      ))
    })
  }
}
