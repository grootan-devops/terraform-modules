terraform {
  required_version = ">= 1.5.0"

  required_providers {
    oneuptime = {
      source  = "oneuptime/oneuptime"
      version = ">= 13.0.6, < 14.0.0"
    }
  }
}

resource "oneuptime_monitor" "this" {
  for_each = local.monitor_definitions

  name         = try(each.value.config.display_name, each.key)
  monitor_type = each.value.config.monitor_type
  description  = try(each.value.config.description, null)

  // Probing behaviour. monitoring_interval is a cron string; a
  // minimum_probe_agreement of 1 means a single probe is enough to flip the
  // status. Defaults come from var.monitor_defaults so monitor_configs only has
  // to carry what differs from the baseline.
  monitoring_interval       = try(each.value.config.monitoring_interval, var.monitor_defaults.monitoring_interval)
  disable_active_monitoring = try(each.value.config.disable_active_monitoring, var.monitor_defaults.disable_active_monitoring)
  minimum_probe_agreement   = try(each.value.config.minimum_probe_agreement, var.monitor_defaults.minimum_probe_agreement)

  // Either provision from a template or from explicit steps, not both.
  monitor_template_id = try(each.value.config.monitor_template_id, null)

  // Steps and criteria are built in locals.tf: generated from monitor_type and
  // the monitor's `target` unless the monitor writes monitor_steps itself.
  // Manual monitors have no steps, and the provider wants null rather than [].
  monitor_steps = length(local.monitor_steps[each.key]) == 0 ? null : local.monitor_steps[each.key]

  // suppress_alerts_when_parent_monitor_statuses is only read when
  // depends_on_monitors is non-empty; empty means every parent status is
  // treated as offline.
  depends_on_monitors                          = try(each.value.config.depends_on_monitors, null)
  suppress_alerts_when_parent_monitor_statuses = try(each.value.config.suppress_alerts_when_parent_monitor_statuses, null)

  custom_fields = try(each.value.config.custom_fields, null)

  labels = toset([
    for label_name in each.value.label_names : var.label_ids[label_name]
  ])
}

resource "oneuptime_monitor_group" "this" {
  for_each    = var.component_definitions
  name        = each.key
  description = "monitor group for component ${each.key}"

  // The component label plus the label of every group that owns it.
  labels = toset([
    for label_name in each.value.label_names : var.label_ids[label_name]
  ])
}

resource "oneuptime_monitor_owner_rule" "this" {
  for_each       = var.component_definitions
  name           = each.key
  is_enabled     = true
  description    = "monitor owner rule for component ${each.key}"
  monitor_labels = toset([var.label_ids[each.key]])
  notify_owners  = true

  // Every group that owns the component becomes an owner team of the rule.
  owner_teams = toset([
    for group in each.value.groups : var.team_ids[group]
  ])
}

resource "oneuptime_monitor_label_rule" "this" {
  for_each       = var.component_definitions
  name           = each.key
  is_enabled     = true
  monitor_labels = toset([var.label_ids[each.key]])
  description    = "monitor label rule for component ${each.key}"

  // Monitors already carry the component label (that is what this rule matches
  // on), so the rule only adds the labels of the owning groups.
  labels_to_add = toset([
    for group in each.value.groups : var.label_ids[group]
  ])
}
