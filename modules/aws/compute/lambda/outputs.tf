output "arn" {
  description = "Function ARN."
  value       = aws_lambda_function.this.arn
}

output "name" {
  description = "Function name."
  value       = aws_lambda_function.this.function_name
}

output "invoke_arn" {
  description = "Alias invoke ARN for API Gateway."
  value       = aws_lambda_alias.this.invoke_arn
}

output "alias_arn" {
  description = "Alias ARN for triggers."
  value       = aws_lambda_alias.this.arn
}

output "alias_name" {
  description = "Alias name."
  value       = aws_lambda_alias.this.name
}

output "role_arn" {
  description = "Execution role ARN."
  value       = local.role_arn
}

output "role_name" {
  description = "Execution role name; null for a role brought by the caller."
  value       = try(module.role[0].name, null)
}

output "log_group_name" {
  description = "Log group name."
  value       = module.log_group.name
}

output "log_group_arn" {
  description = "Log group ARN."
  value       = module.log_group.arn
}

output "security_group_id" {
  description = "Function security group ID; null outside a VPC."
  value       = try(module.security_group[0].id, null)
}

output "kms_key_arn" {
  description = "Key ARN in use; null for the AWS managed key."
  value       = local.kms_key_arn
}

output "function_url" {
  description = "Function URL; null when disabled."
  value       = try(aws_lambda_function_url.this[0].function_url, null)
}

output "alarm_arns" {
  description = "Alarm ARN by key."
  value       = try(module.alarms[0].alarm_arns, {})
}

output "alarm_names" {
  description = "Alarm name by key."
  value       = try(module.alarms[0].alarm_names, {})
}
