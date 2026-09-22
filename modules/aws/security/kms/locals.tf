locals {
  rendered_name             = var.name != null && var.name != "" ? "${var.application}-${var.environment}-${var.name}" : "${var.application}-${var.environment}"
  rendered_description_name = var.name != null ? "${var.application} ${var.name}" : var.application

  tags = merge(
    {
      Application = var.application
      Environment = var.environment
      Name        = local.rendered_name
    },
    var.tags
  )
}
