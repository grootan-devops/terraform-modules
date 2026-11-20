module "alarms" {
  source = "../../observability/cloudwatch-alarms"
  count  = var.alarms.enabled ? 1 : 0

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags

  notifications = {
    enabled    = length(var.alarms.topic_arns) > 0
    topic_arns = { (local.log_region) = var.alarms.topic_arns }
  }

  waf_web_acls = {
    acl = {
      web_acl_metric_name = local.metric_name
      scope               = var.scope
      alarms              = var.alarms.overrides
    }
  }
}
