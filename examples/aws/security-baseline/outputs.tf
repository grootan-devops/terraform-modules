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
