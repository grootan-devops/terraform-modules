output "arn" {
  description = "Secret ARN."
  value       = aws_secretsmanager_secret.this.arn
}

output "name" {
  description = "Secret name."
  value       = aws_secretsmanager_secret.this.name
}

output "version_id" {
  description = "Version ID of the written value; null without one."
  value       = one(aws_secretsmanager_secret_version.this[*].version_id)
}

output "kms_key_arn" {
  description = "Key ARN in use; null for aws/secretsmanager."
  value       = local.kms_key_arn
}
