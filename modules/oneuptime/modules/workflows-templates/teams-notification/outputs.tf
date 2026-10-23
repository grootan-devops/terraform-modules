output "workflow_configs" {
  description = "Pass to the oneuptime module's workflow_configs, merged with any workflows of your own"
  value       = local.notifications
}

output "workflow_variable_contents" {
  description = "Pass to the oneuptime module's workflow_variable_contents. Empty when no webhook URL was given"
  sensitive   = true
  value = var.teams_webhook_url == null ? {} : {
    for key, workflow in local.notifications : "${key}.teamsWebhookUrl" => var.teams_webhook_url
  }
}
