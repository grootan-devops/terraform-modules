output "url" {
  description = "Site URL."
  value       = "https://${var.domain_name}"
}

output "alb_name" {
  description = "Load balancer name."
  value       = module.alb.name
}

output "log_bucket" {
  description = "Log bucket name."
  value       = module.logs.name
}

output "db_security_group_id" {
  description = "Database security group."
  value       = module.db.security_group_id
}

output "endpoint_service_name" {
  description = "PrivateLink endpoint service name."
  value       = module.private_link.endpoint_service_name
}

output "nlb_name" {
  description = "Network Load Balancer name."
  value       = module.private_link.name
}
