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

  albs = {
    lb = {
      load_balancer_arn_suffix = aws_lb.this.arn_suffix
      target_groups            = { for k, t in aws_lb_target_group.this : k => t.arn_suffix }
      idle_timeout_seconds     = var.idle_timeout
      alarms                   = var.alarms.overrides
    }
  }
}
