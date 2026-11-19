output "name" {
  description = "Log group name."
  value       = aws_cloudwatch_log_group.this.name
}

output "arn" {
  description = "Log group ARN."
  value       = aws_cloudwatch_log_group.this.arn
}

output "retention_in_days" {
  description = "Retention in days."
  value       = aws_cloudwatch_log_group.this.retention_in_days
}

output "kms_key_arn" {
  description = "Key ARN; null for service encryption."
  value       = aws_cloudwatch_log_group.this.kms_key_id
}
