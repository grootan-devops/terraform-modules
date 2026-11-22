// No OneUptime instance or API key: the mock provider answers every call, so
// `command = apply` only builds state in memory. The submodules have their own
// tests under <area>/tests; this file covers what the root owns -
// labels, teams, the wiring between areas - and every input validation.
mock_provider "oneuptime" {}

variables {
  application = "core"

  labels_config = {
    "component" = { "platform" = "#614C3F", "application" = "#F52750" }
    "group"     = { "devops" = "#CED431", "developers" = "#1F6FEB" }
  }

  rbac_component_mapping = {
    "platform"    = ["devops"]
    "application" = ["developers", "devops"]
  }

  rbac_team_mapping = {
    "devops"     = ["devops@example.com"]
    "developers" = ["developers@example.com"]
  }

  monitors_component_mapping = {
    "platform"    = ["edge"]
    "application" = ["api"]
  }

  monitor_configs = {
    "api" = {
      display_name = "Core API"
      monitor_type = "API"
      target       = "https://api.example.com/health"
    }
    "edge" = {
      display_name = "Edge gateway"
      monitor_type = "Ping"
      target       = "10.0.0.1"
      target_type  = "IP"
    }
  }

  status_page_configs = {
    "core" = {}
  }
}

// -----------------------------------------------------------------------------
// What the root creates and wires
// -----------------------------------------------------------------------------

run "creates_one_rule_set_per_component" {
  command = apply

  assert {
    condition     = toset(keys(oneuptime_label.this)) == toset(["core", "platform", "application", "devops", "developers"])
    error_message = "Expected the project label plus every label in labels_config."
  }

  assert {
    condition     = toset(keys(output.team_ids)) == toset(["devops", "developers"])
    error_message = "Expected one team per rbac_team_mapping group."
  }

  assert {
    condition     = toset(keys(output.monitor_ids)) == toset(["api", "edge"])
    error_message = "Expected one monitor per mapped monitor_configs entry."
  }

  assert {
    condition     = toset(keys(output.monitor_group_ids)) == toset(["platform", "application"])
    error_message = "Expected one monitor group per component, not one per owning group."
  }

  assert {
    condition     = toset(keys(output.on_call_policy_ids)) == toset(["platform", "application"])
    error_message = "Expected one on-call policy per component."
  }

  assert {
    condition     = keys(output.status_page_ids) == ["core"]
    error_message = "Expected the status page named after its key."
  }
}

run "labels_carry_their_configured_names_and_colours" {
  command = plan

  assert {
    condition     = oneuptime_label.this["core"].name == "core" && oneuptime_label.this["core"].color == "#1100ff"
    error_message = "The application label must be named after the application and coloured #1100ff."
  }

  assert {
    condition     = oneuptime_label.this["platform"].color == "#614C3F" && oneuptime_label.this["devops"].color == "#CED431"
    error_message = "Labels must take their colour from labels_config."
  }

  assert {
    condition     = oneuptime_team.this["devops"].name == "devops" && oneuptime_team.this["developers"].name == "developers"
    error_message = "Teams must be named after their rbac_team_mapping group."
  }
}

run "application_label_wins_over_a_caller_project_label" {
  command = plan

  variables {
    labels_config = {
      "component" = { "platform" = "#614C3F", "application" = "#F52750" }
      "group"     = { "devops" = "#CED431", "developers" = "#1F6FEB" }
      "project"   = { "other" = "#000000" }
    }
  }

  assert {
    condition     = !contains(keys(oneuptime_label.this), "other") && contains(keys(oneuptime_label.this), "core")
    error_message = "The module's project label type must replace a caller-supplied one."
  }
}

run "unmapped_monitor_configs_are_not_created" {
  command = apply

  variables {
    monitor_configs = {
      "api"    = { display_name = "Core API", monitor_type = "API", target = "https://api.example.com/health" }
      "edge"   = { display_name = "Edge gateway", monitor_type = "Ping", target = "10.0.0.1" }
      "orphan" = { display_name = "Not mapped", monitor_type = "API", target = "https://orphan.example.com" }
    }
  }

  assert {
    condition     = !contains(keys(output.monitor_ids), "orphan")
    error_message = "A monitor_configs entry missing from monitors_component_mapping must not be created."
  }
}

