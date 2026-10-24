// Inputs consumed by ./modules/alerts.

variable "alert_grouping_rule_config" {
  type = object({
    group_by_monitor        = bool
    group_by_severity       = bool
    group_by_alert_title    = bool
    group_by_alert_labels   = bool
    group_by_monitor_labels = bool
    enable_time_window      = bool
    // Left unset rather than "": OneUptime drops the empty string and returns
    // the field as null, which fails the apply as an inconsistent result.
    group_by_fields       = optional(string)
    enable_reopen_window  = bool
    reopen_window_minutes = number
  })
  description = "Alert grouping rule configuration"
  default = {
    enable_time_window      = false
    group_by_monitor        = false
    group_by_alert_labels   = true
    group_by_alert_title    = false
    group_by_monitor_labels = false
    group_by_severity       = true
    enable_reopen_window    = true
    reopen_window_minutes   = 15
  }
}
