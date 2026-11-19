output "arn" {
  description = "Hub ARN; null when the hub is off."
  value       = try(aws_securityhub_account.this[0].arn, null)
}

output "finding_aggregator_arn" {
  description = "Finding aggregator ARN; null when the hub is off."
  value       = try(aws_securityhub_finding_aggregator.this[0].arn, null)
}

output "configuration_policy_ids" {
  description = "Configuration policy IDs by key."
  value       = { for key, policy in aws_securityhub_configuration_policy.this : key => policy.id }
}
