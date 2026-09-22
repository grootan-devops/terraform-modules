output "default_target_group_arn" {
  description = "The ARN of the default target group"
  value       = aws_lb_target_group.default.arn
}

output "extra_target_group_arns" {
  description = "Map of extra route names to target group ARNs"
  value       = { for k, v in aws_lb_target_group.extra : k => v.arn }
}

output "lb_dns" {
  description = "DNS endpoint of load balancer"
  value       = aws_lb.this.dns_name
}

output "security_group_id" {
  description = "Security group ID of the ALB (managed or first external)"
  value       = length(var.security_groups) > 0 ? var.security_groups[0] : aws_security_group.alb[0].id
}

output "lb_arn" {
  description = "The ARN of the load balancer"
  value       = aws_lb.this.arn
}

output "listener_arn" {
  description = "The ARN of the primary load balancer listener"
  value       = var.certificate_arn != null ? aws_lb_listener.https[0].arn : aws_lb_listener.http[0].arn
}
