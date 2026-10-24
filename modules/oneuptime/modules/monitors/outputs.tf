output "monitor_ids" {
  description = "monitor key (from monitor_configs) -> monitor id"
  value       = { for key, monitor in oneuptime_monitor.this : key => monitor.id }
}

output "monitor_group_ids" {
  description = "component -> monitor group id"
  value       = { for key, group in oneuptime_monitor_group.this : key => group.id }
}

output "monitor_status_ids" {
  description = "monitor status name (operational, degraded, offline) -> monitor status id"
  value = {
    operational = data.oneuptime_monitor_status.operational.id
    degraded    = data.oneuptime_monitor_status.degraded.id
    offline     = data.oneuptime_monitor_status.offline.id
  }
}
