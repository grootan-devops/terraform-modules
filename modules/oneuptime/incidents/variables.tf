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

variable "incident_grouping_rule_config" {
  type        = any
  description = "Incident grouping rule configuration, normalized by the parent module"
}
