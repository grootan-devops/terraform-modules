output "label_ids" {
  description = "label name -> label id"
  value       = local.label_ids
}

output "team_ids" {
  description = "group name -> team id"
  value       = local.team_ids
}

output "monitor_ids" {
  description = "monitor key -> monitor id"
  value       = module.monitors.monitor_ids
}

output "monitor_group_ids" {
  description = "component -> monitor group id"
  value       = module.monitors.monitor_group_ids
}

output "monitor_group_memberships" {
  description = "monitor key -> id of the monitor group it is in"
  value       = module.monitors.monitor_group_memberships
}

output "incoming_request_secret_keys" {
  description = "Incoming Request monitor key -> heartbeat secret key"
  value       = module.monitors.incoming_request_secret_keys
  sensitive   = true
}

output "incoming_email_secret_keys" {
  description = "Incoming Email monitor key -> inbound email secret key"
  value       = module.monitors.incoming_email_secret_keys
  sensitive   = true
}

output "server_monitor_secret_keys" {
  description = "Server monitor key -> agent secret key"
  value       = module.monitors.server_monitor_secret_keys
  sensitive   = true
}

output "on_call_policy_ids" {
  description = "component -> on-call policy id"
  value       = module.oncall.on_call_policy_ids
}

output "on_call_schedule_ids" {
  description = "component -> on-call schedule id"
  value       = module.oncall.on_call_schedule_ids
}

output "status_page_ids" {
  description = "status page key -> status page id"
  value       = module.status_pages.status_page_ids
}

output "status_page_group_ids" {
  description = "\"<page key>.<group key>\" -> status page group id"
  value       = module.status_pages.status_page_group_ids
}

output "workflow_ids" {
  description = "workflow key -> workflow id"
  value       = module.workflows.workflow_ids
}

output "workflow_graphs" {
  description = "workflow key -> the canvas JSON sent to OneUptime"
  value       = module.workflows.workflow_graphs
}
