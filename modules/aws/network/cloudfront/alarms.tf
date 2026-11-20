module "alarms" {
  source = "../../observability/cloudwatch-alarms"
  count  = var.alarms.enabled ? 1 : 0

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags

  notifications = {
    enabled    = length(var.alarms.topic_arns) > 0
    topic_arns = { (local.region) = var.alarms.topic_arns }
  }

  cloudfront_distributions = {
    distribution = {
      distribution_id = aws_cloudfront_distribution.this.id
      alarms          = var.alarms.overrides
    }
  }
}
