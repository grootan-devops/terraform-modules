output "id" {
  description = "Load balancer ID."
  value       = aws_lb.this.id
}

output "arn" {
  description = "Load balancer ARN."
  value       = aws_lb.this.arn
}

output "arn_suffix" {
  description = "ARN suffix for CloudWatch metrics."
  value       = aws_lb.this.arn_suffix
}

output "name" {
  description = "Load balancer name."
  value       = aws_lb.this.name
}

output "dns_name" {
  description = "DNS name."
  value       = aws_lb.this.dns_name
}

output "zone_id" {
  description = "Route 53 zone ID for alias records."
  value       = aws_lb.this.zone_id
}

output "security_group_id" {
  description = "Load balancer security group ID; null when not created."
  value       = one(module.security_group[*].id)
}

output "https_listener_arn" {
  description = "HTTPS listener ARN; null when disabled."
  value       = local.listener_arns.https
}

output "http_listener_arn" {
  description = "HTTP listener ARN; null when disabled."
  value       = local.listener_arns.http
}

output "target_group_arns" {
  description = "Target group ARNs by key."
  value       = { for k, t in aws_lb_target_group.this : k => t.arn }
}

output "target_group_arn_suffixes" {
  description = "Target group ARN suffixes by key, for CloudWatch metrics."
  value       = { for k, t in aws_lb_target_group.this : k => t.arn_suffix }
}
