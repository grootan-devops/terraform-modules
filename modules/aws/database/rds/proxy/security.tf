resource "aws_security_group" "this" {
  name        = "${local.rendered_name}-sg"
  description = "Security Group for RDS Proxy ${local.rendered_name}"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = length(var.allowed_cidr_blocks) > 0 ? [1] : []
    content {
      description = "Allow inbound from allowed CIDR blocks"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
    }
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.rendered_name}-sg" })
}

resource "aws_security_group" "endpoint" {
  for_each = var.endpoints

  name        = "${local.rendered_name}-${each.key}-sg"
  description = "Security Group for RDS Proxy Endpoint ${each.key}"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = length(each.value.allowed_cidr_blocks) > 0 ? [1] : []
    content {
      description = "Allow inbound from allowed CIDR blocks"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = each.value.allowed_cidr_blocks
    }
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, each.value.tags, { Name = "${local.rendered_name}-${each.key}-sg" })
}
