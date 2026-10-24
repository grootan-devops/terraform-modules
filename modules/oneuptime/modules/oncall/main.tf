terraform {
  required_version = ">= 1.9.0"

  required_providers {
    oneuptime = {
      source  = "oneuptime/oneuptime"
      version = "< 15.0.0"
    }
  }
}

resource "oneuptime_on_call_policy" "this" {
  for_each    = var.component_definitions
  name        = "${each.key}-oncall-policy"
  description = "oncall policy for component ${each.key}"

  // The component label plus the label of every group that owns it.
  labels = toset([
    for label_name in each.value.label_names : var.label_ids[label_name]
  ])

  repeat_policy_if_no_one_acknowledges             = var.on_call_policy_config.repeat_policy_if_no_one_acknowledges
  repeat_policy_if_no_one_acknowledges_no_of_times = var.on_call_policy_config.repeat_policy_if_no_one_acknowledges_no_of_times
}

resource "oneuptime_on_call_policy_owner_rule" "this" {
  for_each    = var.component_definitions
  name        = "${each.key}-oncall-policy-owner-rule"
  description = "oncall policy owner rule for component ${each.key}"

  on_call_duty_policy_labels = toset([
    for label_name in each.value.label_names : var.label_ids[label_name]
  ])

  // Owner teams resolve through team ids, not label ids.
  owner_teams = toset([
    for group in each.value.groups : var.team_ids[group]
  ])

  depends_on = [oneuptime_on_call_policy.this]
}

resource "oneuptime_escalation_rule" "this" {
  for_each                  = var.component_definitions
  on_call_duty_policy_id    = oneuptime_on_call_policy.this[each.key].id
  name                      = "${each.key}-oncall-policy-escalation-rule"
  description               = "oncall policy escalation rules for component ${each.key}"
  escalate_after_in_minutes = var.on_call_escalation_rules.escalate_after_in_minutes
  order                     = var.on_call_escalation_rules.order
}

resource "oneuptime_on_call_policy_schedule" "this" {
  for_each    = var.component_definitions
  name        = "${each.key}-oncall-schedule"
  description = "On-call schedule for ${each.key}"
}

// Binds the schedule to the escalation rule, so the rule pages whoever the
// schedule has on call. The schedule id is optional in the provider schema but
// the API rejects the create without it.
resource "oneuptime_schedules_on_call_duty_escalation_rule" "this" {
  for_each                               = var.component_definitions
  on_call_duty_policy_id                 = oneuptime_on_call_policy.this[each.key].id
  on_call_duty_policy_escalation_rule_id = oneuptime_escalation_rule.this[each.key].id
  on_call_duty_policy_schedule_id        = oneuptime_on_call_policy_schedule.this[each.key].id
}

resource "oneuptime_on_call_schedule_layer" "this" {
  for_each                        = var.component_definitions
  name                            = "${each.key}-oncall-schedule-layer"
  on_call_duty_policy_schedule_id = oneuptime_on_call_policy_schedule.this[each.key].id
  order                           = var.on_call_schedule_layer_config.order
  starts_at                       = var.on_call_schedule_layer_config.starts_at
  hand_off_time                   = var.on_call_schedule_layer_config.hand_off_time
  rotation                        = local.rotation
  restriction_times               = local.restriction_times
}
