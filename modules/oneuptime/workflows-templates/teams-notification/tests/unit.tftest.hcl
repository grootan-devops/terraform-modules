// The template creates no resources, so it needs no provider: every run only
// evaluates the workflow_configs it builds.

variables {
  project_name = "Core"
}

run "builds_all_five_notifications_by_default" {
  command = plan

  assert {
    condition = toset(keys(output.workflow_configs)) == toset([
      "monitor-status-changed", "alert-created", "alert-state-changed", "incident-created", "incident-state-changed",
    ])
    error_message = "Expected all five Teams notifications when enabled is left at its default."
  }

  assert {
    condition     = output.workflow_configs["alert-created"].name == "Core — Teams — Alert created"
    error_message = "Workflow names must be \"<project_name> — Teams — <event>\"."
  }

  assert {
    condition     = output.workflow_configs["monitor-status-changed"].name == "Core — Teams — Monitor status changed"
    error_message = "Workflow names must be \"<project_name> — Teams — <event>\"."
  }

  assert {
    condition = alltrue([
      for key, workflow in output.workflow_configs : keys(workflow.variables) == ["teamsWebhookUrl"]
    ])
    error_message = "Every notification must declare exactly one variable, teamsWebhookUrl."
  }

  assert {
    condition = alltrue([
      for key, workflow in output.workflow_configs : length([for node in workflow.nodes : node if try(node.trigger, false)]) == 1
    ])
    error_message = "Every notification must have exactly one trigger node."
  }

  assert {
    condition = alltrue([
      for key, workflow in output.workflow_configs : anytrue([
        for node in workflow.nodes : node.type == "microsoft-teams-send-message-to-channel"
        && try(node.arguments["webhook-url"], "") == "{{local.variables.teamsWebhookUrl}}"
      ])
    ])
    error_message = "Every notification must post to Teams through the teamsWebhookUrl variable."
  }

  assert {
    condition     = length(output.workflow_variable_contents) == 0
    error_message = "With no webhook URL the variables must be left to the placeholder, so no contents are emitted."
  }
}

run "links_default_to_oneuptime_com" {
  command = plan

  assert {
    condition = alltrue([
      for key, workflow in output.workflow_configs : anytrue([
        for node in workflow.nodes : strcontains(join("\n", values(try(node.arguments, {}))), "https://oneuptime.com/dashboard/@@project_id@@/")
      ])
    ])
    error_message = "Dashboard links must default to https://oneuptime.com and keep the @@project_id@@ token for the module to fill."
  }
}

run "links_follow_a_self_hosted_dashboard_url" {
  command = plan

  variables {
    dashboard_url = "https://oneuptime.example.com"
  }

  assert {
    condition = alltrue([
      for key, workflow in output.workflow_configs : anytrue([
        for node in workflow.nodes : strcontains(join("\n", values(try(node.arguments, {}))), "https://oneuptime.example.com/dashboard/@@project_id@@/")
      ])
    ])
    error_message = "Dashboard links must use dashboard_url."
  }

  assert {
    condition = alltrue([
      for key, workflow in output.workflow_configs : !anytrue([
        for node in workflow.nodes : strcontains(join("\n", values(try(node.arguments, {}))), "https://oneuptime.com/")
      ])
    ])
    error_message = "No link may fall back to the default host once dashboard_url is set."
  }
}

run "webhook_url_becomes_every_variable_content" {
  command = plan

  variables {
    teams_webhook_url = "https://example.webhook.office.com/hook"
  }

  assert {
    condition = toset(keys(output.workflow_variable_contents)) == toset([
      "monitor-status-changed.teamsWebhookUrl", "alert-created.teamsWebhookUrl", "alert-state-changed.teamsWebhookUrl",
      "incident-created.teamsWebhookUrl", "incident-state-changed.teamsWebhookUrl",
    ])
    error_message = "Contents must be keyed \"<workflow>.teamsWebhookUrl\", one per notification."
  }

  assert {
    condition     = alltrue([for ref, value in output.workflow_variable_contents : value == "https://example.webhook.office.com/hook"])
    error_message = "Every content must be the webhook URL."
  }
}

run "enabled_narrows_the_set" {
  command = plan

  variables {
    enabled           = ["alert-created", "incident-created"]
    teams_webhook_url = "https://example.webhook.office.com/hook"
  }

  assert {
    condition     = toset(keys(output.workflow_configs)) == toset(["alert-created", "incident-created"])
    error_message = "Only the enabled notifications must be built."
  }

  assert {
    condition     = toset(keys(output.workflow_variable_contents)) == toset(["alert-created.teamsWebhookUrl", "incident-created.teamsWebhookUrl"])
    error_message = "Contents must follow the enabled set."
  }
}

run "rejects_an_unknown_notification" {
  command = plan

  variables {
    enabled = ["alert-created", "deploy-finished"]
  }

  expect_failures = [var.enabled]
}
