output "key_arn" {
  description = "Key ARN in use; null for the AWS managed key."
  value       = local.key_arn
}

output "created" {
  description = "Whether the module created the key."
  value       = var.kms.create
}
