// Unit tests for modules/incidents, called directly with the normalized inputs
// the parent module (modules/oneuptime) would pass it. No OneUptime instance or
// API key: the mock provider answers every call.
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

  // The shipped default of incident_grouping_rule_config in
  // modules/oneuptime/variables-incidents.tf, with the unset optional as null.
  incident_grouping_rule_config = {
    group_by_monitor         = false
    group_by_severity        = true
    group_by_incident_title  = false
    group_by_incident_labels = true
    group_by_monitor_labels  = false
    enable_time_window       = false
    group_by_fields          = null
    enable_reopen_window     = true
    reopen_window_minutes    = 15
  }
}

run "one_rule_of_each_kind_per_component" {
  command = plan

  assert {
    condition     = toset(keys(oneuptime_incident_owner_rule.this)) == toset(["platform", "application"])
    error_message = "Expected one incident owner rule per component, not one per component/group pair."
  }

  assert {
    condition     = toset(keys(oneuptime_incident_label_rule.this)) == toset(["platform", "application"])
    error_message = "Expected one incident label rule per component."
  }

  assert {
    condition     = toset(keys(oneuptime_incident_grouping_rule.this)) == toset(["platform", "application"])
    error_message = "Expected one incident grouping rule per component."
  }
}

run "rules_are_named_after_the_component" {
  command = plan

  assert {
    condition     = alltrue([for key, rule in oneuptime_incident_owner_rule.this : rule.name == key])
    error_message = "Every incident owner rule should be named after its component."
  }

  assert {
    condition     = alltrue([for key, rule in oneuptime_incident_label_rule.this : rule.name == key])
    error_message = "Every incident label rule should be named after its component."
  }

  assert {
    condition     = alltrue([for key, rule in oneuptime_incident_grouping_rule.this : rule.name == key])
    error_message = "Every incident grouping rule should be named after its component."
  }

  assert {
    condition     = oneuptime_incident_owner_rule.this["application"].description == "incident owner rule for component application"
    error_message = "Incident owner rule description should be \"incident owner rule for component <component>\"."
  }

  assert {
    condition     = oneuptime_incident_label_rule.this["platform"].description == "incident label rule for component platform"
    error_message = "Incident label rule description should be \"incident label rule for component <component>\"."
  }

  assert {
    condition = (
      startswith(oneuptime_incident_grouping_rule.this["platform"].description, "incident grouping rule")
      && endswith(oneuptime_incident_grouping_rule.this["platform"].description, "for component platform")
    )
    error_message = "Incident grouping rule description should name it an incident grouping rule for the component."
  }

  assert {
    condition     = oneuptime_incident_grouping_rule.this["application"].episode_title_template == "application - Incident Episode"
    error_message = "Episode title should be \"<component> - Incident Episode\"."
  }

  assert {
    condition = (
      startswith(oneuptime_incident_grouping_rule.this["application"].episode_description_template, "An incident episode has been triggered for application.")
      && strcontains(oneuptime_incident_grouping_rule.this["application"].episode_description_template, "affecting the application component")
    )
    error_message = "Episode description should name the component it was triggered for."
  }
}

run "a_component_with_two_owning_groups_gets_one_rule_naming_both_teams" {
  command = plan

  assert {
    condition     = oneuptime_incident_owner_rule.this["application"].owner_teams == toset(["team-developers", "team-devops"])
    error_message = "The application owner rule should own incidents for both of its owning teams."
  }

  assert {
    condition     = oneuptime_incident_owner_rule.this["platform"].owner_teams == toset(["team-devops"])
    error_message = "The platform owner rule should be owned by devops only."
  }

  assert {
    condition     = oneuptime_incident_grouping_rule.this["application"].episode_owner_teams == toset(["team-developers", "team-devops"])
    error_message = "The application episode should be owned by both owning teams."
  }

  assert {
    condition = alltrue([
      for rule in oneuptime_incident_owner_rule.this :
      rule.notify_owners && rule.is_enabled && rule.inherit_owners_from_monitors
    ])
    error_message = "Owner rules should be enabled, notify owners and inherit owners from monitors."
  }
}

