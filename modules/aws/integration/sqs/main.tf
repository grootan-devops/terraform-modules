module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags
  names = {
    queue = { max_length = 80 - length(local.suffix) }
    dlq   = { suffix = "dlq", max_length = 80 - length(local.suffix) }
  }
}

module "encryption" {
  source = "../../core/encryption"

  application        = var.application
  environment        = var.environment
  name               = var.name
  purpose            = "sqs"
  tags               = var.tags
  kms                = var.kms
  service_statements = local.kms_service_statements
}

resource "aws_sqs_queue" "this" {
  name                              = local.queue_name
  visibility_timeout_seconds        = var.visibility_timeout_seconds
  message_retention_seconds         = var.message_retention_seconds
  max_message_size                  = var.max_message_size
  delay_seconds                     = var.delay_seconds
  receive_wait_time_seconds         = var.receive_wait_time_seconds
  fifo_queue                        = var.fifo.enabled
  content_based_deduplication       = var.fifo.enabled ? var.fifo.content_based_deduplication : null
  deduplication_scope               = var.fifo.enabled ? (var.fifo.high_throughput ? "messageGroup" : "queue") : null
  fifo_throughput_limit             = var.fifo.enabled ? (var.fifo.high_throughput ? "perMessageGroupId" : "perQueue") : null
  sqs_managed_sse_enabled           = local.sse_sqs ? true : null
  kms_master_key_id                 = local.kms_key_arn
  kms_data_key_reuse_period_seconds = local.sse_sqs ? null : var.kms_data_key_reuse_period_seconds

  tags = merge(module.naming.tags, { Name = local.queue_name })
}

resource "aws_sqs_queue" "dlq" {
  count = var.dead_letter_queue.enabled ? 1 : 0

  name                              = local.dlq_name
  visibility_timeout_seconds        = var.visibility_timeout_seconds
  message_retention_seconds         = var.dead_letter_queue.message_retention_seconds
  max_message_size                  = var.max_message_size
  receive_wait_time_seconds         = var.receive_wait_time_seconds
  fifo_queue                        = var.fifo.enabled
  content_based_deduplication       = var.fifo.enabled ? var.fifo.content_based_deduplication : null
  sqs_managed_sse_enabled           = local.sse_sqs ? true : null
  kms_master_key_id                 = local.kms_key_arn
  kms_data_key_reuse_period_seconds = local.sse_sqs ? null : var.kms_data_key_reuse_period_seconds

  tags = merge(module.naming.tags, { Name = local.dlq_name })
}

resource "aws_sqs_queue_redrive_policy" "this" {
  count = var.dead_letter_queue.enabled ? 1 : 0

  queue_url = aws_sqs_queue.this.id
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[0].arn
    maxReceiveCount     = var.dead_letter_queue.max_receive_count
  })
}

resource "aws_sqs_queue_redrive_allow_policy" "this" {
  count = var.dead_letter_queue.enabled ? 1 : 0

  queue_url = aws_sqs_queue.dlq[0].id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.this.arn]
  })
}

module "policy" {
  source = "../../core/policy-document"

  default_resources = [aws_sqs_queue.this.arn]
  statements        = concat([local.tls_statement], local.publisher_statements, var.policy_statements)
}

resource "aws_sqs_queue_policy" "this" {
  queue_url = aws_sqs_queue.this.id
  policy    = module.policy.json
}

module "dlq_policy" {
  source = "../../core/policy-document"
  count  = var.dead_letter_queue.enabled ? 1 : 0

  default_resources = [aws_sqs_queue.dlq[0].arn]
  statements        = [local.tls_statement]
}

resource "aws_sqs_queue_policy" "dlq" {
  count = var.dead_letter_queue.enabled ? 1 : 0

  queue_url = aws_sqs_queue.dlq[0].id
  policy    = module.dlq_policy[0].json
}
