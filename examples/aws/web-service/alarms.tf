module "alarm_routing" {
  source = "../../../modules/aws/observability/alarm-routing"

  environment         = var.environment
  email_subscriptions = { critical = ["oncall@example.com"] }
}

locals {
  alarm_topics = module.alarm_routing.topic_arns[var.region]
}