run "rules_match_the_component_label_and_add_the_group_labels" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for key, _ in var.component_definitions : [
        oneuptime_incident_owner_rule.this[key].monitor_labels == toset(["label-${key}"]),
        oneuptime_incident_label_rule.this[key].monitor_labels == toset(["label-${key}"]),
        oneuptime_incident_grouping_rule.this[key].monitor_labels == toset(["label-${key}"]),
        oneuptime_incident_grouping_rule.this[key].incident_labels == toset(["label-${key}"]),
      ]
    ]))
    error_message = "Every rule should match monitors (and grouped incidents) on the component label alone."
  }

  assert {
    condition     = oneuptime_incident_label_rule.this["application"].labels_to_add == toset(["label-application", "label-developers", "label-devops"])
    error_message = "The application label rule should add the component label plus both group labels."
  }

  assert {
    condition     = oneuptime_incident_label_rule.this["platform"].labels_to_add == toset(["label-platform", "label-devops"])
    error_message = "The platform label rule should add the component label plus the devops label."
  }

  assert {
    condition     = oneuptime_incident_grouping_rule.this["application"].episode_labels == toset(["label-application", "label-developers", "label-devops"])
    error_message = "The application episode should carry the component label plus both group labels."
  }

  assert {
    condition     = alltrue([for rule in oneuptime_incident_label_rule.this : rule.is_enabled && rule.inherit_labels_from_monitors])
    error_message = "Label rules should be enabled and inherit labels from monitors."
  }
}

run "default_grouping_config_flows_into_every_grouping_rule" {
  command = plan

  assert {
    condition = alltrue([
      for rule in oneuptime_incident_grouping_rule.this :
      rule.group_by_severity == true
      && rule.group_by_incident_labels == true
      && rule.group_by_incident_title == false
      && rule.group_by_monitor == false
      && rule.group_by_monitor_labels == false
      && rule.enable_reopen_window == true
      && rule.reopen_window_minutes == 15
    ])
    error_message = "Grouping rules should take the shipped grouping defaults: by severity and incident labels, 15-minute reopen window."
  }

  assert {
    condition     = alltrue([for rule in oneuptime_incident_grouping_rule.this : rule.priority == 1 && rule.is_enabled])
    error_message = "Grouping rules should be enabled with priority 1."
  }

  assert {
    condition     = alltrue([for rule in oneuptime_incident_grouping_rule.this : length(rule.on_call_duty_policies) == 0])
    error_message = "Grouping rules should not page an on-call policy until one is wired in."
  }
}

run "custom_grouping_config_flows_into_every_grouping_rule" {
  command = plan

  variables {
    incident_grouping_rule_config = {
      group_by_monitor         = true
      group_by_severity        = false
      group_by_incident_title  = true
      group_by_incident_labels = false
      group_by_monitor_labels  = true
      enable_time_window       = false
      group_by_fields          = "service"
      enable_reopen_window     = false
      reopen_window_minutes    = 45
    }
  }

  assert {
    condition = alltrue([
      for rule in oneuptime_incident_grouping_rule.this :
      rule.group_by_severity == false
      && rule.group_by_incident_labels == false
      && rule.group_by_incident_title == true
      && rule.group_by_monitor == true
      && rule.group_by_monitor_labels == true
      && rule.enable_reopen_window == false
      && rule.reopen_window_minutes == 45
    ])
    error_message = "Every flag of incident_grouping_rule_config should reach every grouping rule."
  }

  assert {
    condition     = alltrue([for rule in oneuptime_incident_grouping_rule.this : rule.group_by_fields == "service"])
    error_message = "group_by_fields should reach every grouping rule when set."
  }
}

run "no_components_creates_no_rules" {
  command = plan

  variables {
    component_definitions = {}
  }

  assert {
    condition = (
      length(oneuptime_incident_owner_rule.this) == 0
      && length(oneuptime_incident_label_rule.this) == 0
      && length(oneuptime_incident_grouping_rule.this) == 0
    )
    error_message = "With no components there should be no incident rules at all."
  }
}
