output "trail_bucket" {
  description = "CloudTrail bucket name."
  value       = module.trail.bucket_name
}

output "config_bucket" {
  description = "AWS Config bucket name."
  value       = module.config.bucket_name
}

output "support_role_name" {
  description = "Support role name."
  value       = module.baseline.support_role_name
}

output "budget_names" {
  description = "Budget names by key."
  value       = module.costs.budget_names
}

output "backup_vault_name" {
  description = "Backup vault name."
  value       = module.backup.vault_name
}

output "backup_role_name" {
  description = "Backup service role name."
  value       = module.backup.role_name
}

output "scp_names" {
  description = "Organization policy names by key."
  value       = { for k, p in module.organization.policies : k => p.name }
}
