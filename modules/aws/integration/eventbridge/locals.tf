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

  target_bus_name = var.bus_name != "" ? var.bus_name : local.rendered_name
  bus_name        = var.create_bus ? aws_cloudwatch_event_bus.this[0].name : "default"
  bus_arn         = var.create_bus ? aws_cloudwatch_event_bus.this[0].arn : "arn:aws:events:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:event-bus/default"
}
