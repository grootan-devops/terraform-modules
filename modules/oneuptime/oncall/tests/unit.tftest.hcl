// Unit tests for oncall/, called directly with the normalized inputs the
// parent module (modules/oneuptime) would pass it. No OneUptime instance or API
// key: the mock provider answers every call, so `command = apply` only builds
// state in memory.
mock_provider "oneuptime" {}

variables {
  // What modules/oneuptime/locals.tf derives from
  //   rbac_component_mapping = { platform = ["devops"], application = ["developers", "devops"] }
  component_definitions = {
    "platform" = {
      groups      = ["devops"]
      label_names = ["platform", "devops"]
    }
    "application" = {
      groups      = ["developers", "devops"]
      label_names = ["application", "developers", "devops"]
    }
  }

  label_ids = {
    "core"        = "label-core"
    "platform"    = "label-platform"
    "application" = "label-application"
    "devops"      = "label-devops"
    "developers"  = "label-developers"
  }

  team_ids = {
    "devops"     = "team-devops"
    "developers" = "team-developers"
  }

  // The shipped defaults in modules/oneuptime/variables-oncall.tf.
  on_call_policy_config = {
    repeat_policy_if_no_one_acknowledges             = true
    repeat_policy_if_no_one_acknowledges_no_of_times = 3
  }

  on_call_escalation_rules = {
    escalate_after_in_minutes = 30
    order                     = 1
  }

  // on_call_schedule_layer_config = {} after the parent's optional() defaults.
  on_call_schedule_layer_config = {
    starts_at     = "2026-01-01T00:00:00.000Z"
    hand_off_time = "2026-01-01T09:00:00.000Z"
    order         = 1
    rotation = {
      interval_type  = "Week"
      interval_count = 1
    }
    restriction = {
      type   = "None"
      daily  = null
      weekly = []
    }
  }
}

run "one_on_call_setup_per_component" {
  command = plan

  assert {
    condition = alltrue([
      for instances in [
        oneuptime_on_call_policy.this,
        oneuptime_on_call_policy_owner_rule.this,
        oneuptime_escalation_rule.this,
        oneuptime_on_call_policy_schedule.this,
        oneuptime_schedules_on_call_duty_escalation_rule.this,
        oneuptime_on_call_schedule_layer.this,
      ] : toset(keys(instances)) == toset(["platform", "application"])
    ])
    error_message = "Expected exactly one policy, owner rule, escalation rule, schedule, binding and layer per component."
  }
}

run "resources_are_named_after_the_component" {
  command = plan

  assert {
    condition     = oneuptime_on_call_policy.this["platform"].name == "platform-oncall-policy"
    error_message = "On-call policy should be named \"<component>-oncall-policy\"."
  }

  assert {
    condition     = oneuptime_on_call_policy.this["platform"].description == "oncall policy for component platform"
    error_message = "On-call policy description should be \"oncall policy for component <component>\"."
  }

  assert {
    condition     = oneuptime_on_call_policy_owner_rule.this["application"].name == "application-oncall-policy-owner-rule"
    error_message = "Owner rule should be named \"<component>-oncall-policy-owner-rule\"."
  }

  assert {
    condition     = oneuptime_on_call_policy_owner_rule.this["application"].description == "oncall policy owner rule for component application"
    error_message = "Owner rule description should be \"oncall policy owner rule for component <component>\"."
  }

  assert {
    condition     = oneuptime_escalation_rule.this["platform"].name == "platform-oncall-policy-escalation-rule"
    error_message = "Escalation rule should be named \"<component>-oncall-policy-escalation-rule\"."
  }

  assert {
    condition     = oneuptime_escalation_rule.this["platform"].description == "oncall policy escalation rules for component platform"
    error_message = "Escalation rule description should name the component."
  }

  assert {
    condition     = oneuptime_on_call_policy_schedule.this["application"].name == "application-oncall-schedule"
    error_message = "Schedule should be named \"<component>-oncall-schedule\"."
  }

  assert {
    condition     = oneuptime_on_call_policy_schedule.this["application"].description == "On-call schedule for application"
    error_message = "Schedule description should be \"On-call schedule for <component>\"."
  }

  assert {
    condition     = oneuptime_on_call_schedule_layer.this["application"].name == "application-oncall-schedule-layer"
    error_message = "Schedule layer should be named \"<component>-oncall-schedule-layer\"."
  }
}

