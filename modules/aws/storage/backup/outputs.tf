output "vault_arns" {
  description = "Vault ARN by Region."
  value       = { for region, vault in aws_backup_vault.this : region => vault.arn }
}

output "vault_name" {
  description = "Vault name; null without a vault."
  value       = var.vault.enabled ? local.vault_name : null
}

output "plan_ids" {
  description = "Backup plan ID by Region."
  value       = { for region, plan in aws_backup_plan.this : region => plan.id }
}

output "plan_arns" {
  description = "Backup plan ARN by Region."
  value       = { for region, plan in aws_backup_plan.this : region => plan.arn }
}

output "selection_ids" {
  description = "Backup selection ID by Region."
  value       = { for region, selection in aws_backup_selection.this : region => selection.id }
}

output "role_arn" {
  description = "Backup service role ARN; null without a vault."
  value       = local.role_arn
}

output "role_name" {
  description = "Backup service role name; null for a role brought by the caller."
  value       = try(module.role[0].name, null)
}

output "framework_arns" {
  description = "Audit framework ARN by Region."
  value       = { for region, framework in aws_backup_framework.this : region => framework.arn }
}

output "report_plan_arns" {
  description = "Report plan ARN by Region."
  value       = { for region, plan in aws_backup_report_plan.this : region => plan.arn }
}

output "kms_key_arns" {
  description = "Vault key ARN by Region; null for the AWS managed key."
  value       = local.kms_key_arns
}

output "kms_key_policy_json" {
  description = "Key policy statements a caller key needs; null without a vault."
  value       = var.vault.enabled ? module.kms_policy.json : null
}

output "report_bucket_policy_json" {
  description = "Report bucket policy statement; null without a report plan."
  value       = var.vault.enabled && var.report_plan.enabled ? local.report_bucket_policy : null
}