run "no_status_pages_means_no_status_page" {
  command = apply

  variables {
    status_page_configs = {}
  }

  assert {
    condition     = length(output.status_page_ids) == 0
    error_message = "No status_page_configs entry must create no status page."
  }
}

run "monitors_join_their_component_group" {
  command = apply

  assert {
    condition = output.monitor_group_memberships == {
      "api"  = output.monitor_group_ids["application"]
      "edge" = output.monitor_group_ids["platform"]
    }
    error_message = "Each monitor must be a member of its component's monitor group."
  }
}

run "exposes_schedules_and_status_page_groups" {
  command = apply

  variables {
    on_call_overrides = { "platform" = { schedule_enabled = true } }
    status_page_configs = {
      "core" = { groups = { "services" = {}, "infrastructure" = {} } }
    }
  }

  assert {
    condition     = keys(output.on_call_schedule_ids) == ["platform"] && alltrue([for id in values(output.on_call_schedule_ids) : id != ""])
    error_message = "on_call_schedule_ids must list the components with a schedule."
  }

  assert {
    condition     = toset(keys(output.status_page_group_ids)) == toset(["core.services", "core.infrastructure"]) && alltrue([for id in values(output.status_page_group_ids) : id != ""])
    error_message = "status_page_group_ids must list every \"<page>.<group>\" key."
  }
}

run "exposes_heartbeat_and_agent_keys_by_monitor" {
  command = apply

  variables {
    monitors_component_mapping = {
      "platform"    = ["edge", "backup", "mailbox", "runner"]
      "application" = ["api"]
    }
    monitor_configs = {
      "api"     = { display_name = "Core API", monitor_type = "API", target = "https://api.example.com/health" }
      "edge"    = { display_name = "Edge gateway", monitor_type = "Ping", target = "10.0.0.1" }
      "backup"  = { display_name = "Nightly backup", monitor_type = "Incoming Request" }
      "mailbox" = { display_name = "Backup report mailbox", monitor_type = "Incoming Email" }
      "runner"  = { display_name = "Build runner", monitor_type = "Server" }
    }
  }

  assert {
    condition = (
      keys(nonsensitive(output.incoming_request_secret_keys)) == ["backup"]
      && keys(nonsensitive(output.incoming_email_secret_keys)) == ["mailbox"]
      && keys(nonsensitive(output.server_monitor_secret_keys)) == ["runner"]
    )
    error_message = "Each secret key output must list only the monitors of its type, by slug."
  }

  assert {
    condition = alltrue([
      for keys_by_slug in [output.incoming_request_secret_keys, output.incoming_email_secret_keys, output.server_monitor_secret_keys] :
      alltrue([for key in values(nonsensitive(keys_by_slug)) : key != ""])
    ])
    error_message = "Every secret key must be read from the created monitor."
  }
}

run "plans_with_stack_wide_custom_fields" {
  command = plan

  variables {
    custom_fields = jsonencode({ team = "core" })
    monitor_configs = {
      "api"  = { display_name = "Core API", monitor_type = "API", target = "https://api.example.com/health", custom_fields = jsonencode({ tier = "1" }) }
      "edge" = { display_name = "Edge gateway", monitor_type = "Ping", target = "10.0.0.1" }
    }
    status_page_configs = {
      "core" = { custom_fields = jsonencode({ audience = "customers" }) }
    }
  }

  assert {
    condition     = toset(keys(output.monitor_ids)) == toset(["api", "edge"]) && keys(output.status_page_ids) == ["core"]
    error_message = "Stack-wide custom_fields must merge with monitor and page custom_fields without failing the plan."
  }
}