run "policies_carry_component_and_group_labels_and_every_owning_team" {
  command = plan

  assert {
    condition     = oneuptime_on_call_policy.this["application"].labels == toset(["label-application", "label-developers", "label-devops"])
    error_message = "The application policy should carry the component label plus both group labels."
  }

  assert {
    condition     = oneuptime_on_call_policy.this["platform"].labels == toset(["label-platform", "label-devops"])
    error_message = "The platform policy should carry the component label plus the devops label."
  }

  assert {
    condition     = oneuptime_on_call_policy_owner_rule.this["application"].on_call_duty_policy_labels == toset(["label-application", "label-developers", "label-devops"])
    error_message = "The application owner rule should match on the component label plus both group labels."
  }

  assert {
    condition     = oneuptime_on_call_policy_owner_rule.this["application"].owner_teams == toset(["team-developers", "team-devops"])
    error_message = "A component owned by two groups should get one owner rule naming both teams."
  }

  assert {
    condition     = oneuptime_on_call_policy_owner_rule.this["platform"].owner_teams == toset(["team-devops"])
    error_message = "The platform owner rule should name the devops team only."
  }
}

run "default_timings_flow_through" {
  command = plan

  assert {
    condition = alltrue([
      for policy in oneuptime_on_call_policy.this :
      policy.repeat_policy_if_no_one_acknowledges == true
      && policy.repeat_policy_if_no_one_acknowledges_no_of_times == 3
    ])
    error_message = "Policies should repeat 3 times when nobody acknowledges."
  }

  assert {
    condition = alltrue([
      for rule in oneuptime_escalation_rule.this :
      rule.escalate_after_in_minutes == 30 && rule.order == 1
    ])
    error_message = "Escalation rules should escalate after 30 minutes at order 1."
  }

  assert {
    condition = alltrue([
      for layer in oneuptime_on_call_schedule_layer.this :
      layer.starts_at == "2026-01-01T00:00:00.000Z"
      && layer.hand_off_time == "2026-01-01T09:00:00.000Z"
      && layer.order == 1
    ])
    error_message = "Schedule layers should take starts_at, hand_off_time and order from on_call_schedule_layer_config."
  }
}

run "default_layer_is_a_weekly_unrestricted_rotation_in_the_wire_format" {
  command = plan

  assert {
    condition = jsondecode(oneuptime_on_call_schedule_layer.this["platform"].rotation) == {
      _type = "Recurring"
      value = {
        intervalType  = "Week"
        intervalCount = { _type = "PositiveNumber", value = 1 }
      }
    }
    error_message = "rotation should be the tagged Recurring value with a PositiveNumber interval count."
  }

  assert {
    condition     = jsondecode(oneuptime_on_call_schedule_layer.this["platform"].restriction_times)._type == "RestrictionTimes"
    error_message = "restriction_times should be tagged _type = \"RestrictionTimes\"."
  }

  assert {
    condition     = jsondecode(oneuptime_on_call_schedule_layer.this["platform"].restriction_times).value.restictionType == "None"
    error_message = "restriction type should be sent under the upstream (misspelt) key restictionType."
  }

  assert {
    condition     = !contains(keys(jsondecode(oneuptime_on_call_schedule_layer.this["platform"].restriction_times).value), "restrictionType")
    error_message = "The correctly spelt restrictionType key is ignored by OneUptime and should not be sent."
  }

  assert {
    condition     = jsondecode(oneuptime_on_call_schedule_layer.this["platform"].restriction_times).value.dayRestrictionTimes == null
    error_message = "An unrestricted layer should send no daily window."
  }

  assert {
    condition     = jsondecode(oneuptime_on_call_schedule_layer.this["platform"].restriction_times).value.weeklyRestrictionTimes == []
    error_message = "weeklyRestrictionTimes should be an empty list, never null, on an unrestricted layer."
  }

  assert {
    condition = (
      oneuptime_on_call_schedule_layer.this["platform"].rotation == oneuptime_on_call_schedule_layer.this["application"].rotation
      && oneuptime_on_call_schedule_layer.this["platform"].restriction_times == oneuptime_on_call_schedule_layer.this["application"].restriction_times
    )
    error_message = "Every component's layer should share the same rotation and restriction."
  }
}

