locals {
  suffix      = var.fifo.enabled ? ".fifo" : ""
  queue_name  = "${module.naming.names.queue}${local.suffix}"
  dlq_name    = "${module.naming.names.dlq}${local.suffix}"
  sse_sqs     = !var.kms.create && var.kms.key_id == null
  kms_key_arn = module.encryption.key_arn

  publisher_principals = distinct(concat(
    [for p in values(var.allowed_publishers) : p.principal],
    [for p in values(var.dead_letter_queue.allowed_publishers) : p.principal]
  ))

  kms_service_statements = [for principal in local.publisher_principals : {
    sid        = "Allow${title(split(".", principal)[0])}Publish"
    actions    = ["kms:GenerateDataKey", "kms:Decrypt"]
    principals = { Service = [principal] }
    conditions = [{ test = "StringEquals", variable = "aws:SourceAccount", values = [module.naming.account_id] }]
  }]

  tls_statement = {
    sid        = "DenyInsecureTransport"
    effect     = "Deny"
    actions    = ["sqs:*"]
    principals = { AWS = ["*"] }
    conditions = [{ test = "Bool", variable = "aws:SecureTransport", values = ["false"] }]
  }

  publisher_statements = [for key, p in var.allowed_publishers : {
    sid        = "AllowPublisher${replace(key, "/[^a-zA-Z0-9]/", "")}"
    actions    = ["sqs:SendMessage"]
    principals = { Service = [p.principal] }
    conditions = [{ test = "ArnEquals", variable = "aws:SourceArn", values = [p.source_arn] }]
  }]

  dlq_publisher_statements = [for key, p in var.dead_letter_queue.allowed_publishers : {
    sid        = "AllowDeadLetter${replace(key, "/[^a-zA-Z0-9]/", "")}"
    actions    = ["sqs:SendMessage"]
    principals = { Service = [p.principal] }
    conditions = [{ test = "ArnEquals", variable = "aws:SourceArn", values = [p.source_arn] }]
  }]
}
