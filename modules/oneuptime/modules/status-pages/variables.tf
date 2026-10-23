// Inputs are normalized by the parent module: the types, defaults and
// validations for status_page_defaults, status_page_configs and
// status_page_announcements live in modules/oneuptime/variables-status-pages.tf,
// so what arrives here is already complete. See ./README.md for the schema.

variable "application" {
  type        = string
  description = "Project/application name. A page with no label_names of its own carries this label"
}

variable "status_page_defaults" {
  type        = any
  description = "Baseline applied to every status page, already merged with the module defaults"
}

variable "status_page_configs" {
  type        = any
  description = "One entry per status page, keyed by a short identifier"
  default     = {}
}

variable "status_page_announcements" {
  type        = any
  description = "Announcements published across status pages, keyed by a short identifier"
  default     = {}
}

variable "monitor_configs" {
  type        = any
  description = "Monitor configuration, read only for the display_name of a published monitor"
  default     = {}
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

variable "monitor_ids" {
  type        = map(string)
  description = "monitor key -> oneuptime_monitor id, from the monitors submodule"
  default     = {}
}

variable "monitor_group_ids" {
  type        = map(string)
  description = "component -> oneuptime_monitor_group id, from the monitors submodule"
  default     = {}
}
