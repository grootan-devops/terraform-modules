// Inputs consumed by ./oncall.

variable "on_call_policy_config" {
  type = object({
    repeat_policy_if_no_one_acknowledges             = bool
    repeat_policy_if_no_one_acknowledges_no_of_times = number
  })
  default = {
    repeat_policy_if_no_one_acknowledges             = true
    repeat_policy_if_no_one_acknowledges_no_of_times = 3
  }
}


variable "on_call_escalation_rules" {
  type = object({
    escalate_after_in_minutes = number
    order                     = number
  })
  default = {
    escalate_after_in_minutes = 30
    order                     = 1
  }
}


// Shape of the single schedule layer created per component. OneUptime requires
// a layer before a schedule can put anyone on call, and it wants a rotation and
// a restriction window on every one of them.
variable "on_call_schedule_layer_config" {
  type = object({
    // ISO 8601 instants. OneUptime types both of these as date-times, so a bare
    // number is rejected. Kept as fixed literals rather than timestamp() so a
    // plan does not diff on every run.
    starts_at     = optional(string, "2026-01-01T00:00:00.000Z")
    hand_off_time = optional(string, "2026-01-01T09:00:00.000Z")
    order         = optional(number, 1)

    rotation = optional(object({
      interval_type  = optional(string, "Week")
      interval_count = optional(number, 1)
    }), {})

    // "None" means the layer covers the clock. Business-hours cover is opt-in,
    // because a restricted layer leaves the rest of the day uncovered.
    restriction = optional(object({
      type = optional(string, "None")

      daily = optional(object({
        start_time = string
        end_time   = string
      }))

      weekly = optional(list(object({
        start_day  = string
        end_day    = string
        start_time = string
        end_time   = string
      })), [])
    }), {})
  })
  default = {}

  validation {
    condition     = contains(["Hour", "Day", "Week", "Month", "Year"], var.on_call_schedule_layer_config.rotation.interval_type)
    error_message = "rotation.interval_type must be one of Hour, Day, Week, Month, Year."
  }

  validation {
    condition     = var.on_call_schedule_layer_config.rotation.interval_count > 0
    error_message = "rotation.interval_count must be greater than 0."
  }

  validation {
    condition     = contains(["None", "Daily", "Weekly"], var.on_call_schedule_layer_config.restriction.type)
    error_message = "restriction.type must be one of None, Daily, Weekly."
  }

  validation {
    condition     = var.on_call_schedule_layer_config.restriction.type != "Daily" || var.on_call_schedule_layer_config.restriction.daily != null
    error_message = "restriction.daily must be set when restriction.type is \"Daily\"."
  }

  validation {
    condition     = var.on_call_schedule_layer_config.restriction.type != "Weekly" || length(var.on_call_schedule_layer_config.restriction.weekly) > 0
    error_message = "restriction.weekly must list at least one window when restriction.type is \"Weekly\"."
  }

  validation {
    condition = alltrue([
      for window in var.on_call_schedule_layer_config.restriction.weekly :
      contains(["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"], window.start_day)
      && contains(["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"], window.end_day)
    ])
    error_message = "restriction.weekly start_day and end_day must be full English weekday names, e.g. \"Monday\"."
  }
}
