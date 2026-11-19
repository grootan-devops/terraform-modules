module "naming" {
  source = "../../../core/naming"

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags
  names = {
    replication_group = { max_length = 40 }
    subnet_group      = { max_length = 255 }
    parameter_group   = { suffix = local.family, max_length = 255 }
  }
}

module "encryption" {
  source = "../../../core/encryption"

  purpose = "valkey"

  application        = var.application
  environment        = var.environment
  name               = var.name
  tags               = var.tags
  kms                = var.kms
  service_statements = local.kms_service_statements
}

module "log_group" {
  source   = "../../../observability/log-group"
  for_each = local.log_group_names

  application                 = var.application
  environment                 = var.environment
  name                        = var.name
  tags                        = var.tags
  log_group_name              = each.value
  retention_in_days           = var.cloudwatch_logs.retention_in_days
  log_group_class             = var.cloudwatch_logs.log_group_class
  deletion_protection_enabled = var.cloudwatch_logs.deletion_protection_enabled
  kms_key_arn                 = try(coalesce(var.cloudwatch_logs.kms_key_arn, local.kms_key_arn), null)
}

module "security_group" {
  source = "../../../network/security-group"
  count  = var.security_group.create ? 1 : 0

  application   = var.application
  environment   = var.environment
  name          = var.name
  purpose       = "valkey"
  tags          = var.tags
  vpc_id        = var.vpc_id
  description   = "${module.naming.name} Valkey"
  ingress_rules = local.ingress_rules
}

resource "aws_elasticache_subnet_group" "this" {
  name        = module.naming.names.subnet_group
  description = "${module.naming.name} Valkey subnets"
  subnet_ids  = var.subnet_ids

  tags = merge(module.naming.tags, { Name = module.naming.names.subnet_group })
}

resource "aws_elasticache_parameter_group" "this" {
  name        = module.naming.names.parameter_group
  family      = local.family
  description = "${module.naming.name} Valkey parameters"

  dynamic "parameter" {
    for_each = var.parameters
    content {
      name  = parameter.key
      value = parameter.value
    }
  }

  tags = merge(module.naming.tags, { Name = module.naming.names.parameter_group })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id       = local.replication_group_id
  description                = "${module.naming.name} Valkey"
  engine                     = "valkey"
  engine_version             = var.engine_version
  node_type                  = var.node_type
  num_cache_clusters         = var.num_cache_clusters
  port                       = var.port
  parameter_group_name       = aws_elasticache_parameter_group.this.name
  subnet_group_name          = aws_elasticache_subnet_group.this.name
  security_group_ids         = local.security_group_ids
  network_type               = "ipv4"
  ip_discovery               = "ipv4"
  automatic_failover_enabled = local.multi_az
  multi_az_enabled           = local.multi_az
  at_rest_encryption_enabled = true
  kms_key_id                 = local.kms_key_arn
  transit_encryption_enabled = true
  transit_encryption_mode    = "required"
  user_group_ids             = var.user_group_id == null ? null : [var.user_group_id]
  auth_token_wo              = var.auth_token_wo
  auth_token_wo_version      = var.auth_token_wo_version
  auth_token_update_strategy = var.auth_token_update_strategy
  snapshot_retention_limit   = var.snapshot_retention_limit
  snapshot_window            = var.snapshot_window
  final_snapshot_identifier  = "${local.replication_group_id}-final"
  maintenance_window         = "sun:03:00-sun:06:00"
  auto_minor_version_upgrade = true
  apply_immediately          = true

  dynamic "log_delivery_configuration" {
    for_each = local.log_types
    content {
      destination      = module.log_group[log_delivery_configuration.key].name
      destination_type = "cloudwatch-logs"
      log_format       = var.cloudwatch_logs.log_format
      log_type         = log_delivery_configuration.key
    }
  }

  tags = merge(module.naming.tags, { Name = local.replication_group_id })
}
