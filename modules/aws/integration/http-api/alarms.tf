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

  http_apis = {
    api = {
      api_id = aws_apigatewayv2_api.this.id
      stage  = aws_apigatewayv2_stage.this.name
      alarms = var.alarms.overrides
    }
  }
}
