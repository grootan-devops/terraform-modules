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

  nat_gateways = {
    for k in local.nat_keys : local.azs[tonumber(k)] => {
      nat_gateway_id = aws_nat_gateway.this[k].id
      alarms         = var.alarms.overrides
    }
  }
}
