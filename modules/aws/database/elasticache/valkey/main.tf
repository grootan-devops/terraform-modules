resource "aws_elasticache_subnet_group" "this" {
  name        = "${local.rendered_name}-sng"
  description = "Subnet group for ElastiCache Valkey ${local.rendered_description_name}"
  subnet_ids  = var.subnet_ids

  tags = merge(local.tags, { Name = "${local.rendered_name}-sng" })
}

resource "aws_elasticache_parameter_group" "this" {
  name        = "${local.rendered_name}-pg"
  family      = var.parameter_group_family
  description = "Parameter group for ElastiCache Valkey ${local.rendered_description_name}"

  dynamic "parameter" {
    for_each = var.parameters
    content {
      name  = parameter.value.name
      value = parameter.value.value
    }
  }

  tags = merge(local.tags, { Name = "${local.rendered_name}-pg" })
}

resource "aws_security_group" "this" {
  name        = "${local.rendered_name}-valkey-sg"
  description = "Security Group for ElastiCache Valkey ${local.rendered_description_name}"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = length(var.allowed_cidr_blocks) > 0 ? [1] : []
    content {
      description = "Allow Valkey inbound from allowed CIDR blocks"
      from_port   = var.port
      to_port     = var.port
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

  tags = merge(local.tags, { Name = "${local.rendered_name}-valkey-sg" })
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id      = local.rendered_name
  description               = "Replication group for ElastiCache Valkey ${local.rendered_description_name}"
  engine                    = "valkey"
  engine_version            = var.engine_version
  node_type                 = var.node_type
  num_cache_clusters        = var.num_cache_clusters
  parameter_group_name      = aws_elasticache_parameter_group.this.name
  subnet_group_name         = aws_elasticache_subnet_group.this.name
  security_group_ids        = [aws_security_group.this.id]
  port                      = var.port
  ip_discovery              = "ipv4"
  final_snapshot_identifier = "final-snapshot-${local.rendered_name}"

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  kms_key_id                 = var.kms_key_id

  maintenance_window = "sun:03:00-sun:06:00"
  apply_immediately  = true

  tags = local.tags
}

