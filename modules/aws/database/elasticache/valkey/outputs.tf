output "primary_endpoint_address" {
  description = "The DNS endpoint of the primary node in the replication group"
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "reader_endpoint_address" {
  description = "The DNS endpoint of the reader node(s) in the replication group"
  value       = aws_elasticache_replication_group.this.reader_endpoint_address
}

output "configuration_endpoint_address" {
  description = "The configuration endpoint address for cluster mode"
  value       = aws_elasticache_replication_group.this.configuration_endpoint_address
}
