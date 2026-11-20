output "instance_arn" {
  description = "Identity Center instance ARN."
  value       = local.instance_arn
}

output "identity_store_id" {
  description = "Identity store ID."
  value       = local.identity_store_id
}

output "permission_set_arns" {
  description = "Permission set ARNs by key."
  value       = { for k, p in aws_ssoadmin_permission_set.this : k => p.arn }
}

output "group_ids" {
  description = "Identity store group IDs by key."
  value       = { for k, g in aws_identitystore_group.this : k => g.group_id }
}
