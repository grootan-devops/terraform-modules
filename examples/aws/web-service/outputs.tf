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

output "waf_log_bucket" {
  description = "WAF log bucket name."
  value       = module.waf_logs.name
}

output "web_acl_name" {
  description = "Regional web ACL name."
  value       = module.waf.name
}

output "db_security_group_id" {
  description = "Database security group."
  value       = module.db.security_group_id
}

output "db_proxy_endpoint" {
  description = "RDS Proxy endpoint."
  value       = module.proxy.endpoint
}

output "cache_endpoint" {
  description = "Valkey primary endpoint."
  value       = module.cache.primary_endpoint_address
}

output "cache_token_secret_name" {
  description = "Cache AUTH token secret name."
  value       = module.cache_token.name
}

output "kms_key_alias" {
  description = "Shared data key alias."
  value       = module.key.alias_name
}

output "audit_log_group" {
  description = "Application audit log group."
  value       = module.audit_logs.name
}

output "file_system_name" {
  description = "Shared file system name."
  value       = module.shared.name
}

output "report_job_queues" {
  description = "Report job queue names."
  value       = module.reports.job_queue_names
}

output "endpoint_service_name" {
  description = "PrivateLink endpoint service name."
  value       = module.private_link.endpoint_service_name
}

output "nlb_name" {
  description = "Network Load Balancer name."
  value       = module.private_link.name
}

output "db_proxy_user_arn" {
  description = "IAM resource for rds-db:connect through the proxy."
  value       = local.proxy_db_user_arn
}