run "workflows_get_the_project_and_monitor_status_ids" {
  command = apply

  variables {
    workflow_configs = {
      "notify" = {
        name = "Core notify"
        nodes = [
          { key = "trigger", type = "alert-on-create", trigger = true },
          {
            key  = "log"
            type = "log"
            arguments = {
              link   = "https://oneuptime.example.com/dashboard/@@project_id@@/alerts"
              status = "@@monitor_status.offline@@"
            }
          },
        ]
        variables = { "token" = { description = "API token" } }
      }
    }
    workflow_variable_contents = { "notify.token" = "secret-value" }
  }

  assert {
    condition     = keys(output.workflow_ids) == ["notify"]
    error_message = "Expected one workflow per workflow_configs entry."
  }

  assert {
    condition     = !strcontains(output.workflow_graphs["notify"], "@@")
    error_message = "Every @@token@@ must be replaced before the graph is sent."
  }

  assert {
    condition     = strcontains(output.workflow_graphs["notify"], "/dashboard/${values(oneuptime_label.this)[0].project_id}/alerts")
    error_message = "@@project_id@@ must become the project the labels belong to."
  }

  assert {
    condition     = length(jsondecode(output.workflow_graphs["notify"]).nodes) == 2 && length(jsondecode(output.workflow_graphs["notify"]).edges) == 1
    error_message = "Two nodes in flow order must produce two canvas nodes and one edge."
  }
}

// -----------------------------------------------------------------------------
// monitors_component_mapping and monitor_configs
// -----------------------------------------------------------------------------

run "rejects_a_mapped_monitor_without_config" {
  command = plan

  variables {
    monitors_component_mapping = {
      "platform" = ["edge", "missing"]
    }
  }

  expect_failures = [var.monitors_component_mapping]
}

run "rejects_an_unknown_monitor_type" {
  command = plan

  variables {
    monitor_configs = {
      "api"  = { display_name = "Core API", monitor_type = "HTTP", target = "https://api.example.com/health" }
      "edge" = { display_name = "Edge gateway", monitor_type = "Ping", target = "10.0.0.1" }
    }
  }

  expect_failures = [var.monitor_configs]
}

run "rejects_a_type_without_presets_and_without_steps" {
  command = plan

  variables {
    monitor_configs = {
      "api"  = { display_name = "Core API", monitor_type = "Logs" }
      "edge" = { display_name = "Edge gateway", monitor_type = "Ping", target = "10.0.0.1" }
    }
  }

  expect_failures = [var.monitor_configs]
}

run "rejects_a_probe_monitor_without_target" {
  command = plan

  variables {
    monitor_configs = {
      "api"  = { display_name = "Core API", monitor_type = "API" }
      "edge" = { display_name = "Edge gateway", monitor_type = "Ping", target = "10.0.0.1" }
    }
  }

  expect_failures = [var.monitor_configs]
}

run "rejects_a_port_monitor_without_port" {
  command = plan

  variables {
    monitor_configs = {
      "api"  = { display_name = "PostgreSQL", monitor_type = "Port", target = "postgres.example.com" }
      "edge" = { display_name = "Edge gateway", monitor_type = "Ping", target = "10.0.0.1" }
    }
  }

  expect_failures = [var.monitor_configs]
}

run "rejects_an_unknown_criteria_preset_key" {
  command = plan

  variables {
    monitor_configs = {
      "api"  = { display_name = "Core API", monitor_type = "API", target = "https://api.example.com", criteria = { offlne = {} } }
      "edge" = { display_name = "Edge gateway", monitor_type = "Ping", target = "10.0.0.1" }
    }
  }

  expect_failures = [var.monitor_configs]
}

run "rejects_an_unknown_criteria_presets_entry" {
  command = plan

  variables {
    monitor_configs = {
      "api"  = { display_name = "Core API", monitor_type = "API", target = "https://api.example.com", criteria_presets = ["offline", "down"] }
      "edge" = { display_name = "Edge gateway", monitor_type = "Ping", target = "10.0.0.1" }
    }
  }

  expect_failures = [var.monitor_configs]
}

