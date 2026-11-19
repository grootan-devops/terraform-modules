resource "aws_s3_bucket_notification" "this" {
  count = local.notify ? 1 : 0

  bucket      = aws_s3_bucket.this.id
  eventbridge = var.notifications.eventbridge

  dynamic "topic" {
    for_each = var.notifications.topics

    content {
      id            = topic.key
      topic_arn     = topic.value.arn
      events        = topic.value.events
      filter_prefix = topic.value.filter_prefix
      filter_suffix = topic.value.filter_suffix
    }
  }

  dynamic "queue" {
    for_each = var.notifications.queues

    content {
      id            = queue.key
      queue_arn     = queue.value.arn
      events        = queue.value.events
      filter_prefix = queue.value.filter_prefix
      filter_suffix = queue.value.filter_suffix
    }
  }

  dynamic "lambda_function" {
    for_each = var.notifications.functions

    content {
      id                  = lambda_function.key
      lambda_function_arn = lambda_function.value.arn
      events              = lambda_function.value.events
      filter_prefix       = lambda_function.value.filter_prefix
      filter_suffix       = lambda_function.value.filter_suffix
    }
  }
}
