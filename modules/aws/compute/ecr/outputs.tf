output "arn" {
  description = "Repository ARN."
  value       = aws_ecr_repository.this.arn
}

output "name" {
  description = "Repository name."
  value       = aws_ecr_repository.this.name
}

output "repository_url" {
  description = "Repository URL for docker push and pull."
  value       = aws_ecr_repository.this.repository_url
}

output "registry_id" {
  description = "Registry (account) ID."
  value       = aws_ecr_repository.this.registry_id
}

output "kms_key_arn" {
  description = "Key ARN in use; null for AES256."
  value       = local.kms_key_arn
}
