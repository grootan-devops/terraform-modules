// Inputs shared by every submodule. The domain-specific inputs live next to the
// submodule that consumes them: variables-monitors.tf, variables-alerts.tf,
// variables-incidents.tf, variables-oncall.tf, variables-status-pages.tf.

variable "application" {
  type        = string
  description = "Name of the project or application. Also becomes a project label attached to everything this module creates"
}

variable "labels_config" {
  type        = map(map(string))
  description = "{ label_type = { label_name = hex_colour } }. One oneuptime_label per label name"
  default     = {}
}

// Rbac component and team mapping

variable "rbac_component_mapping" {
  type        = map(list(string))
  description = "component -> the groups that own it. Drives monitor groups, owner rules and label rules across every submodule"
}

variable "rbac_team_mapping" {
  type        = map(list(string))
  description = "group -> member emails. Creates one oneuptime_team per group"
}

variable "custom_fields" {
  type        = string
  default     = null
  description = "Custom Fields on this resource"
}
