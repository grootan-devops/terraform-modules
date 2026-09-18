resource "aws_db_parameter_group" "this" {
  name        = "${local.rendered_name}-postgres"
  family      = "postgres${split(".", var.engine_version)[0]}"
  description = "Database parameter group for ${local.rendered_description_name}"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  dynamic "parameter" {
    for_each = [for p in var.parameters : p if p.name != "rds.force_ssl"]
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = lookup(parameter.value, "apply_method", "immediate")
    }
  }

  tags = merge(local.tags, { Name = "${local.rendered_name}-postgres" })
}
