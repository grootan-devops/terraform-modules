resource "aws_security_group" "this" {
  count = length(var.security_group_ids) == 0 ? 1 : 0

  name        = "${local.name_prefix}-efs-sg"
  description = "Security group for EFS mount targets in ${local.name_prefix}"
  vpc_id      = var.vpc_id

  ingress {
    description     = "NFS inbound from allowed security groups or CIDRs"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
    cidr_blocks     = var.allowed_cidr_blocks
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-efs-sg" })
}
