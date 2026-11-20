output "id" {
  description = "REST API ID."
  value       = aws_api_gateway_rest_api.this.id
}

output "arn" {
  description = "REST API ARN."
  value       = aws_api_gateway_rest_api.this.arn
}

output "name" {
  description = "REST API name."
  value       = aws_api_gateway_rest_api.this.name
}

output "execution_arn" {
  description = "Execution ARN for invoke permissions."
  value       = aws_api_gateway_rest_api.this.execution_arn
}

output "invoke_url" {
  description = "Stage invoke URL."
  value       = aws_api_gateway_stage.this.invoke_url
}

output "stage_arn" {
  description = "Stage ARN."
  value       = aws_api_gateway_stage.this.arn
}

output "stage_name" {
  description = "Stage name."
  value       = aws_api_gateway_stage.this.stage_name
}

output "regional_domain_name" {
  description = "Custom domain target for Route 53 aliases; null without a domain."
  value       = try(aws_api_gateway_domain_name.this[0].regional_domain_name, null)
}

output "regional_zone_id" {
  description = "Custom domain hosted zone ID for Route 53 aliases; null without a domain."
  value       = try(aws_api_gateway_domain_name.this[0].regional_zone_id, null)
}

output "log_group_name" {
  description = "Access log group name."
  value       = module.access_log_group.name
}

output "log_group_arn" {
  description = "Access log group ARN."
  value       = module.access_log_group.arn
}

output "kms_key_arn" {
  description = "Log key ARN in use; null for service encryption."
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
