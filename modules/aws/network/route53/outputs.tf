output "zone_id" {
  description = "Hosted zone ID."
  value       = aws_route53_zone.this.zone_id
}

output "name" {
  description = "Zone name."
  value       = aws_route53_zone.this.name
}

output "arn" {
  description = "Hosted zone ARN."
  value       = aws_route53_zone.this.arn
}

output "name_servers" {
  description = "Name servers to delegate to."
  value       = aws_route53_zone.this.name_servers
}

output "record_fqdns" {
  description = "Record FQDNs by key."
  value       = { for k, r in aws_route53_record.this : k => r.fqdn }
}

output "health_check_ids" {
  description = "Health check IDs by key."
  value       = { for k, h in aws_route53_health_check.this : k => h.id }
}

output "ds_record" {
  description = "DS record for the parent zone; null without DNSSEC."
  value       = one(aws_route53_key_signing_key.this[*].ds_record)
}

output "log_group_name" {
  description = "Query log group name; null without query logging."
  value       = one(module.log_group[*].name)
}

output "log_group_arn" {
  description = "Query log group ARN; null without query logging."
  value       = one(module.log_group[*].arn)
}

output "kms_key_arn" {
  description = "Query log key ARN; null for service encryption."
  value       = local.kms_key_arn
}
