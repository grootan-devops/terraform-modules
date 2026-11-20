output "name" {
  description = "Base name."
  value       = local.base
}

output "names" {
  description = "Derived names."
  value       = local.names
}

output "tags" {
  description = "Caller and governance tags."
  value       = local.tags
}

output "governance_tags" {
  description = "Governance tags."
  value       = local.governance_tags
}

output "account_id" {
  description = "Account ID."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "Region."
  value       = local.region
}

output "partition" {
  description = "Partition."
  value       = data.aws_partition.current.partition
}

output "dns_suffix" {
  description = "Partition DNS suffix."
  value       = data.aws_partition.current.dns_suffix
}
