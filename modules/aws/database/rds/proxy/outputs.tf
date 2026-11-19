output "id" {
  description = "Proxy ID."
  value       = aws_db_proxy.this.id
}

output "arn" {
  description = "Proxy ARN."
  value       = aws_db_proxy.this.arn
}

output "name" {
  description = "Proxy name (ProxyName dimension)."
  value       = aws_db_proxy.this.name
}

output "endpoint" {
  description = "Default endpoint."
  value       = aws_db_proxy.this.endpoint
}

output "port" {
  description = "Port the proxy listens on."
  value       = local.engine_port
}

output "resource_id" {
  description = "Proxy resource ID (prx-...)."
  value       = element(split(":", aws_db_proxy.this.arn), 6)
}

output "db_user_arn_prefix" {
  description = "rds-db:connect ARN prefix, without the user name."
  value       = "arn:${module.naming.partition}:rds-db:${module.naming.region}:${module.naming.account_id}:dbuser:${element(split(":", aws_db_proxy.this.arn), 6)}"
}

output "endpoints" {
  description = "Extra endpoint hostnames by key."
  value       = { for k, e in aws_db_proxy_endpoint.this : k => e.endpoint }
}

output "security_group_id" {
  description = "Module security group ID; null when not created."
  value       = try(module.security_group[0].id, null)
}

output "role_arn" {
  description = "Proxy role ARN."
  value       = local.role_arn
}

output "role_name" {
  description = "Proxy role name; null for a role brought by the caller."
  value       = try(module.role[0].name, null)
}

output "log_group_name" {
  description = "Log group name; null when not created."
  value       = try(module.log_group[0].name, null)
}

output "alarm_arns" {
  description = "Alarm ARN by key."
  value       = try(module.alarms[0].alarm_arns, {})
}

output "alarm_names" {
  description = "Alarm name by key."
  value       = try(module.alarms[0].alarm_names, {})
}
