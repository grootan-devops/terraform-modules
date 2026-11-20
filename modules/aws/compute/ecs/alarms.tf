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

  ecs_services = {
    for k, s in aws_ecs_service.this : k => {
      cluster_name       = aws_ecs_cluster.this.name
      service_name       = s.name
      container_insights = var.container_insights != "disabled"
      alarms             = var.alarms.overrides
    }
  }
}
