// No OneUptime instance or API key: the mock provider answers every call, so
// `command = apply` only builds state in memory.
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
    error_message = "Expected one monitor per monitor_configs entry."
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
      "api" = {
        display_name = "Core API"
        monitor_type = "HTTP"
        target       = "https://api.example.com/health"
      }
      "edge" = {
        display_name = "Edge gateway"
        monitor_type = "Ping"
        target       = "10.0.0.1"
      }
    }
  }

  expect_failures = [var.monitor_configs]
}
