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
  description = "Load balancer security group ID."
  value       = module.security_group.id
}

output "listener_arns" {
  description = "Listener ARNs by key."
  value       = { for k, l in aws_lb_listener.this : k => l.arn }
}

output "target_group_arns" {
  description = "Target group ARNs by key, once a listener uses them."
  value       = { for k, t in aws_lb_target_group.this : k => t.arn }

  depends_on = [aws_lb_listener.this]
}

output "target_group_arn_suffixes" {
  description = "Target group ARN suffixes by key, for CloudWatch metrics."
  value       = { for k, t in aws_lb_target_group.this : k => t.arn_suffix }
}

output "endpoint_service_name" {
  description = "PrivateLink endpoint service name; null when disabled."
  value       = one(aws_vpc_endpoint_service.this[*].service_name)
}

output "endpoint_service_id" {
  description = "PrivateLink endpoint service ID; null when disabled."
  value       = one(aws_vpc_endpoint_service.this[*].id)
}
