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

  eventbridge_rules = {
    for k in keys(var.rules) : k => {
      rule_name      = aws_cloudwatch_event_rule.this[k].name
      event_bus_name = aws_cloudwatch_event_rule.this[k].event_bus_name
      alarms         = var.alarms.overrides.rules
    }
  }

  schedule_groups = var.scheduler.enabled ? {
    schedules = {
      schedule_group_name = aws_scheduler_schedule_group.this[0].name
      alarms              = var.alarms.overrides.schedules
    }
  } : {}
}
