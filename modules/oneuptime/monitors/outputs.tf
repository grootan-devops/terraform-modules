output "monitor_ids" {
  description = "monitor key (from monitor_configs) -> monitor id"
  value       = { for key, monitor in oneuptime_monitor.this : key => monitor.id }
}

output "monitor_group_ids" {
  description = "component -> monitor group id"
  value       = { for key, group in oneuptime_monitor_group.this : key => group.id }
}

output "monitor_group_memberships" {
  description = "monitor key -> id of the monitor group it is in"
  value       = { for key, member in oneuptime_monitor_group_resource.this : key => member.monitor_group_id }
}

output "incoming_request_secret_keys" {
  description = "Incoming Request monitor key -> heartbeat secret key"
  sensitive   = true
  value = {
    for key, monitor in oneuptime_monitor.this : key => monitor.incoming_request_secret_key
    if local.monitor_specs[key].monitor_type == "Incoming Request"
  }
}

output "incoming_email_secret_keys" {
  description = "Incoming Email monitor key -> inbound email secret key"
  sensitive   = true
  value = {
    for key, monitor in oneuptime_monitor.this : key => monitor.incoming_email_secret_key
    if local.monitor_specs[key].monitor_type == "Incoming Email"
  }
}

output "server_monitor_secret_keys" {
  description = "Server monitor key -> agent secret key"
  sensitive   = true
  value = {
    for key, monitor in oneuptime_monitor.this : key => monitor.server_monitor_secret_key
    if local.monitor_specs[key].monitor_type == "Server"
  }
}

output "monitor_status_ids" {
  description = "monitor status name (operational, degraded, offline) -> monitor status id"
  value = {
    operational = data.oneuptime_monitor_status.operational.id
    degraded    = data.oneuptime_monitor_status.degraded.id
    offline     = data.oneuptime_monitor_status.offline.id
  }
}
