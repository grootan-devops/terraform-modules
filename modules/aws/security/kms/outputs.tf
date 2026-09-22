output "key_arn" {
  description = "The ARN of the KMS key"
  value       = aws_kms_key.this.arn
}

output "key_id" {
  description = "The globally unique identifier for the key"
  value       = aws_kms_key.this.key_id
}

output "replica_key_arn" {
  description = "The ARN of the KMS replica key if created"
  value       = var.replica_key.create && var.multi_region ? aws_kms_replica_key.this[0].arn : null
}
