mock_provider "oneuptime" {}

override_data {
  target = module.oneuptime.module.monitors.data.oneuptime_monitor_status.operational
  values = { id = "status-operational" }
}

override_data {
  target = module.oneuptime.module.monitors.data.oneuptime_monitor_status.degraded
  values = { id = "status-degraded" }
}

override_data {
  target = module.oneuptime.module.monitors.data.oneuptime_monitor_status.offline
  values = { id = "status-offline" }
}

override_data {
  target = data.oneuptime_monitor_status.degraded
  values = { id = "status-degraded" }
}

override_data {
  target = data.oneuptime_monitor_status.operational
  values = { id = "status-operational" }
}

override_data {
  target = data.oneuptime_alert_severity.high
  values = { id = "alert-severity-high" }
}

override_data {
  target = module.oneuptime.module.status_pages.data.oneuptime_domain.by_name
  values = { id = "domain-example" }
}

variables {
  oneuptime_url                 = "https://oneuptime.example.com"
  teams_webhook_url             = "https://hooks.example.com/teams/shop-notifications"
  major_incident_webhook_url    = "https://hooks.example.com/teams/shop-major-incidents"
  status_page_teams_webhook_url = "https://hooks.example.com/teams/shop-status"
}

run "plans_with_unknown_ids" {
  command = plan

  assert {
    condition = toset(keys(output.label_ids)) == toset([
      "shop", "storefront", "checkout", "data", "network", "operations", "frontend", "backend", "sre", "dba",
    ])
    error_message = "Expected the application label plus one label per component and group."
  }

  assert {
    condition     = toset(keys(output.team_ids)) == toset(["frontend", "backend", "sre", "dba"])
    error_message = "Expected one team per group."
  }

  assert {
    condition = toset(keys(output.monitor_ids)) == toset([
      "storefront", "storefront-journey", "storefront-tls", "storefront-dns", "storefront-dnssec", "storefront-domain",
      "checkout-api", "checkout-regions", "payment-gateway", "order-export", "checkout-errors",
      "postgres-primary", "orders-replica-lag", "db-host", "nightly-backup",
      "edge-gateway", "vpn-concentrator",
      "backup-report-email", "dc-migration",
    ])
    error_message = "Expected one monitor per mapped slug, covering every monitor type in the inventory."
  }

  assert {
    condition     = toset(keys(output.monitor_group_ids)) == toset(["storefront", "checkout", "data", "network", "operations"])
    error_message = "Expected one monitor group per component; storefront has two owning groups and still one group."
  }

  assert {
    condition     = toset(keys(output.on_call_policy_ids)) == toset(["storefront", "checkout", "data", "network", "operations"])
    error_message = "Expected one on-call policy per component, not one per component and group."
  }

  assert {
    condition     = toset(keys(output.monitor_group_memberships)) == toset(keys(output.monitor_ids))
    error_message = "Expected every monitor to join its component's monitor group."
  }

  assert {
    condition     = toset(keys(output.on_call_schedule_ids)) == toset(["checkout", "data"])
    error_message = "Expected a schedule only for the components that enable one."
  }

  assert {
    condition     = toset(keys(output.status_page_ids)) == toset(["public", "internal"])
    error_message = "Expected the public and the internal status page."
  }

  assert {
    condition = toset(keys(output.status_page_group_ids)) == toset([
      "public.shop", "public.checkout", "public.payments",
      "internal.storefront", "internal.checkout", "internal.data", "internal.infrastructure",
    ])
    error_message = "Expected every group of both status pages, keyed by page and group."
  }

  assert {
    condition = (
      toset(keys(nonsensitive(output.incoming_request_secret_keys))) == toset(["order-export", "nightly-backup"])
      && keys(nonsensitive(output.incoming_email_secret_keys)) == ["backup-report-email"]
      && keys(nonsensitive(output.server_monitor_secret_keys)) == ["db-host"]
    )
    error_message = "Expected the heartbeat, inbound email and agent keys of their own monitors, by slug."
  }

  assert {
    condition = toset(keys(module.teams_notifications.workflow_configs)) == toset([
      "alert-created", "alert-state-changed", "incident-created", "incident-state-changed", "monitor-status-changed",
    ])
    error_message = "Expected the five Teams template workflows."
  }

  assert {
    condition = toset(keys(output.workflow_ids)) == setunion(
      toset(keys(module.teams_notifications.workflow_configs)),
      toset(["major-incident-bridge", "monitor-offline-audit", "incident-state-audit"]),
    )
    error_message = "Expected the Teams template workflows merged with the custom ones."
  }
}

