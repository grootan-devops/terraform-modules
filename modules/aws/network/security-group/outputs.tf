output "id" {
  description = "Security group ID."
  value       = aws_security_group.this.id
}

output "arn" {
  description = "Security group ARN."
  value       = aws_security_group.this.arn
}

output "name" {
  description = "Security group name."
  value       = aws_security_group.this.name
}

output "ingress_rule_ids" {
  description = "Ingress rule IDs by key."
  value       = { for k, r in aws_vpc_security_group_ingress_rule.this : k => r.security_group_rule_id }
}

output "egress_rule_ids" {
  description = "Egress rule IDs by key."
  value       = { for k, r in aws_vpc_security_group_egress_rule.this : k => r.security_group_rule_id }
}
