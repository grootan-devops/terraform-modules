output "id" {
  description = "Replication group ID (ReplicationGroupId dimension)."
  value       = aws_elasticache_replication_group.this.replication_group_id
}

output "arn" {
  description = "Replication group ARN."
  value       = aws_elasticache_replication_group.this.arn
}

output "primary_endpoint_address" {
  description = "Primary endpoint address."
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "reader_endpoint_address" {
  description = "Reader endpoint address."
  value       = aws_elasticache_replication_group.this.reader_endpoint_address
}

output "port" {
  description = "Port."
  value       = aws_elasticache_replication_group.this.port
}

output "member_clusters" {
  description = "Cache cluster IDs (CacheClusterId dimension)."
  value       = aws_elasticache_replication_group.this.member_clusters
}

output "security_group_id" {
  description = "Module security group ID; null when not created."
  value       = try(module.security_group[0].id, null)
}

output "log_group_names" {
  description = "Log group names by log type."
  value       = { for t, g in module.log_group : t => g.name }
}

output "kms_key_arn" {
  description = "Key ARN in use; null for the AWS managed key."
  value       = local.kms_key_arn
}
