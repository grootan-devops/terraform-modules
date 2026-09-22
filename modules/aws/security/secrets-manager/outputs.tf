output "arn" {
  description = "ARN of the secret."
  value       = aws_secretsmanager_secret.this.arn
}

output "id" {
  description = "ID of the secret."
  value       = aws_secretsmanager_secret.this.id
}

output "name" {
  description = "Name of the secret."
  value       = aws_secretsmanager_secret.this.name
}

output "version_id" {
  description = "Unique identifier of the version of the secret."
  value       = try(aws_secretsmanager_secret_version.this[0].version_id, null)
}

output "policy_id" {
  description = "ID of the secret policy."
  value       = try(aws_secretsmanager_secret_policy.this[0].id, null)
}
