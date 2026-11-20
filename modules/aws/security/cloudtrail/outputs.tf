output "arn" {
  description = "Trail ARN."
  value       = try(aws_cloudtrail.this[0].arn, null)
}

output "name" {
  description = "Trail name."
  value       = try(aws_cloudtrail.this[0].name, null)
}

output "bucket_name" {
  description = "Log bucket name."
  value       = var.bucket.enabled ? module.bucket[0].name : local.bucket_name
}

output "bucket_arn" {
  description = "Log bucket ARN."
  value       = var.bucket.enabled ? module.bucket[0].arn : (local.bucket_name == null ? null : local.bucket_arn)
}

output "log_group_name" {
  description = "Log group name."
  value       = try(module.log_group[0].name, null)
}

output "log_group_arn" {
  description = "Log group ARN."
  value       = try(module.log_group[0].arn, null)
}

output "role_arn" {
  description = "Log delivery role ARN."
  value       = local.role_arn
}

output "role_name" {
  description = "Log delivery role name; null for a role brought by the caller."
  value       = try(module.role[0].name, null)
}

output "kms_key_arn" {
  description = "Key ARN in use."
  value       = local.kms_key_arn
}

output "kms_key_policy_json" {
  description = "Key policy statements a caller key needs."
  value       = var.trail.enabled || var.bucket.enabled ? module.kms_policy.json : null
}