run "rejects_an_extra_criterion_order_out_of_range" {
  command = plan

  variables {
    monitor_configs = {
      "api" = {
        display_name   = "Core API"
        monitor_type   = "API"
        target         = "https://api.example.com"
        extra_criteria = [{ name = "Rate limited", order = 1000, filters = [] }]
      }
      "edge" = { display_name = "Edge gateway", monitor_type = "Ping", target = "10.0.0.1" }
    }
  }

  expect_failures = [var.monitor_configs]
}

run "rejects_a_fractional_extra_criterion_order" {
  command = plan

  variables {
    monitor_configs = {
      "api" = {
        display_name   = "Core API"
        monitor_type   = "API"
        target         = "https://api.example.com"
        extra_criteria = [{ name = "Rate limited", order = 5.5, filters = [] }]
      }
      "edge" = { display_name = "Edge gateway", monitor_type = "Ping", target = "10.0.0.1" }
    }
  }

  expect_failures = [var.monitor_configs]
}

// -----------------------------------------------------------------------------
// custom_fields
// -----------------------------------------------------------------------------

run "rejects_custom_fields_that_are_not_an_object" {
  command = plan

  variables {
    custom_fields = jsonencode(["core"])
  }

  expect_failures = [var.custom_fields]
}

run "rejects_monitor_custom_fields_that_are_not_an_object" {
  command = plan

  variables {
    custom_fields = jsonencode({ team = "core" })
    monitor_configs = {
      "api"  = { display_name = "Core API", monitor_type = "API", target = "https://api.example.com", custom_fields = "not json" }
      "edge" = { display_name = "Edge gateway", monitor_type = "Ping", target = "10.0.0.1" }
    }
  }

  expect_failures = [var.monitor_configs]
}

run "rejects_status_page_custom_fields_that_are_not_an_object" {
  command = plan

  variables {
    custom_fields = jsonencode({ team = "core" })
    status_page_configs = {
      "core" = { custom_fields = jsonencode("core") }
    }
  }

  expect_failures = [var.status_page_configs]
}

// -----------------------------------------------------------------------------
// monitor_defaults
// -----------------------------------------------------------------------------

run "rejects_a_monitoring_interval_the_dashboard_does_not_offer" {
  command = plan

  variables {
    monitor_defaults = { monitoring_interval = "*/3 * * * *" }
  }

  expect_failures = [var.monitor_defaults]
}

run "rejects_a_probe_agreement_below_one" {
  command = plan

  variables {
    monitor_defaults = { minimum_probe_agreement = 0 }
  }

  expect_failures = [var.monitor_defaults]
}

run "rejects_a_request_timeout_over_the_server_cap" {
  command = plan

  variables {
    monitor_defaults = { monitor_step = { request_timeout_in_ms = 70000 } }
  }

  expect_failures = [var.monitor_defaults]
}

run "rejects_a_retry_count_over_the_server_cap" {
  command = plan

  variables {
    monitor_defaults = { monitor_step = { retry_count = 5 } }
  }

  expect_failures = [var.monitor_defaults]
}

run "rejects_an_unknown_filter_condition" {
  command = plan

  variables {
    monitor_defaults = { criteria = { filter_condition = "Some" } }
  }

  expect_failures = [var.monitor_defaults]
}

run "rejects_an_unknown_incident_severity" {
  command = plan

  variables {
    monitor_defaults = { severities = { incident = "severe" } }
  }

  expect_failures = [var.monitor_defaults]
}

run "rejects_an_unknown_alert_severity" {
  command = plan

  variables {
    monitor_defaults = { severities = { alert = "medium" } }
  }

  expect_failures = [var.monitor_defaults]
}

run "rejects_an_unknown_evaluate_over_time_type" {
  command = plan

  variables {
    monitor_defaults = { thresholds = { evaluate_over_time_type = "Median" } }
  }

  expect_failures = [var.monitor_defaults]
}

