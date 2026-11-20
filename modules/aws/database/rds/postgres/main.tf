module "naming" {
  source = "../../../core/naming"

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags
  names = {
    instance        = { max_length = 63 }
    subnet_group    = { max_length = 255 }
    parameter_group = { suffix = local.family, max_length = 255 }
  }
}

module "encryption" {
  source = "../../../core/encryption"

  purpose = "rds"

  application        = var.application
  environment        = var.environment
  name               = var.name
  tags               = var.tags
  kms                = var.kms
  service_statements = local.kms_service_statements
}

module "monitoring_role" {
  source = "../../../security/iam-role"
  count  = var.iam_role.create ? 1 : 0

  application              = var.application
  environment              = var.environment
  name                     = var.name
  purpose                  = "monitoring"
  tags                     = var.tags
  role_name                = var.iam_role.name
  path                     = var.iam_role.path
  permissions_boundary_arn = var.iam_role.permissions_boundary_arn
  managed_policy_arns      = concat(["${local.arn_prefix}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"], var.iam_role.managed_policy_arns)
  policy_statements        = var.iam_role.policy_statements
  trust = {
    services = ["monitoring.rds.${module.naming.dns_suffix}"]
    conditions = [
      { test = "StringEquals", variable = "aws:SourceAccount", values = [module.naming.account_id] },
      { test = "ArnLike", variable = "aws:SourceArn", values = [local.db_arn] }
    ]
  }
}

module "security_group" {
  source = "../../../network/security-group"
  count  = var.security_group.create ? 1 : 0

  application   = var.application
  environment   = var.environment
  name          = var.name
  purpose       = "postgres"
  tags          = var.tags
  vpc_id        = var.vpc_id
  description   = "${module.naming.name} PostgreSQL"
  ingress_rules = local.ingress_rules
  egress_rules  = local.egress_rules
}

resource "aws_db_subnet_group" "this" {
  name        = module.naming.names.subnet_group
  description = "${module.naming.name} PostgreSQL subnets"
  subnet_ids  = var.subnet_ids

  tags = merge(module.naming.tags, { Name = module.naming.names.subnet_group })
}

resource "aws_db_parameter_group" "this" {
  name        = module.naming.names.parameter_group
  family      = local.family
  description = "${module.naming.name} PostgreSQL parameters"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "immediate"
  }

  dynamic "parameter" {
    for_each = var.parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(module.naming.tags, { Name = module.naming.names.parameter_group })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "this" {
  identifier                            = local.identifier
  engine                                = "postgres"
  engine_version                        = var.engine_version
  engine_lifecycle_support              = var.extended_support ? "open-source-rds-extended-support" : "open-source-rds-extended-support-disabled"
  instance_class                        = var.instance_class
  allocated_storage                     = var.storage.allocated_storage
  max_allocated_storage                 = var.storage.max_allocated_storage
  storage_type                          = var.storage.type
  iops                                  = var.storage.iops
  storage_throughput                    = var.storage.throughput
  storage_encrypted                     = true
  kms_key_id                            = local.kms_key_arn
  username                              = var.credential.username
  manage_master_user_password           = var.credential.manage_master_user_password ? true : null
  master_user_secret_kms_key_id         = local.secret_kms_key_arn
  password_wo                           = var.password_wo
  password_wo_version                   = var.password_wo_version
  iam_database_authentication_enabled   = true
  db_subnet_group_name                  = aws_db_subnet_group.this.name
  vpc_security_group_ids                = local.security_group_ids
  port                                  = var.port
  multi_az                              = var.multi_az
  publicly_accessible                   = false
  network_type                          = "IPV4"
  parameter_group_name                  = aws_db_parameter_group.this.name
  backup_retention_period               = var.backup_retention_period
  backup_window                         = "00:00-03:00"
  maintenance_window                    = "sun:03:00-sun:06:00"
  copy_tags_to_snapshot                 = true
  delete_automated_backups              = false
  deletion_protection                   = var.deletion_protection
  skip_final_snapshot                   = false
  final_snapshot_identifier             = "${local.identifier}-final-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  auto_minor_version_upgrade            = true
  allow_major_version_upgrade           = var.allow_major_version_upgrade
  apply_immediately                     = var.apply_immediately
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = local.monitoring_role_arn
  database_insights_mode                = "standard"
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = local.kms_key_arn
  performance_insights_retention_period = var.performance_insights_retention_period
  enabled_cloudwatch_logs_exports       = var.cloudwatch_logs.exports

  tags = merge(module.naming.tags, { Name = local.identifier })

  depends_on = [module.log_group, module.monitoring_role]

  lifecycle {
    ignore_changes = [final_snapshot_identifier]
  }
}

resource "aws_db_instance_automated_backups_replication" "this" {
  count = var.backup_replication.enabled ? 1 : 0

  region                 = var.backup_replication.region
  source_db_instance_arn = aws_db_instance.this.arn
  kms_key_id             = var.backup_replication.kms_key_arn
  retention_period       = var.backup_retention_period
}
