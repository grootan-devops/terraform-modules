output "recorder_names" {
  description = "Recorder name by Region."
  value       = { for region, recorder in aws_config_configuration_recorder.this : region => recorder.name }
}

output "service_linked_role_arn" {
  description = "AWSServiceRoleForConfig ARN the recorders use."
  value       = local.service_linked_role_arn
}

output "bucket_name" {
  description = "Delivery bucket name; null without a bucket."
  value       = local.create_bucket ? module.bucket[0].name : var.bucket.name
}

output "bucket_arn" {
  description = "Delivery bucket ARN; null without a bucket."
  value       = local.create_bucket ? module.bucket[0].arn : (var.bucket.name == null ? null : local.bucket_arn)
}

output "kms_key_arn" {
  description = "Key ARN in use; null for SSE-S3."
  value       = local.kms_key_arn
}

output "kms_key_policy_json" {
  description = "Key policy statements a caller key needs."
  value       = module.kms_policy.json
}

output "aggregator_arn" {
  description = "Aggregator ARN; null when disabled."
  value       = try(aws_config_configuration_aggregator.this[0].arn, null)
}

output "aggregator_role_arn" {
  description = "Aggregator role ARN; null when disabled."
  value       = try(module.aggregator_role[0].arn, null)
}

output "organization_rule_arns" {
  description = "Organization rule ARNs by region/rule key."
  value       = { for key, rule in aws_config_organization_managed_rule.this : key => rule.arn }
}

output "account_rule_names" {
  description = "Account rule names by region/rule key."
  value       = { for key, rule in aws_config_config_rule.this : key => rule.name }
}

output "account_rule_arns" {
  description = "Account rule ARNs by region/rule key."
  value       = { for key, rule in aws_config_config_rule.this : key => rule.arn }
}

output "conformance_pack_arns" {
  description = "Conformance pack ARNs by region/pack key."
  value       = { for key, pack in aws_config_organization_conformance_pack.this : key => pack.arn }
}

output "remediation_configuration_arns" {
  description = "Remediation configuration ARNs by key."
  value       = { for key, remediation in aws_config_remediation_configuration.this : key => remediation.arn }
}
