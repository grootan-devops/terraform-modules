locals {
  rendered_name = var.bucket_name_override != null ? var.bucket_name_override : (
    var.name != null && var.name != "" ? "${var.application}-${var.environment}-${var.name}" : "${var.application}-${var.environment}"
  )

  tags = merge(
    {
      Application = var.application
      Environment = var.environment
      Name        = local.rendered_name
    },
    var.tags
  )
}
