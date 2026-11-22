output "arn" {
  description = "State machine ARN."
  value       = aws_sfn_state_machine.this.arn
}

output "name" {
  description = "State machine name."
  value       = aws_sfn_state_machine.this.name
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

output "kms_key_arn" {
  description = "Key ARN in use; null for the AWS owned key."
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
