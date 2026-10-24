output "on_call_policy_ids" {
  description = "component -> on-call policy id"
  value       = { for key, policy in oneuptime_on_call_policy.this : key => policy.id }
}

output "on_call_schedule_ids" {
  description = "component -> on-call schedule id"
  value       = { for key, schedule in oneuptime_on_call_policy_schedule.this : key => schedule.id }
}
