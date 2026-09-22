resource "aws_security_group" "this" {
  name        = "${local.rendered_name}-rds"
  description = "Security Group for RDS instance ${local.rendered_description_name}"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = length(var.allowed_cidr_blocks) > 0 ? [1] : []
    content {
      description = "Allow PostgreSQL inbound from allowed CIDR blocks"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
    }
  }

  egress {
    description = "Allow outbound traffic to designated CIDR blocks"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.egress_cidr_blocks
  }

  tags = merge(local.tags, { Name = "${local.rendered_name}-rds" })
}
