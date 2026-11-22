output "label_ids" {
  description = "Label IDs by name."
  value       = module.oneuptime.label_ids
}

output "team_ids" {
  description = "Team IDs by group."
  value       = module.oneuptime.team_ids
}

output "monitor_ids" {
  description = "Monitor IDs by slug."
  value       = module.oneuptime.monitor_ids
}

output "monitor_group_ids" {
  description = "Monitor group IDs by component."
  value       = module.oneuptime.monitor_group_ids
}

output "monitor_group_memberships" {
  description = "Monitor group ID of each monitor, by slug."
  value       = module.oneuptime.monitor_group_memberships
}

output "incoming_request_secret_keys" {
  description = "Heartbeat secret keys by slug."
  value       = module.oneuptime.incoming_request_secret_keys
  sensitive   = true
}

output "incoming_email_secret_keys" {
  description = "Inbound email secret keys by slug."
  value       = module.oneuptime.incoming_email_secret_keys
  sensitive   = true
}

output "server_monitor_secret_keys" {
  description = "Server agent secret keys by slug."
  value       = module.oneuptime.server_monitor_secret_keys
  sensitive   = true
}

output "on_call_policy_ids" {
  description = "On-call policy IDs by component."
  value       = module.oneuptime.on_call_policy_ids
}

output "on_call_schedule_ids" {
  description = "On-call schedule IDs by component."
  value       = module.oneuptime.on_call_schedule_ids
}

output "status_page_ids" {
  description = "Status page IDs by key."
  value       = module.oneuptime.status_page_ids
}

output "status_page_group_ids" {
  description = "Status page group IDs by page and group key."
  value       = module.oneuptime.status_page_group_ids
}

output "workflow_ids" {
  description = "Workflow IDs by key."
  value       = module.oneuptime.workflow_ids
}