run "daily_restriction_and_custom_timings" {
  command = plan

  variables {
    on_call_policy_config = {
      repeat_policy_if_no_one_acknowledges             = false
      repeat_policy_if_no_one_acknowledges_no_of_times = 5
    }

    on_call_escalation_rules = {
      escalate_after_in_minutes = 10
      order                     = 2
    }

    on_call_schedule_layer_config = {
      starts_at     = "2026-03-01T00:00:00.000Z"
      hand_off_time = "2026-03-01T08:00:00.000Z"
      order         = 3
      rotation = {
        interval_type  = "Day"
        interval_count = 2
      }
      restriction = {
        type = "Daily"
        daily = {
          start_time = "2026-01-01T09:00:00.000Z"
          end_time   = "2026-01-01T17:00:00.000Z"
        }
        weekly = []
      }
    }
  }

  assert {
    condition = alltrue([
      for policy in oneuptime_on_call_policy.this :
      policy.repeat_policy_if_no_one_acknowledges == false
      && policy.repeat_policy_if_no_one_acknowledges_no_of_times == 5
    ])
    error_message = "on_call_policy_config should reach every policy."
  }

  assert {
    condition = alltrue([
      for rule in oneuptime_escalation_rule.this :
      rule.escalate_after_in_minutes == 10 && rule.order == 2
    ])
    error_message = "on_call_escalation_rules should reach every escalation rule."
  }

  assert {
    condition = alltrue([
      for layer in oneuptime_on_call_schedule_layer.this :
      layer.starts_at == "2026-03-01T00:00:00.000Z"
      && layer.hand_off_time == "2026-03-01T08:00:00.000Z"
      && layer.order == 3
    ])
    error_message = "Custom starts_at, hand_off_time and order should reach every layer."
  }

  assert {
    condition = jsondecode(oneuptime_on_call_schedule_layer.this["application"].rotation).value == {
      intervalType  = "Day"
      intervalCount = { _type = "PositiveNumber", value = 2 }
    }
    error_message = "rotation should carry the configured interval type and count."
  }

  assert {
    condition = jsondecode(oneuptime_on_call_schedule_layer.this["application"].restriction_times).value == {
      restictionType = "Daily"
      dayRestrictionTimes = {
        startTime = "2026-01-01T09:00:00.000Z"
        endTime   = "2026-01-01T17:00:00.000Z"
      }
      weeklyRestrictionTimes = []
    }
    error_message = "A Daily restriction should send dayRestrictionTimes and still an empty weeklyRestrictionTimes list."
  }
}

run "weekly_restriction_sends_every_window" {
  command = plan

  variables {
    on_call_schedule_layer_config = {
      starts_at     = "2026-01-01T00:00:00.000Z"
      hand_off_time = "2026-01-01T09:00:00.000Z"
      order         = 1
      rotation = {
        interval_type  = "Week"
        interval_count = 1
      }
      restriction = {
        type  = "Weekly"
        daily = null
        weekly = [
          {
            start_day  = "Monday"
            end_day    = "Friday"
            start_time = "2026-01-01T09:00:00.000Z"
            end_time   = "2026-01-01T17:00:00.000Z"
          },
          {
            start_day  = "Saturday"
            end_day    = "Sunday"
            start_time = "2026-01-01T10:00:00.000Z"
            end_time   = "2026-01-01T14:00:00.000Z"
          },
        ]
      }
    }
  }

  assert {
    condition     = jsondecode(oneuptime_on_call_schedule_layer.this["platform"].restriction_times).value.restictionType == "Weekly"
    error_message = "A Weekly restriction should be sent as restictionType = \"Weekly\"."
  }

  assert {
    condition     = jsondecode(oneuptime_on_call_schedule_layer.this["platform"].restriction_times).value.dayRestrictionTimes == null
    error_message = "A Weekly restriction should send no daily window."
  }

  assert {
    condition = jsondecode(oneuptime_on_call_schedule_layer.this["platform"].restriction_times).value.weeklyRestrictionTimes == [
      {
        startDay  = "Monday"
        endDay    = "Friday"
        startTime = "2026-01-01T09:00:00.000Z"
        endTime   = "2026-01-01T17:00:00.000Z"
      },
      {
        startDay  = "Saturday"
        endDay    = "Sunday"
        startTime = "2026-01-01T10:00:00.000Z"
        endTime   = "2026-01-01T14:00:00.000Z"
      },
    ]
    error_message = "Every weekly window should be sent, in order, with camelCase keys."
  }
}

run "escalation_rule_pages_the_components_schedule" {
  command = apply

  assert {
    condition = alltrue([
      for key, rule in oneuptime_escalation_rule.this :
      rule.on_call_duty_policy_id == oneuptime_on_call_policy.this[key].id
    ])
    error_message = "Each escalation rule should belong to its own component's policy."
  }

  assert {
    condition = alltrue([
      for key, binding in oneuptime_schedules_on_call_duty_escalation_rule.this :
      binding.on_call_duty_policy_id == oneuptime_on_call_policy.this[key].id
      && binding.on_call_duty_policy_escalation_rule_id == oneuptime_escalation_rule.this[key].id
      && binding.on_call_duty_policy_schedule_id == oneuptime_on_call_policy_schedule.this[key].id
    ])
    error_message = "Each binding should tie a component's escalation rule to that same component's schedule."
  }

  assert {
    condition = alltrue([
      for key, layer in oneuptime_on_call_schedule_layer.this :
      layer.on_call_duty_policy_schedule_id == oneuptime_on_call_policy_schedule.this[key].id
    ])
    error_message = "Each layer should sit on its own component's schedule."
  }

  assert {
    condition     = output.on_call_policy_ids == { for key, policy in oneuptime_on_call_policy.this : key => policy.id }
    error_message = "on_call_policy_ids should map each component to its policy id."
  }

  assert {
    condition     = output.on_call_schedule_ids == { for key, schedule in oneuptime_on_call_policy_schedule.this : key => schedule.id }
    error_message = "on_call_schedule_ids should map each component to its schedule id."
  }
}
