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

output "on_call_policy_ids" {
  description = "component -> on-call policy id"
  value       = module.oncall.on_call_policy_ids
}

output "status_page_ids" {
  description = "status page key -> status page id"
  value       = module.status_pages.status_page_ids
}

output "workflow_ids" {
  description = "workflow key -> workflow id"
  value       = module.workflows.workflow_ids
}

output "workflow_graphs" {
  description = "workflow key -> the canvas JSON sent to OneUptime"
  value       = module.workflows.workflow_graphs
}
