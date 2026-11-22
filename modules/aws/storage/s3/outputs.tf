output "id" {
  description = "Bucket ID."
  value       = aws_s3_bucket.this.id
}

output "arn" {
  description = "Bucket ARN."
  value       = aws_s3_bucket.this.arn
}

output "name" {
  description = "Bucket name."
  value       = aws_s3_bucket.this.bucket
}

output "domain_name" {
  description = "Bucket domain name."
  value       = aws_s3_bucket.this.bucket_domain_name
}

output "regional_domain_name" {
  description = "Regional domain name for CloudFront origins."
  value       = aws_s3_bucket.this.bucket_regional_domain_name
}

output "kms_key_arn" {
  description = "Key ARN in use; null for SSE-S3."
  value       = local.kms_key_arn
}

output "replication_role_arn" {
  description = "Replication role ARN; null without replication."
  value       = var.replication.enabled ? local.role_arn : null
}

output "policy_json" {
  description = "Bucket policy JSON."
  value       = module.policy.json
}

output "alarm_arns" {
  description = "Alarm ARN by key."
  value       = try(module.alarms[0].alarm_arns, {})
}

output "alarm_names" {
  description = "Alarm name by key."
  value       = try(module.alarms[0].alarm_names, {})
}
