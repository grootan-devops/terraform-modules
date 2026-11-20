output "id" {
  description = "Web ACL ID."
  value       = aws_wafv2_web_acl.this.id
}

output "arn" {
  description = "Web ACL ARN."
  value       = aws_wafv2_web_acl.this.arn
}

output "name" {
  description = "Web ACL name."
  value       = aws_wafv2_web_acl.this.name
}

output "metric_name" {
  description = "Web ACL metric name (WebACL dimension)."
  value       = local.metric_name
}

output "rule_metric_names" {
  description = "Rule metric names by rule name (Rule dimension)."
  value       = local.rule_metric_names
}

output "log_group_name" {
  description = "Log group name."
  value       = module.log_group.name
}

output "log_group_arn" {
  description = "Log group ARN."
  value       = module.log_group.arn
}

output "kms_key_arn" {
  description = "Log key ARN; null for service encryption."
  value       = local.kms_key_arn
}
