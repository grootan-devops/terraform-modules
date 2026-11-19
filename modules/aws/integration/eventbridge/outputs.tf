output "bus_arn" {
  description = "Event bus ARN (the default bus when disabled)."
  value       = local.own_bus_arn
}

output "bus_name" {
  description = "Event bus name."
  value       = var.bus.enabled ? aws_cloudwatch_event_bus.this[0].name : "default"
}

output "rule_arns" {
  description = "Rule ARNs by key."
  value       = { for k, r in aws_cloudwatch_event_rule.this : k => r.arn }
}

output "rule_names" {
  description = "Rule names by key."
  value       = { for k, r in aws_cloudwatch_event_rule.this : k => r.name }
}

output "rule_bus_names" {
  description = "Rule bus names by key (EventBusName dimension)."
  value       = { for k, r in aws_cloudwatch_event_rule.this : k => r.event_bus_name }
}

output "schedule_group_name" {
  description = "Schedule group name; null when the scheduler is off."
  value       = try(aws_scheduler_schedule_group.this[0].name, null)
}

output "schedule_group_arn" {
  description = "Schedule group ARN; null when the scheduler is off."
  value       = try(aws_scheduler_schedule_group.this[0].arn, null)
}

output "schedule_arns" {
  description = "Schedule ARNs by key."
  value       = { for k, s in aws_scheduler_schedule.this : k => s.arn }
}

output "role_arn" {
  description = "Target role ARN; null when no target needs one."
  value       = local.role_arn
}

output "role_name" {
  description = "Target role name; null when not created."
  value       = try(module.role[0].name, null)
}

output "log_group_name" {
  description = "Bus log group name; null when bus logging is off."
  value       = try(module.log_group[0].name, null)
}

output "log_group_arn" {
  description = "Bus log group ARN; null when bus logging is off."
  value       = try(module.log_group[0].arn, null)
}

output "kms_key_arn" {
  description = "Key ARN in use; null for the AWS owned key."
  value       = local.kms_key_arn
}
