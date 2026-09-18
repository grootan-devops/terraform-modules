resource "aws_db_subnet_group" "this" {
  name        = "${local.rendered_name}-sng"
  description = "Database subnet group for ${local.rendered_description_name}"
  subnet_ids  = var.subnet_ids

  tags = merge(local.tags, { Name = "${local.rendered_name}-sng" })
}
