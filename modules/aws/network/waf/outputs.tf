output "web_acl_arn" {
  description = "ARN of the WAFv2 Web ACL."
  value       = aws_wafv2_web_acl.this.arn
}

output "web_acl_id" {
  description = "ID of the WAFv2 Web ACL."
  value       = aws_wafv2_web_acl.this.id
}

output "web_acl_capacity" {
  description = "Web ACL capacity units (WCU) currently used by this Web ACL."
  value       = aws_wafv2_web_acl.this.capacity
}
