terraform {
  required_version = ">= 1.5.0"

  required_providers {
    oneuptime = {
      source  = "oneuptime/oneuptime"
      version = ">= 13.0.6, < 14.0.0"
    }
  }
}

// One rule per component. component_definitions gives a component a list of
// owning groups, and owner_teams takes a set, so the list collapses into the
// team set of a single rule rather than fanning out into one rule per group.
resource "oneuptime_incident_owner_rule" "this" {
  for_each       = var.component_definitions
  name           = each.key
  is_enabled     = true
  description    = "incident owner rule for component ${each.key}"
  monitor_labels = toset([var.label_ids[each.key]])
  notify_owners  = true

  owner_teams = toset([
    for group in each.value.groups : var.team_ids[group]
  ])

  inherit_owners_from_monitors = true
}

resource "oneuptime_incident_label_rule" "this" {
  for_each       = var.component_definitions
  name           = each.key
  is_enabled     = true
  monitor_labels = toset([var.label_ids[each.key]])
  description    = "incident label rule for component ${each.key}"

  // The component label plus the label of every group that owns it.
  labels_to_add = toset([
    for label_name in each.value.label_names : var.label_ids[label_name]
  ])

  inherit_labels_from_monitors = true
}

resource "oneuptime_incident_grouping_rule" "this" {
  for_each                     = var.component_definitions
  name                         = each.key
  description                  = "incident grouping rule label rule for component ${each.key}"
  priority                     = 1
  is_enabled                   = true
  monitor_labels               = toset([var.label_ids[each.key]])
  incident_labels              = toset([var.label_ids[each.key]])
  group_by_severity            = var.incident_grouping_rule_config.group_by_severity
  group_by_incident_labels     = var.incident_grouping_rule_config.group_by_incident_labels
  group_by_incident_title      = var.incident_grouping_rule_config.group_by_incident_title
  group_by_fields              = var.incident_grouping_rule_config.group_by_fields
  group_by_monitor             = var.incident_grouping_rule_config.group_by_monitor
  group_by_monitor_labels      = var.incident_grouping_rule_config.group_by_monitor_labels
  enable_reopen_window         = var.incident_grouping_rule_config.enable_reopen_window
  reopen_window_minutes        = var.incident_grouping_rule_config.reopen_window_minutes
  episode_title_template       = "${each.key} - Incident Episode"
  episode_description_template = "An incident episode has been triggered for ${each.key}. This episode groups related incidents affecting the ${each.key} component. Review the incidents in this episode for the latest impact and details."

  episode_labels = toset([
    for label_name in each.value.label_names : var.label_ids[label_name]
  ])

  episode_owner_teams = toset([
    for group in each.value.groups : var.team_ids[group]
  ])

  // Wire on_call_policy_ids from the oncall submodule in here to page the
  // on-call rota when an episode opens.
  on_call_duty_policies = [] // TO-DO
}
