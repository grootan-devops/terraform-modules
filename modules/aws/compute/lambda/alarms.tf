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

  lambda_functions = {
    function = {
      function_name   = aws_lambda_function.this.function_name
      timeout_seconds = var.timeout
      event_source    = length(local.stream_sources) > 0 ? "stream" : length(local.sqs_sources) > 0 ? "queue" : "none"
      alarms          = var.alarms.overrides
    }
  }
}
