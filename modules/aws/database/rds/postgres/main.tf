resource "aws_db_instance" "this" {
  identifier = local.rendered_name

  # Engine
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class
  license_model  = "postgresql-license"

  # Storage
  allocated_storage     = var.storage.allocated_storage
  max_allocated_storage = var.storage.max_allocated_storage
  storage_type          = var.storage.storage_type
  iops                  = var.storage.iops
  storage_throughput    = var.storage.storage_throughput
  dedicated_log_volume  = false

  # Credentials Identity
  username                            = var.credential.username
  password                            = var.credential.password
  iam_database_authentication_enabled = true

  # Network & Security
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  port                   = 5432
  multi_az               = var.multi_az
  availability_zone      = var.multi_az ? null : var.availability_zone
  publicly_accessible    = false
  network_type           = "IPV4" # Defaults to IPv4

  # Encryption
  storage_encrypted = true
  kms_key_id        = var.kms_key_id

  # Backup & Maintenance
  backup_retention_period  = var.backup_retention_period
  backup_window            = "00:00-03:00"
  maintenance_window       = "sun:03:00-sun:06:00"
  copy_tags_to_snapshot    = true
  delete_automated_backups = false
  deletion_protection      = true

  skip_final_snapshot       = false
  final_snapshot_identifier = "final-snapshot-${local.rendered_name}-${formatdate("YYYYMMDDhhmmss", timestamp())}"

  # Upgrades
  auto_minor_version_upgrade  = true
  allow_major_version_upgrade = false
  apply_immediately           = false

  # Monitoring & Logging
  database_insights_mode                = "standard" # Support values: standard, advanced
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = var.monitoring_interval > 0 ? aws_iam_role.enhanced_monitoring[0].arn : null
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = var.kms_key_id
  performance_insights_retention_period = var.performance_insights_retention_period
  enabled_cloudwatch_logs_exports       = var.cloudwatch_logs.exports

  # Advanced
  parameter_group_name = aws_db_parameter_group.this.name

  lifecycle {
    ignore_changes = [
      final_snapshot_identifier,
      password
    ]
  }

  tags = local.tags
}

resource "aws_db_instance_automated_backups_replication" "this" {
  count    = var.enable_automated_backup_replication ? 1 : 0
  provider = aws.replica

  source_db_instance_arn = aws_db_instance.this.arn
  kms_key_id             = var.automated_backup_replication_kms_key_arn
  retention_period       = var.backup_retention_period
}
