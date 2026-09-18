locals {
  rendered_name = (
    var.name != null && var.name != "" ? (
      var.application != "" && var.environment != "" ? "${var.application}-${var.environment}-${var.name}" : var.name
    ) : "${var.application}-${var.environment}"
  )

  tags = merge(
    var.application != "" ? { Application = var.application } : {},
    var.environment != "" ? { Environment = var.environment } : {},
    { Name = local.rendered_name },
    var.tags
  )

  service_discovery_namespace = var.service_discovery_namespace != null ? var.service_discovery_namespace : "${var.application}.${var.environment}.local"
}
