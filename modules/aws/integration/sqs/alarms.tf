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

  sqs_queues = {
    queue = {
      queue_name = aws_sqs_queue.this.name
      dlq_name   = var.dead_letter_queue.enabled ? aws_sqs_queue.dlq[0].name : null
      alarms     = var.alarms.overrides
    }
  }
}
