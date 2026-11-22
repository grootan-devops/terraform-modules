module "alarm_routing" {
  source = "../../../modules/aws/observability/alarm-routing"

  environment         = var.environment
  regions             = ["us-east-1"]
  email_subscriptions = { critical = ["oncall@example.com"] }
}

locals {
  edge_alarm_topics = module.alarm_routing.topic_arns["us-east-1"]
}
