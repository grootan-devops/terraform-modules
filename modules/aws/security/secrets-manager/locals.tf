locals {
  rendered_name = var.name_prefix != null ? null : (
    var.name != null && var.name != "" ? (
      startswith(var.name, "${var.application}-${var.environment}") ? var.name : "${var.application}-${var.environment}-${var.name}"
    ) : "${var.application}-${var.environment}"
  )

  governance_tags = {
    Application = var.application
    Environment = var.environment
    Name        = coalesce(local.rendered_name, var.name_prefix, "${var.application}-${var.environment}")
    ManagedBy   = "Terraform"
  }

  tags = merge(var.tags, local.governance_tags)
}
