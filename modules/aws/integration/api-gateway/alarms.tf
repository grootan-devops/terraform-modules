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

  api_gateways = {
    api = {
      api_name = aws_api_gateway_rest_api.this.name
      stage    = aws_api_gateway_stage.this.stage_name
      alarms   = var.alarms.overrides
    }
  }
}
