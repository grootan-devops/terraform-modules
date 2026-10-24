// Inputs are normalized by the parent module: the types, defaults and
// validations live in modules/oneuptime/variables*.tf, so what arrives here is
// already complete. See ./README.md for the monitor_configs schema.

variable "application" {
  type        = string
  description = "Project/application name, attached to every monitor as the project label"
}

variable "monitors_component_mapping" {
  type        = map(list(string))
  description = "component -> monitor keys. The keys must exist in monitor_configs"
}

variable "monitor_configs" {
  type        = any
  description = "One entry per monitor, keyed by monitor slug"
}

variable "monitor_defaults" {
  type        = any
  description = "Baseline applied to every monitor, already merged with the module defaults"
}

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
