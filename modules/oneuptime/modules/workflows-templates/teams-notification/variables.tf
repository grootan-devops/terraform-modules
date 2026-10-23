variable "project_name" {
  type        = string
  description = "Name shown in every message (PROJECT: <name>) and used to name the workflows, e.g. \"Core\""
}

variable "teams_webhook_url" {
  type        = string
  sensitive   = true
  default     = null
  description = <<-EOT
    Microsoft Teams webhook URL the notifications post to. Applied when a
    workflow variable is created and never read back (OneUptime does not return
    secret variables), so changing it later has no effect on an existing
    workflow: recreate the variable, or change it in the console. When null, the
    variable is created with a placeholder.
  EOT
}

variable "dashboard_url" {
  type        = string
  default     = "https://oneuptime.com"
  description = "Base URL of the OneUptime instance, used for the \"open in OneUptime\" links. Set it for a self-hosted instance"
}

variable "enabled" {
  type        = set(string)
  default     = ["monitor-status-changed", "alert-created", "alert-state-changed", "incident-created", "incident-state-changed"]
  description = "Which notifications to build"

  validation {
    condition     = length(setsubtract(var.enabled, ["monitor-status-changed", "alert-created", "alert-state-changed", "incident-created", "incident-state-changed"])) == 0
    error_message = "Unknown notifications: ${join(", ", sort(setsubtract(var.enabled, ["monitor-status-changed", "alert-created", "alert-state-changed", "incident-created", "incident-state-changed"])))}."
  }
}