run "rejects_an_evaluate_over_time_window_not_offered" {
  command = plan

  variables {
    monitor_defaults = { thresholds = { evaluate_over_time_minutes = 7 } }
  }

  expect_failures = [var.monitor_defaults]
}

// -----------------------------------------------------------------------------
// on_call_schedule_layer_config
// -----------------------------------------------------------------------------

run "rejects_an_unknown_rotation_interval" {
  command = plan

  variables {
    on_call_schedule_layer_config = { rotation = { interval_type = "Fortnight" } }
  }

  expect_failures = [var.on_call_schedule_layer_config]
}

run "rejects_a_rotation_count_of_zero" {
  command = plan

  variables {
    on_call_schedule_layer_config = { rotation = { interval_count = 0 } }
  }

  expect_failures = [var.on_call_schedule_layer_config]
}

run "rejects_an_unknown_restriction_type" {
  command = plan

  variables {
    on_call_schedule_layer_config = { restriction = { type = "Monthly" } }
  }

  expect_failures = [var.on_call_schedule_layer_config]
}

run "rejects_a_daily_restriction_without_a_window" {
  command = plan

  variables {
    on_call_schedule_layer_config = { restriction = { type = "Daily" } }
  }

  expect_failures = [var.on_call_schedule_layer_config]
}

run "rejects_a_weekly_restriction_without_windows" {
  command = plan

  variables {
    on_call_schedule_layer_config = { restriction = { type = "Weekly", weekly = [] } }
  }

  expect_failures = [var.on_call_schedule_layer_config]
}

run "rejects_an_abbreviated_weekday" {
  command = plan

  variables {
    on_call_schedule_layer_config = {
      restriction = {
        type = "Weekly"
        weekly = [{
          start_day  = "Mon"
          end_day    = "Friday"
          start_time = "2026-01-01T09:00:00.000Z"
          end_time   = "2026-01-01T17:00:00.000Z"
        }]
      }
    }
  }

  expect_failures = [var.on_call_schedule_layer_config]
}

// -----------------------------------------------------------------------------
// status_page_defaults, status_page_configs, status_page_announcements
// -----------------------------------------------------------------------------

run "rejects_uptime_history_over_the_server_cap" {
  command = plan

  variables {
    status_page_defaults = { show_uptime_history_in_days = 120 }
  }

  expect_failures = [var.status_page_defaults]
}

run "rejects_an_unknown_uptime_precision" {
  command = plan

  variables {
    status_page_defaults = { overall_uptime_percent_precision = "Two Decimal" }
  }

  expect_failures = [var.status_page_defaults]
}

run "rejects_an_unknown_group_view_mode" {
  command = plan

  variables {
    status_page_defaults = { group = { view_mode = "Tiles" } }
  }

  expect_failures = [var.status_page_defaults]
}

run "rejects_a_bar_colour_band_over_100" {
  command = plan

  variables {
    status_page_defaults = {
      history_chart_bar_colors = [{ uptime_percent_greater_than_or_equal_to = 101, bar_color = "#0F9D58" }]
    }
  }

  expect_failures = [var.status_page_defaults]
}

run "rejects_a_bar_colour_band_at_zero" {
  command = plan

  variables {
    status_page_defaults = {
      history_chart_bar_colors = [{ uptime_percent_greater_than_or_equal_to = 0, bar_color = "#DB4437" }]
    }
  }

  expect_failures = [var.status_page_defaults]
}

run "rejects_a_resource_with_two_monitor_sources" {
  command = plan

  variables {
    status_page_configs = {
      "core" = { resources = { "api" = { monitor_key = "api", monitor_id = "00000000-0000-0000-0000-000000000000" } } }
    }
  }

  expect_failures = [var.status_page_configs]
}

run "rejects_a_resource_for_an_unknown_monitor" {
  command = plan

  variables {
    status_page_configs = {
      "core" = { resources = { "db" = { monitor_key = "db" } } }
    }
  }

  expect_failures = [var.status_page_configs]
}

