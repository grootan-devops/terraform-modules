output "arn" {
  description = "Key ARN."
  value       = aws_kms_key.this.arn
}

output "id" {
  description = "Key ID."
  value       = aws_kms_key.this.key_id
}

output "alias_name" {
  description = "Alias name."
  value       = aws_kms_alias.this[local.alias].name
}

output "alias_arn" {
  description = "Alias ARN."
  value       = aws_kms_alias.this[local.alias].arn
}

output "replica_arns" {
  description = "Replica ARNs by Region."
  value       = { for region, key in aws_kms_replica_key.this : region => key.arn }
}

output "policy_json" {
  description = "Key policy JSON."
  value       = module.policy.json
}
