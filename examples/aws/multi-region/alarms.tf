module "alarm_routing" {
  source = "../../../modules/aws/observability/alarm-routing"

  environment         = "prod"
  regions             = ["eu-west-1", "us-east-1"]
  email_subscriptions = { critical = ["oncall@example.com"] }
}