run "rejects_a_resource_for_an_unknown_component" {
  command = plan

  variables {
    status_page_configs = {
      "core" = { resources = { "infra" = { monitor_group_key = "infrastructure" } } }
    }
  }

  expect_failures = [var.status_page_configs]
}

run "rejects_a_resource_in_an_undeclared_group" {
  command = plan

  variables {
    status_page_configs = {
      "core" = { resources = { "api" = { monitor_key = "api", group_key = "services" } } }
    }
  }

  expect_failures = [var.status_page_configs]
}

run "rejects_a_monitor_rule_that_matches_nothing" {
  command = plan

  variables {
    status_page_configs = {
      "core" = { monitor_rules = { "all" = { name = "All" } } }
    }
  }

  expect_failures = [var.status_page_configs]
}

run "rejects_an_announcement_about_an_unknown_monitor" {
  command = plan

  variables {
    status_page_announcements = {
      "upgrade" = {
        title                = "Upgrade"
        description          = "Planned upgrade."
        show_announcement_at = "2026-09-01T09:00:00Z"
        monitor_keys         = ["db"]
      }
    }
  }

  expect_failures = [var.status_page_announcements]
}

run "rejects_an_announcement_on_an_unknown_page" {
  command = plan

  variables {
    status_page_announcements = {
      "upgrade" = {
        title                = "Upgrade"
        description          = "Planned upgrade."
        show_announcement_at = "2026-09-01T09:00:00Z"
        status_page_keys     = ["internal"]
      }
    }
  }

  expect_failures = [var.status_page_announcements]
}

// -----------------------------------------------------------------------------
// workflow_configs and workflow_variable_contents
// -----------------------------------------------------------------------------

run "rejects_a_workflow_with_neither_nodes_nor_graph" {
  command = plan

  variables {
    workflow_configs = { "empty" = { name = "Empty" } }
  }

  expect_failures = [var.workflow_configs]
}

run "rejects_a_graph_that_is_not_json" {
  command = plan

  variables {
    workflow_configs = { "raw" = { name = "Raw", graph = "not json" } }
  }

  expect_failures = [var.workflow_configs]
}

run "rejects_a_graph_without_edges" {
  command = plan

  variables {
    workflow_configs = { "raw" = { name = "Raw", graph = "{\"nodes\": []}" } }
  }

  expect_failures = [var.workflow_configs]
}

run "rejects_a_workflow_without_a_trigger" {
  command = plan

  variables {
    workflow_configs = {
      "notify" = { name = "Notify", nodes = [{ key = "log", type = "log" }] }
    }
  }

  expect_failures = [var.workflow_configs]
}

run "rejects_a_repeated_node_key" {
  command = plan

  variables {
    workflow_configs = {
      "notify" = {
        name  = "Notify"
        nodes = [{ key = "step", type = "alert-on-create", trigger = true }, { key = "step", type = "log" }]
      }
    }
  }

  expect_failures = [var.workflow_configs]
}

run "rejects_a_next_target_that_is_not_a_node" {
  command = plan

  variables {
    workflow_configs = {
      "notify" = {
        name  = "Notify"
        nodes = [{ key = "trigger", type = "alert-on-create", trigger = true, next = { success = "missing" } }]
      }
    }
  }

  expect_failures = [var.workflow_configs]
}

run "rejects_contents_for_an_undeclared_variable" {
  command = plan

  variables {
    workflow_configs = {
      "notify" = {
        name      = "Notify"
        nodes     = [{ key = "trigger", type = "alert-on-create", trigger = true }]
        variables = { "token" = {} }
      }
    }
    workflow_variable_contents = { "notify.webhook" = "https://example.com/hook" }
  }

  expect_failures = [var.workflow_variable_contents]
}

run "rejects_an_on_call_override_for_an_unknown_component" {
  command = plan

  variables {
    on_call_overrides = {
      "not-a-component" = { escalate_after_in_minutes = 5 }
    }
  }

  expect_failures = [var.on_call_overrides]
}
