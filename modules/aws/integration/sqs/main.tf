resource "aws_sqs_queue" "this" {
  name                              = local.rendered_name
  visibility_timeout_seconds        = var.visibility_timeout_seconds
  message_retention_seconds         = var.message_retention_seconds
  max_message_size                  = var.max_message_size
  delay_seconds                     = var.delay_seconds
  receive_wait_time_seconds         = var.receive_wait_time_seconds
  redrive_policy                    = var.redrive_policy
  redrive_allow_policy              = var.redrive_allow_policy
  fifo_queue                        = var.fifo_queue
  content_based_deduplication       = var.content_based_deduplication
  kms_master_key_id                 = var.kms_key_arn
  sqs_managed_sse_enabled           = false
  kms_data_key_reuse_period_seconds = var.kms_data_key_reuse_period_seconds
  tags                              = local.tags
}

resource "aws_sqs_queue" "dlq" {
  count = var.create_dlq ? 1 : 0

  name                              = "${local.rendered_name}-dlq"
  visibility_timeout_seconds        = var.visibility_timeout_seconds
  message_retention_seconds         = 1209600 # 14 days
  max_message_size                  = var.max_message_size
  delay_seconds                     = var.delay_seconds
  receive_wait_time_seconds         = var.receive_wait_time_seconds
  fifo_queue                        = var.fifo_queue
  content_based_deduplication       = var.content_based_deduplication
  kms_master_key_id                 = var.kms_key_arn
  sqs_managed_sse_enabled           = false
  kms_data_key_reuse_period_seconds = var.kms_data_key_reuse_period_seconds
  tags                              = merge(local.tags, { Name = "${local.rendered_name}-dlq" })
}

resource "aws_sqs_queue_redrive_policy" "this" {
  count = var.create_dlq ? 1 : 0

  queue_url = aws_sqs_queue.this.id
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[0].arn
    maxReceiveCount     = var.max_receive_count
  })
}

resource "aws_sqs_queue_redrive_allow_policy" "this" {
  count = var.create_dlq ? 1 : 0

  queue_url = aws_sqs_queue.dlq[0].id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.this.arn]
  })
}

data "aws_iam_policy_document" "combined" {
  count = var.policy != null || var.allow_eventbridge ? 1 : 0

  source_policy_documents = var.policy != null ? [var.policy] : []

  dynamic "statement" {
    for_each = var.allow_eventbridge ? [1] : []
    content {
      sid    = "AllowEventBridgePublish"
      effect = "Allow"
      principals {
        type        = "Service"
        identifiers = ["events.amazonaws.com"]
      }
      actions   = ["sqs:SendMessage"]
      resources = [aws_sqs_queue.this.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "this" {
  count     = var.policy != null || var.allow_eventbridge ? 1 : 0
  queue_url = aws_sqs_queue.this.id
  policy    = data.aws_iam_policy_document.combined[0].json
}
