variable "component_definitions" {
  type = map(object({
    groups      = list(string)
    label_names = list(string)
  }))
  description = "component -> its owning groups and the label names that belong to it"
}

variable "label_ids" {
  type        = map(string)
  description = "label name -> oneuptime_label id"
}

variable "team_ids" {
  type        = map(string)
  description = "group name -> oneuptime_team id"
}

variable "on_call_policy_config" {
  type        = any
  description = "On-call policy configuration, normalized by the parent module"
}

variable "on_call_escalation_rules" {
  type        = any
  description = "Escalation rule configuration, normalized by the parent module"
}

variable "on_call_schedule_layer_config" {
  type        = any
  description = "Schedule layer configuration, normalized by the parent module"
}