run "applies_with_every_id_wired" {
  command = apply

  variables {
    status_page_owner_user_ids = ["00000000-0000-4000-8000-000000000001"]
  }

  assert {
    condition = alltrue(concat(
      [for id in values(output.monitor_ids) : id != ""],
      [for id in values(output.status_page_ids) : id != ""],
      [for id in values(output.workflow_ids) : id != ""],
    ))
    error_message = "Every monitor, status page and workflow must have an id after apply."
  }

  assert {
    condition = alltrue(flatten([
      for component, slugs in local.component_monitors : [
        for slug in slugs : output.monitor_group_memberships[slug] == output.monitor_group_ids[component]
      ]
    ]))
    error_message = "Every monitor must be a member of its component's monitor group."
  }

  assert {
    condition = alltrue(concat(
      [for id in values(output.on_call_schedule_ids) : id != ""],
      [for id in values(output.status_page_group_ids) : id != ""],
      [for key in keys(output.status_page_group_ids) : contains(keys(output.status_page_ids), split(".", key)[0])],
    ))
    error_message = "Every schedule and status page group must have an id, and every group must sit on a declared page."
  }

  assert {
    condition = alltrue([
      for keys_by_slug in [output.incoming_request_secret_keys, output.incoming_email_secret_keys, output.server_monitor_secret_keys] :
      alltrue([for key in values(nonsensitive(keys_by_slug)) : key != ""])
    ])
    error_message = "Every heartbeat, inbound email and agent key must be read from its monitor."
  }

  assert {
    condition     = alltrue([for graph in values(module.oneuptime.workflow_graphs) : !strcontains(graph, "@@")])
    error_message = "Every @@token@@ must be replaced with the project's ids."
  }

  assert {
    condition     = strcontains(module.oneuptime.workflow_graphs["monitor-offline-audit"], "\"input-2\":\"status-offline\"")
    error_message = "@@monitor_status.offline@@ must become the project's Offline status id."
  }

  assert {
    condition = alltrue([
      for key in keys(module.teams_notifications.workflow_configs) :
      strcontains(module.oneuptime.workflow_graphs[key], "{{local.variables.teamsWebhookUrl}}")
    ])
    error_message = "Template workflows must read the webhook from their workflow variable."
  }

  assert {
    condition = !anytrue(flatten([
      for graph in values(module.oneuptime.workflow_graphs) : [
        for url in [var.teams_webhook_url, var.major_incident_webhook_url] : strcontains(graph, nonsensitive(url))
      ]
    ]))
    error_message = "A webhook URL must never be written into a workflow graph."
  }

  assert {
    condition = toset([
      for edge in jsondecode(module.oneuptime.workflow_graphs["major-incident-bridge"]).edges : edge.sourceHandle
    ]) == toset(["success", "yes", "no", "error"]) && length(jsondecode(module.oneuptime.workflow_graphs["major-incident-bridge"]).edges) == 4
    error_message = "The bridge must branch on severity, end the not-critical path and log delivery failures."
  }

  assert {
    condition = one([
      for node in jsondecode(module.oneuptime.workflow_graphs["major-incident-bridge"]).nodes : node.position
      if node.data.id == "log-not-critical"
    ]) == { x = 450, y = 600 }
    error_message = "A node with x and y must keep its canvas position."
  }

  assert {
    condition = (
      length(jsondecode(module.oneuptime.workflow_graphs["incident-state-audit"]).nodes) == 2
      && length(jsondecode(module.oneuptime.workflow_graphs["incident-state-audit"]).edges) == 1
    )
    error_message = "A raw graph must pass through unchanged."
  }

  assert {
    condition     = data.oneuptime_monitor_status.degraded.id == "status-degraded" && data.oneuptime_alert_severity.high.id == "alert-severity-high"
    error_message = "Hand-written criteria must resolve the stack's own status and severity lookups."
  }
}
