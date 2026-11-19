output "kms_key_arns" {
  description = "Key ARN by Region; null for AWS managed encryption."
  value       = local.kms_key_arns
}

output "automation_log_group_names" {
  description = "Automation log group name by Region."
  value       = { for region, group in module.automation_log_group : region => group.name }
}

output "automation_log_group_arns" {
  description = "Automation log group ARN by Region."
  value       = { for region, group in module.automation_log_group : region => group.arn }
}

output "session_log_group_names" {
  description = "Session log group name by Region."
  value       = { for region, group in module.session_log_group : region => group.name }
}

output "session_log_group_arns" {
  description = "Session log group ARN by Region."
  value       = { for region, group in module.session_log_group : region => group.arn }
}

output "session_document_arns" {
  description = "Session preferences document ARN by Region."
  value       = { for region, document in aws_ssm_document.session_manager : region => document.arn }
}

output "session_kms_iam_policy_json" {
  description = "IAM policy managed nodes need for sessions; null when disabled."
  value       = local.session_enabled ? local.session_policy_json : null
}

output "default_host_management_role_arn" {
  description = "Default Host Management role ARN."
  value       = try(module.dhmc_role[0].arn, null)
}

output "default_host_management_role_name" {
  description = "Default Host Management role name."
  value       = try(module.dhmc_role[0].name, null)
}

output "patch_policy_manager_arn" {
  description = "Patch policy configuration manager ARN."
  value       = try(aws_ssmquicksetup_configuration_manager.patch_policy[0].manager_arn, null)
}

output "patch_policy_administration_role_arn" {
  description = "Patch policy local administration role ARN."
  value       = try(module.patch_administration_role[0].arn, null)
}

output "patch_policy_execution_role_arn" {
  description = "Patch policy local execution role ARN."
  value       = try(module.patch_execution_role[0].arn, null)
}

output "patch_baseline_ids" {
  description = "Custom patch baseline ID by key."
  value       = { for key, baseline in aws_ssm_patch_baseline.this : key => baseline.id }
}

output "association_ids" {
  description = "Inventory and agent update association IDs by Region."
  value = {
    for region in local.regions : region => merge(
      contains(keys(aws_ssm_association.inventory), region) ? { inventory = aws_ssm_association.inventory[region].association_id } : {},
      contains(keys(aws_ssm_association.agent_update), region) ? { agent_update = aws_ssm_association.agent_update[region].association_id } : {},
    )
  }
}

output "resource_data_sync_name" {
  description = "Resource data sync name; null when disabled."
  value       = local.sync_enabled ? module.naming.names.sync : null
}

output "inventory_bucket_name" {
  description = "Inventory bucket name."
  value       = try(module.bucket[0].name, null)
}

output "inventory_bucket_arn" {
  description = "Inventory bucket ARN."
  value       = try(module.bucket[0].arn, null)
}

output "quick_setup_manager_arn" {
  description = "Host management configuration manager ARN."
  value       = try(aws_ssmquicksetup_configuration_manager.host_management[0].manager_arn, null)
}
