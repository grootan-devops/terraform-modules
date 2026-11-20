module "alarms" {
  source = "../../observability/cloudwatch-alarms"
  count  = var.alarms.enabled ? 1 : 0

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags

  notifications = {
    enabled    = length(var.alarms.topic_arns) > 0
    topic_arns = { (module.naming.region) = var.alarms.topic_arns }
  }

  efs_file_systems = {
    file-system = {
      file_system_id   = aws_efs_file_system.this.id
      throughput_mode  = var.throughput.mode
      performance_mode = var.performance_mode
      alarms           = var.alarms.overrides
    }
  }
}
