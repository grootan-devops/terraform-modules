module "alarms" {
  source = "../../../observability/cloudwatch-alarms"
  count  = var.alarms.enabled ? 1 : 0

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags

  notifications = {
    enabled    = length(var.alarms.topic_arns) > 0
    topic_arns = { (module.naming.region) = var.alarms.topic_arns }
  }

  rds_instances = {
    instance = {
      db_instance_identifier = aws_db_instance.this.identifier
      allocated_storage_gib  = var.storage.allocated_storage
      alarms                 = var.alarms.overrides
    }
  }
}
