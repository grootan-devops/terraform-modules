output "id" {
  description = "Queue URL."
  value       = aws_sqs_queue.this.id
}

output "arn" {
  description = "Queue ARN."
  value       = aws_sqs_queue.this.arn
}

output "name" {
  description = "Queue name."
  value       = aws_sqs_queue.this.name
}

output "url" {
  description = "Queue URL."
  value       = aws_sqs_queue.this.url
}

output "dlq_arn" {
  description = "Dead-letter queue ARN; null when disabled."
  value       = try(aws_sqs_queue.dlq[0].arn, null)
}

output "dlq_url" {
  description = "Dead-letter queue URL; null when disabled."
  value       = try(aws_sqs_queue.dlq[0].url, null)
}

output "dlq_name" {
  description = "Dead-letter queue name; null when disabled."
  value       = try(aws_sqs_queue.dlq[0].name, null)
}

output "kms_key_arn" {
  description = "Key ARN in use; null for SSE-SQS."
  value       = local.kms_key_arn
}
