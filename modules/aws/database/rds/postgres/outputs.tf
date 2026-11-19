output "id" {
  description = "DB instance identifier (DBInstanceIdentifier dimension)."
  value       = aws_db_instance.this.identifier
}

output "arn" {
  description = "DB instance ARN."
  value       = aws_db_instance.this.arn
}

output "resource_id" {
  description = "DB resource ID for rds-db:connect policies."
  value       = aws_db_instance.this.resource_id
}

output "address" {
  description = "Hostname."
  value       = aws_db_instance.this.address
}

output "endpoint" {
  description = "Endpoint (host:port)."
  value       = aws_db_instance.this.endpoint
}

output "port" {
  description = "Port."
  value       = aws_db_instance.this.port
}

output "security_group_id" {
  description = "Module security group ID; null when not created."
  value       = try(module.security_group[0].id, null)
}

output "master_user_secret_arn" {
  description = "Secrets Manager secret of the master user; null with password_wo."
  value       = try(aws_db_instance.this.master_user_secret[0].secret_arn, null)
}

output "monitoring_role_arn" {
  description = "Enhanced Monitoring role ARN."
  value       = local.monitoring_role_arn
}

output "log_group_names" {
  description = "Log group names by export."
  value       = { for e, g in module.log_group : e => g.name }
}

output "kms_key_arn" {
  description = "Key ARN in use; null for the AWS managed key."
  value       = local.kms_key_arn
}

output "alarm_arns" {
  description = "Alarm ARN by key."
  value       = try(module.alarms[0].alarm_arns, {})
}

output "alarm_names" {
  description = "Alarm name by key."
  value       = try(module.alarms[0].alarm_names, {})
}
