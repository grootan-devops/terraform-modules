// Unit tests for modules/monitors, called directly with the normalized inputs
// the parent module (modules/oneuptime) would pass it. No OneUptime instance or
// API key: the mock provider answers every call, so `command = apply` only
// builds state in memory.
mock_provider "oneuptime" {}

// Fixed ids for the status and severity lookups in data.tf, so a test can tell
// which one a criterion resolved to. They are read during plan as well.
override_data {
  target = data.oneuptime_monitor_status.operational
  values = { id = "status-operational" }
}

override_data {
  target = data.oneuptime_monitor_status.degraded
  values = { id = "status-degraded" }
}

override_data {
  target = data.oneuptime_monitor_status.offline
  values = { id = "status-offline" }
}

override_data {
  target = data.oneuptime_incident_severity.critical
  values = { id = "incident-severity-critical" }
}

override_data {
  target = data.oneuptime_incident_severity.major
  values = { id = "incident-severity-major" }
}

override_data {
  target = data.oneuptime_incident_severity.minor
  values = { id = "incident-severity-minor" }
}

override_data {
  target = data.oneuptime_alert_severity.high
  values = { id = "alert-severity-high" }
}

override_data {
  target = data.oneuptime_alert_severity.low
  values = { id = "alert-severity-low" }
}

variables {
  application = "core"

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

  monitors_component_mapping = {
    "platform"    = ["edge", "postgres", "tls", "runner", "backup", "maintenance", "multi-region"]
    "application" = ["api", "docs"]
  }

  monitor_configs = {
    // Every precedence level at once: a monitor-wide threshold, a per-criterion
    // threshold, a severity by name, an extra header and two extra criteria.
    "api" = {
      display_name = "Core API"
      description  = "Public API health endpoint"
      monitor_type = "API"
      target       = "https://api.example.com/health"

      step = {
        request_headers = { "Accept" = "application/json" }
      }

      thresholds = { response_time_ms = 2000 }

      criteria = {
        offline = {
          body_contains     = "OK"
          incident_severity = "major"
          remediation_notes = "Check the api deployment."
        }
        degraded = {
          response_time_ms = 3000
          alert_severity   = "high"
        }
      }

      extra_criteria = [
        {
          name                  = "Rate limited"
          filters               = [{ check_on = "Response Status Code", filter_type = "Equal To", value = "429" }]
          change_monitor_status = true
          monitor_status_id     = "status-degraded"
        },
        {
          name             = "Maintenance page"
          filter_condition = "Any"
          filters          = [{ check_on = "Response Status Code", filter_type = "Equal To", value = "503" }]
        },
      ]
    }

    // No display_name, so the slug names it.
    "docs" = {
      monitor_type = "Website"
      target       = "https://docs.example.com"
      thresholds   = { response_time_ms = 2000 }
    }

    "edge" = {
      display_name = "Edge gateway"
      monitor_type = "Ping"
      target       = "10.0.0.1"
      target_type  = "IP"
      thresholds   = { packet_loss_percent = 5 }
    }

    // Listed out of order on purpose: evaluation order comes from the preset.
    "postgres" = {
      display_name     = "PostgreSQL primary"
      monitor_type     = "Port"
      target           = "db.example.com"
      port             = 5432
      criteria_presets = ["operational", "offline"]
    }

    "tls" = {
      display_name        = "Web TLS certificate"
      monitor_type        = "SSL Certificate"
      target              = "https://www.example.com"
      monitoring_interval = "0 0 * * *"
      thresholds          = { certificate_expiry_days = 30 }
    }

    "runner" = {
      display_name = "Build runner"
      monitor_type = "Server"
      thresholds   = { disk_path = "/var", disk_percent = 80 }
    }

    "backup" = {
      display_name = "Nightly backup"
      monitor_type = "Incoming Request"
      thresholds   = { heartbeat_timeout_minutes = 1500 }
      criteria = {
        offline = {
          incident_severity = "minor"
          overrides = {
            incident_grouping = "{\"groupByJSONPath\":\"$.cluster\"}"
          }
        }
      }
    }

    "maintenance" = {
      display_name = "Datacenter migration"
      description  = "Tracked by hand during the migration window"
      monitor_type = "Manual"
    }

    // Hand-written steps: `target` is ignored, a step without criteria keeps
    // the generated ones, a step with criteria gets the criteria defaults.
    "multi-region" = {
      display_name = "Checkout API"
      monitor_type = "API"
      target       = "https://ignored.example.com"
      monitor_steps = [
        {
          monitor_destination      = "https://eu.api.example.com/health"
          monitor_destination_type = "URL"
          request_type             = "GET"
        },
        {
          monitor_destination      = "https://us.api.example.com/health"
          monitor_destination_type = "URL"
          request_type             = "GET"
          retry_count              = 1
          criteria = [
            {
              name    = "Down"
              filters = [{ check_on = "Is Online", filter_type = "False" }]
            },
          ]
        },
      ]
    }

    // Not in monitors_component_mapping, so never created.
    "unmapped" = {
      display_name = "Not mapped"
      monitor_type = "Manual"
    }
  }

  // monitor_defaults = {} after the parent's optional() defaults
  // (modules/oneuptime/variables-monitors.tf).
  monitor_defaults = {
    monitoring_interval       = "* * * * *"
    disable_active_monitoring = false
    minimum_probe_agreement   = 1
    monitor_step = {
      request_timeout_in_ms          = 5000
      retry_count                    = 3
      do_not_follow_redirects        = false
      allow_self_signed_certificates = false
      request_headers                = {}
    }
    criteria = {
      filter_condition = "All"
      is_enabled       = true
    }
    thresholds = {
      expected_status_code              = 200
      response_time_ms                  = 5000
      evaluate_over_time_minutes        = 15
      evaluate_over_time_type           = "Average"
      evaluate_over_time_no_data_policy = "Ignore"
      packet_loss_percent               = 10
      jitter_ms                         = 50
      certificate_expiry_days           = 21
      domain_expiry_days                = 30
      dnssec_expiry_days                = 7
      heartbeat_timeout_minutes         = 60
      execution_time_ms                 = 10000
      query_time_ms                     = 5000
      dns_response_time_ms              = 500
      cpu_percent                       = 90
      memory_percent                    = 90
      disk_percent                      = 85
      swap_percent                      = 50
      disk_path                         = "/"
    }
    severities = {
      incident = "critical"
      alert    = "low"
    }
  }
}

run "one_monitor_per_mapped_slug_and_one_rule_set_per_component" {
  command = plan

  assert {
    condition     = toset(keys(oneuptime_monitor.this)) == toset(["api", "docs", "edge", "postgres", "tls", "runner", "backup", "maintenance", "multi-region"])
    error_message = "Expected one monitor per slug in monitors_component_mapping, and none for the unmapped slug."
  }

  assert {
    condition = alltrue([
      for instances in [oneuptime_monitor_group.this, oneuptime_monitor_owner_rule.this, oneuptime_monitor_label_rule.this] :
      toset(keys(instances)) == toset(["platform", "application"])
    ])
    error_message = "Expected one monitor group, owner rule and label rule per component, not one per owning group."
  }
}

run "monitors_groups_and_rules_are_named_predictably" {
  command = plan

  assert {
    condition     = oneuptime_monitor.this["api"].name == "Core API"
    error_message = "A monitor should be named after its display_name."
  }

  assert {
    condition     = oneuptime_monitor.this["docs"].name == "docs"
    error_message = "A monitor without display_name should be named after its slug."
  }

  assert {
    condition     = oneuptime_monitor.this["api"].description == "Public API health endpoint"
    error_message = "A monitor's description should pass straight through."
  }

  assert {
    condition = alltrue(flatten([
      for key, _ in var.component_definitions : [
        oneuptime_monitor_group.this[key].name == key,
        oneuptime_monitor_owner_rule.this[key].name == key,
        oneuptime_monitor_label_rule.this[key].name == key,
      ]
    ]))
    error_message = "Monitor groups, owner rules and label rules should be named after their component."
  }

  assert {
    condition = (
      oneuptime_monitor_group.this["platform"].description == "monitor group for component platform"
      && oneuptime_monitor_owner_rule.this["platform"].description == "monitor owner rule for component platform"
      && oneuptime_monitor_label_rule.this["platform"].description == "monitor label rule for component platform"
    )
    error_message = "Monitor group and rule descriptions should be \"monitor <kind> for component <component>\"."
  }
}

run "monitors_carry_component_group_and_application_labels" {
  command = plan

  assert {
    condition     = oneuptime_monitor.this["api"].labels == toset(["label-application", "label-developers", "label-devops", "label-core"])
    error_message = "A monitor should carry its component label, every owning group's label and the application label."
  }

  assert {
    condition     = oneuptime_monitor.this["edge"].labels == toset(["label-platform", "label-devops", "label-core"])
    error_message = "A platform monitor should carry the platform, devops and core labels."
  }

  assert {
    condition     = oneuptime_monitor_group.this["application"].labels == toset(["label-application", "label-developers", "label-devops"])
    error_message = "A monitor group should carry the component label plus its group labels."
  }

  assert {
    condition     = oneuptime_monitor_owner_rule.this["application"].owner_teams == toset(["team-developers", "team-devops"])
    error_message = "A component owned by two groups should get one owner rule naming both teams."
  }

  assert {
    condition = alltrue([
      for key, rule in oneuptime_monitor_owner_rule.this :
      rule.monitor_labels == toset(["label-${key}"]) && rule.notify_owners && rule.is_enabled
    ])
    error_message = "Owner rules should match on the component label, be enabled and notify owners."
  }

  // Monitors already carry the component label (it is what the rule matches
  // on), so the label rule only adds the owning groups' labels - see main.tf.
  assert {
    condition     = oneuptime_monitor_label_rule.this["application"].labels_to_add == toset(["label-developers", "label-devops"])
    error_message = "The application label rule should add both owning groups' labels."
  }

  assert {
    condition = alltrue([
      for key, rule in oneuptime_monitor_label_rule.this :
      rule.monitor_labels == toset(["label-${key}"]) && rule.is_enabled
    ])
    error_message = "Label rules should be enabled and match on the component label."
  }
}

run "envelope_takes_the_defaults_unless_the_monitor_overrides_them" {
  command = plan

  assert {
    condition = (
      oneuptime_monitor.this["api"].monitoring_interval == "* * * * *"
      && oneuptime_monitor.this["api"].disable_active_monitoring == false
      && oneuptime_monitor.this["api"].minimum_probe_agreement == 1
    )
    error_message = "A monitor that sets nothing should take the monitor_defaults envelope."
  }

  assert {
    condition     = oneuptime_monitor.this["tls"].monitoring_interval == "0 0 * * *"
    error_message = "A monitor's own monitoring_interval should win over the default."
  }
}

run "api_monitor_step_and_criteria" {
  command = plan

  assert {
    condition = (
      oneuptime_monitor.this["api"].monitor_steps[0].monitor_destination == "https://api.example.com/health"
      && oneuptime_monitor.this["api"].monitor_steps[0].monitor_destination_type == "URL"
      && oneuptime_monitor.this["api"].monitor_steps[0].request_type == "GET"
      && oneuptime_monitor.this["api"].monitor_steps[0].request_timeout_in_ms == 5000
      && oneuptime_monitor.this["api"].monitor_steps[0].retry_count == 3
    )
    error_message = "An API monitor should get one GET step to its target with the default timeout and retries."
  }

  assert {
    condition     = length(oneuptime_monitor.this["api"].monitor_steps) == 1
    error_message = "A generated monitor should have exactly one step."
  }

  assert {
    condition = (
      oneuptime_monitor.this["api"].monitor_steps[0].do_not_follow_redirects == null
      && oneuptime_monitor.this["api"].monitor_steps[0].allow_self_signed_certificates == null
    )
    error_message = "do_not_follow_redirects and allow_self_signed_certificates should be omitted when false."
  }

  assert {
    condition     = oneuptime_monitor.this["api"].monitor_steps[0].request_headers == tomap({ "Accept" = "application/json" })
    error_message = "The monitor's own request_headers should be sent."
  }

  assert {
    condition     = [for c in oneuptime_monitor.this["api"].monitor_steps[0].criteria : c.name] == ["Offline", "Degraded", "Rate limited", "Maintenance page", "Operational"]
    error_message = "Criteria should run offline, degraded, the extra criteria in listed order, then operational."
  }

  assert {
    condition = [for f in oneuptime_monitor.this["api"].monitor_steps[0].criteria[0].filters : [f.check_on, f.filter_type, coalesce(f.value, "-")]] == [
      ["Is Online", "False", "-"],
      ["Response Status Code", "Not Equal To", "200"],
      ["Is Request Timeout", "True", "-"],
      ["Response Body", "Not Contains", "OK"],
    ]
    error_message = "Offline should fail on offline, a non-200 status, a timeout, or a body missing body_contains."
  }

  assert {
    condition = (
      oneuptime_monitor.this["api"].monitor_steps[0].criteria[0].filter_condition == "Any"
      && oneuptime_monitor.this["api"].monitor_steps[0].criteria[0].description == "Core API is unreachable or failing its health check"
      && oneuptime_monitor.this["api"].monitor_steps[0].criteria[0].change_monitor_status == true
      && oneuptime_monitor.this["api"].monitor_steps[0].criteria[0].monitor_status_id == "status-offline"
      && oneuptime_monitor.this["api"].monitor_steps[0].criteria[0].create_incidents == true
      && oneuptime_monitor.this["api"].monitor_steps[0].criteria[0].is_enabled == true
    )
    error_message = "Offline should match on Any filter, flip the status to Offline and create an incident."
  }

  assert {
    condition = (
      oneuptime_monitor.this["api"].monitor_steps[0].criteria[0].incidents[0].title == "Core API is offline"
      && oneuptime_monitor.this["api"].monitor_steps[0].criteria[0].incidents[0].description == "Core API failed its API check."
      && oneuptime_monitor.this["api"].monitor_steps[0].criteria[0].incidents[0].incident_severity_id == "incident-severity-major"
      && oneuptime_monitor.this["api"].monitor_steps[0].criteria[0].incidents[0].remediation_notes == "Check the api deployment."
      && oneuptime_monitor.this["api"].monitor_steps[0].criteria[0].incidents[0].auto_resolve_incident == true
      && oneuptime_monitor.this["api"].monitor_steps[0].criteria[0].incidents[0].show_incident_on_status_page == true
      && oneuptime_monitor.this["api"].monitor_steps[0].criteria[0].incidents[0].is_private == false
    )
    error_message = "The offline incident should use the generated title/description, the major severity id and the remediation notes."
  }

  assert {
    condition = (
      oneuptime_monitor.this["api"].monitor_steps[0].criteria[1].filter_condition == "All"
      && oneuptime_monitor.this["api"].monitor_steps[0].criteria[1].monitor_status_id == "status-degraded"
      && oneuptime_monitor.this["api"].monitor_steps[0].criteria[1].create_alerts == true
    )
    error_message = "Degraded should match on All filters, flip the status to Degraded and create an alert."
  }

  assert {
    condition = [for f in oneuptime_monitor.this["api"].monitor_steps[0].criteria[1].filters : [f.check_on, f.filter_type, f.value]] == [
      ["Response Status Code", "Equal To", "200"],
      ["Response Time (in ms)", "Greater Than", "3000"],
    ]
    error_message = "Degraded should compare the response time against the criterion's 3000, over the monitor's 2000 and the default 5000."
  }

  assert {
    condition = (
      oneuptime_monitor.this["api"].monitor_steps[0].criteria[1].filters[1].evaluate_over_time == true
      && oneuptime_monitor.this["api"].monitor_steps[0].criteria[1].filters[1].evaluate_over_time_minutes == 15
      && oneuptime_monitor.this["api"].monitor_steps[0].criteria[1].filters[1].evaluate_over_time_type == "Average"
      && oneuptime_monitor.this["api"].monitor_steps[0].criteria[1].filters[1].evaluate_over_time_no_data_policy == "Ignore"
    )
    error_message = "The response time filter should be averaged over 15 minutes, ignoring missing data."
  }

  assert {
    condition = (
      oneuptime_monitor.this["api"].monitor_steps[0].criteria[1].alerts[0].title == "Core API is degraded"
      && oneuptime_monitor.this["api"].monitor_steps[0].criteria[1].alerts[0].description == "Core API responded outside its expected thresholds."
      && oneuptime_monitor.this["api"].monitor_steps[0].criteria[1].alerts[0].alert_severity_id == "alert-severity-high"
      && oneuptime_monitor.this["api"].monitor_steps[0].criteria[1].alerts[0].auto_resolve_alert == true
    )
    error_message = "The degraded alert should use the generated title/description and the high severity id."
  }

  assert {
    condition = (
      oneuptime_monitor.this["api"].monitor_steps[0].criteria[4].description == "Core API is healthy"
      && oneuptime_monitor.this["api"].monitor_steps[0].criteria[4].change_monitor_status == true
      && oneuptime_monitor.this["api"].monitor_steps[0].criteria[4].monitor_status_id == "status-operational"
      && oneuptime_monitor.this["api"].monitor_steps[0].criteria[4].create_incidents == false
      && oneuptime_monitor.this["api"].monitor_steps[0].criteria[4].create_alerts == false
    )
    error_message = "Operational should be able to flip the status back to Operational and create nothing."
  }

  assert {
    condition = [for f in oneuptime_monitor.this["api"].monitor_steps[0].criteria[4].filters : [f.check_on, f.filter_type, coalesce(f.value, "-")]] == [
      ["Is Online", "True", "-"],
      ["Response Status Code", "Equal To", "200"],
    ]
    error_message = "Operational should require the monitor online with the expected status code."
  }

  assert {
    condition = (
      oneuptime_monitor.this["api"].monitor_steps[0].criteria[2].filter_condition == "All"
      && oneuptime_monitor.this["api"].monitor_steps[0].criteria[2].is_enabled == true
      && oneuptime_monitor.this["api"].monitor_steps[0].criteria[2].monitor_status_id == "status-degraded"
      && oneuptime_monitor.this["api"].monitor_steps[0].criteria[2].filters[0].value == "429"
      && oneuptime_monitor.this["api"].monitor_steps[0].criteria[3].filter_condition == "Any"
    )
    error_message = "Extra criteria should be passed through with the criteria defaults underneath their own values."
  }

  // Each preset creates exactly what the README promises: Offline an incident,
  // Degraded an alert, Operational nothing. An absent incidents/alerts block is
  // unknown on the planned resource, so the blocks are read from the rendered
  // criteria.
  assert {
    condition = (
      oneuptime_monitor.this["api"].monitor_steps[0].criteria[0].create_alerts == false
      && !contains(keys(local.monitor_criteria["api"][0]), "alerts")
    )
    error_message = "Offline must open an incident only, not raise an alert as well."
  }

  assert {
    condition = (
      oneuptime_monitor.this["api"].monitor_steps[0].criteria[1].create_incidents == false
      && !contains(keys(local.monitor_criteria["api"][1]), "incidents")
    )
    error_message = "Degraded must raise an alert only, not open an incident as well."
  }

  assert {
    condition = (
      !contains(keys(local.monitor_criteria["api"][4]), "incidents")
      && !contains(keys(local.monitor_criteria["api"][4]), "alerts")
    )
    error_message = "Operational must carry neither an incidents nor an alerts block."
  }
}

run "criteria_flags_override_what_the_preset_creates" {
  command = plan

  variables {
    monitors_component_mapping = { "application" = ["docs"] }
    monitor_configs = {
      "docs" = {
        display_name = "Docs"
        monitor_type = "Website"
        target       = "https://docs.example.com"
        criteria = {
          offline     = { create_incidents = false, create_alerts = true }
          degraded    = { create_incidents = true }
          operational = { create_incidents = true, create_alerts = true }
        }
      }
    }
  }

  assert {
    condition = (
      local.monitor_criteria["docs"][0].create_incidents == false
      && !contains(keys(local.monitor_criteria["docs"][0]), "incidents")
      && local.monitor_criteria["docs"][0].create_alerts == true
      && length(local.monitor_criteria["docs"][0].alerts) == 1
    )
    error_message = "criteria.offline can swap the incident for an alert."
  }

  assert {
    condition = (
      local.monitor_criteria["docs"][1].create_incidents == true
      && length(local.monitor_criteria["docs"][1].incidents) == 1
      && local.monitor_criteria["docs"][1].create_alerts == true
      && length(local.monitor_criteria["docs"][1].alerts) == 1
    )
    error_message = "criteria.degraded can open an incident on top of its alert."
  }

  assert {
    condition = (
      local.monitor_criteria["docs"][2].create_incidents == false
      && local.monitor_criteria["docs"][2].create_alerts == false
      && !contains(keys(local.monitor_criteria["docs"][2]), "incidents")
      && !contains(keys(local.monitor_criteria["docs"][2]), "alerts")
    )
    error_message = "Operational is the recovery criterion and never creates an incident or an alert, whatever it is asked."
  }
}

run "website_monitor_takes_monitor_thresholds_and_default_severities" {
  command = plan

  assert {
    condition = (
      oneuptime_monitor.this["docs"].monitor_steps[0].monitor_destination_type == "URL"
      && oneuptime_monitor.this["docs"].monitor_steps[0].request_type == null
      && oneuptime_monitor.this["docs"].monitor_steps[0].request_headers == null
    )
    error_message = "A Website step should be a URL destination with no request verb and, with no headers anywhere, no request_headers."
  }

  assert {
    condition     = oneuptime_monitor.this["docs"].monitor_steps[0].criteria[1].filters[1].value == "2000"
    error_message = "The monitor's thresholds.response_time_ms should win over the default."
  }

  assert {
    condition = (
      oneuptime_monitor.this["docs"].monitor_steps[0].criteria[0].incidents[0].incident_severity_id == "incident-severity-critical"
      && oneuptime_monitor.this["docs"].monitor_steps[0].criteria[1].alerts[0].alert_severity_id == "alert-severity-low"
      && oneuptime_monitor.this["docs"].monitor_steps[0].criteria[0].incidents[0].title == "docs is offline"
    )
    error_message = "Without overrides the offline incident should be critical, the degraded alert low, and the slug the subject."
  }

  assert {
    condition     = length(oneuptime_monitor.this["docs"].monitor_steps[0].criteria[0].filters) == 3
    error_message = "Without body_contains there should be no Response Body filter."
  }
}

run "ping_monitor_criteria" {
  command = plan

  assert {
    condition = (
      oneuptime_monitor.this["edge"].monitor_steps[0].monitor_destination == "10.0.0.1"
      && oneuptime_monitor.this["edge"].monitor_steps[0].monitor_destination_type == "IP"
      && oneuptime_monitor.this["edge"].monitor_steps[0].request_type == null
      && oneuptime_monitor.this["edge"].monitor_steps[0].request_headers == null
    )
    error_message = "A Ping step should probe its target, take target_type over the Hostname default, and send no HTTP fields."
  }

  assert {
    condition = [for f in oneuptime_monitor.this["edge"].monitor_steps[0].criteria[0].filters : [f.check_on, f.filter_type]] == [
      ["Is Online", "False"],
      ["Is Request Timeout", "True"],
    ]
    error_message = "Ping offline should fail on offline or timeout."
  }

  assert {
    condition = [for f in oneuptime_monitor.this["edge"].monitor_steps[0].criteria[1].filters : [f.check_on, f.filter_type, f.value]] == [
      ["Packet Loss (in %)", "Greater Than", "5"],
      ["Jitter (in ms)", "Greater Than", "50"],
      ["Response Time (in ms)", "Greater Than", "5000"],
    ]
    error_message = "Ping degraded should use the monitor's packet loss and the default jitter and response time."
  }

  assert {
    condition     = [for f in oneuptime_monitor.this["edge"].monitor_steps[0].criteria[2].filters : [f.check_on, f.filter_type]] == [["Is Online", "True"]]
    error_message = "Ping operational should require the target online."
  }
}

run "port_monitor_with_narrowed_presets" {
  command = plan

  assert {
    condition = (
      oneuptime_monitor.this["postgres"].monitor_steps[0].monitor_destination == "db.example.com"
      && oneuptime_monitor.this["postgres"].monitor_steps[0].monitor_destination_type == "Hostname"
      && oneuptime_monitor.this["postgres"].monitor_steps[0].port == 5432
    )
    error_message = "A Port step should probe its hostname on its port."
  }

  assert {
    condition     = [for c in oneuptime_monitor.this["postgres"].monitor_steps[0].criteria : c.name] == ["Offline", "Operational"]
    error_message = "criteria_presets should narrow the set, and order should follow the preset, not the listing."
  }

  assert {
    condition = [for f in oneuptime_monitor.this["postgres"].monitor_steps[0].criteria[0].filters : [f.check_on, f.filter_type]] == [
      ["Is Online", "False"],
      ["Is Request Timeout", "True"],
    ]
    error_message = "Port offline should fail on offline or timeout."
  }
}

run "ssl_certificate_monitor_criteria" {
  command = plan

  assert {
    condition = (
      oneuptime_monitor.this["tls"].monitor_steps[0].monitor_destination == "https://www.example.com"
      && oneuptime_monitor.this["tls"].monitor_steps[0].monitor_destination_type == "URL"
    )
    error_message = "An SSL Certificate step should probe its URL."
  }

  assert {
    condition = [for f in oneuptime_monitor.this["tls"].monitor_steps[0].criteria[0].filters : f.check_on] == [
      "Is Expired Certificate",
      "Is Not A Valid Certificate",
      "Is Self Signed Certificate",
    ]
    error_message = "SSL offline should fail on an expired, invalid or self-signed certificate."
  }

  assert {
    condition = [for f in oneuptime_monitor.this["tls"].monitor_steps[0].criteria[1].filters : [f.check_on, f.filter_type, f.value]] == [
      ["Expires In Days", "Less Than", "30"],
    ]
    error_message = "SSL degraded should use the monitor's certificate_expiry_days."
  }

  assert {
    condition     = [for f in oneuptime_monitor.this["tls"].monitor_steps[0].criteria[2].filters : f.check_on] == ["Is Valid Certificate"]
    error_message = "SSL operational should require a valid certificate."
  }
}

run "server_monitor_criteria" {
  command = plan

  assert {
    condition = (
      oneuptime_monitor.this["runner"].monitor_steps[0].monitor_destination == null
      && oneuptime_monitor.this["runner"].monitor_steps[0].monitor_destination_type == null
      && oneuptime_monitor.this["runner"].monitor_steps[0].retry_count == 3
    )
    error_message = "A Server step should have no destination but still take the step defaults."
  }

  assert {
    condition = [for f in oneuptime_monitor.this["runner"].monitor_steps[0].criteria[1].filters : [f.check_on, f.value, coalesce(f.disk_path, "-")]] == [
      ["CPU Usage (in %)", "90", "-"],
      ["Memory Usage (in %)", "90", "-"],
      ["Swap Usage (in %)", "50", "-"],
      ["Disk Usage (in %)", "80", "/var"],
    ]
    error_message = "Server degraded should use the default CPU/memory/swap thresholds and the monitor's disk threshold and path."
  }
}

run "incoming_request_heartbeat_criteria" {
  command = plan

  assert {
    condition     = [for c in oneuptime_monitor.this["backup"].monitor_steps[0].criteria : c.name] == ["Offline", "Operational"]
    error_message = "A heartbeat monitor has no degraded preset."
  }

  assert {
    condition = (
      oneuptime_monitor.this["backup"].monitor_steps[0].criteria[0].filters[0].filter_type == "Not Recieved In Minutes"
      && oneuptime_monitor.this["backup"].monitor_steps[0].criteria[0].filters[0].value == "1500"
      && oneuptime_monitor.this["backup"].monitor_steps[0].criteria[1].filters[0].filter_type == "Recieved In Minutes"
      && oneuptime_monitor.this["backup"].monitor_steps[0].criteria[1].filters[0].value == "1500"
    )
    error_message = "Both heartbeat criteria should read the monitor-wide window, with the upstream spelling."
  }

  assert {
    condition     = oneuptime_monitor.this["backup"].monitor_steps[0].criteria[0].incidents[0].incident_severity_id == "incident-severity-minor"
    error_message = "A criterion's incident_severity should resolve to that severity's id."
  }

  assert {
    condition     = oneuptime_monitor.this["backup"].monitor_steps[0].criteria[0].incident_grouping == "{\"groupByJSONPath\":\"$.cluster\"}"
    error_message = "criteria.<preset>.overrides should be merged over the finished criterion."
  }
}

// A null monitor_steps is unknown in a mock plan (the attribute is computed),
// so this checks the steps the conditional in main.tf reads.
run "manual_monitor_has_no_steps" {
  command = plan

  assert {
    condition     = local.monitor_steps["maintenance"] == []
    error_message = "A Manual monitor should generate no steps."
  }

  assert {
    condition     = length(local.monitor_criteria["maintenance"]) == 0
    error_message = "A Manual monitor should generate no criteria."
  }

  assert {
    condition = (
      oneuptime_monitor.this["maintenance"].name == "Datacenter migration"
      && oneuptime_monitor.this["maintenance"].monitor_type == "Manual"
      && oneuptime_monitor.this["maintenance"].description == "Tracked by hand during the migration window"
    )
    error_message = "A Manual monitor should still be created with its name, type and description."
  }
}

run "explicit_monitor_steps_replace_generation" {
  command = plan

  assert {
    condition = [for step in oneuptime_monitor.this["multi-region"].monitor_steps : step.monitor_destination] == [
      "https://eu.api.example.com/health",
      "https://us.api.example.com/health",
    ]
    error_message = "Hand-written steps should be sent as written, ignoring `target`."
  }

  assert {
    condition = (
      oneuptime_monitor.this["multi-region"].monitor_steps[0].retry_count == 3
      && oneuptime_monitor.this["multi-region"].monitor_steps[1].retry_count == 1
    )
    error_message = "Step defaults should sit underneath a hand-written step's own values."
  }

  assert {
    condition     = [for c in oneuptime_monitor.this["multi-region"].monitor_steps[0].criteria : c.name] == ["Offline", "Degraded", "Operational"]
    error_message = "A hand-written step without criteria should pick up the generated ones."
  }

  assert {
    condition = (
      [for c in oneuptime_monitor.this["multi-region"].monitor_steps[1].criteria : c.name] == ["Down"]
      && oneuptime_monitor.this["multi-region"].monitor_steps[1].criteria[0].filter_condition == "All"
      && oneuptime_monitor.this["multi-region"].monitor_steps[1].criteria[0].is_enabled == true
    )
    error_message = "A hand-written step's criteria should be kept, with the criteria defaults underneath."
  }
}

run "stack_defaults_sit_under_monitor_and_criterion_values" {
  command = plan

  variables {
    monitor_defaults = {
      monitoring_interval       = "*/5 * * * *"
      disable_active_monitoring = false
      minimum_probe_agreement   = 2
      monitor_step = {
        request_timeout_in_ms          = 10000
        retry_count                    = 2
        do_not_follow_redirects        = false
        allow_self_signed_certificates = true
        request_headers = {
          "User-Agent" = "probe/core"
          "Accept"     = "text/plain"
        }
      }
      criteria = {
        filter_condition = "Any"
        is_enabled       = true
      }
      thresholds = {
        expected_status_code              = 200
        response_time_ms                  = 1500
        evaluate_over_time_minutes        = 15
        evaluate_over_time_type           = "Average"
        evaluate_over_time_no_data_policy = "Ignore"
        packet_loss_percent               = 10
        jitter_ms                         = 50
        certificate_expiry_days           = 21
        domain_expiry_days                = 30
        dnssec_expiry_days                = 7
        heartbeat_timeout_minutes         = 60
        execution_time_ms                 = 10000
        query_time_ms                     = 5000
        dns_response_time_ms              = 500
        cpu_percent                       = 90
        memory_percent                    = 90
        disk_percent                      = 85
        swap_percent                      = 50
        disk_path                         = "/"
      }
      severities = {
        incident = "minor"
        alert    = "high"
      }
    }
  }

  assert {
    condition = (
      oneuptime_monitor.this["api"].monitoring_interval == "*/5 * * * *"
      && oneuptime_monitor.this["api"].minimum_probe_agreement == 2
      && oneuptime_monitor.this["tls"].monitoring_interval == "0 0 * * *"
    )
    error_message = "The stack envelope should apply unless the monitor sets its own."
  }

  assert {
    condition = (
      oneuptime_monitor.this["edge"].monitor_steps[0].criteria[1].filters[2].value == "1500"
      && oneuptime_monitor.this["docs"].monitor_steps[0].criteria[1].filters[1].value == "2000"
      && oneuptime_monitor.this["api"].monitor_steps[0].criteria[1].filters[1].value == "3000"
    )
    error_message = "Response time should resolve stack 1500 < monitor thresholds 2000 < criterion 3000."
  }

  assert {
    condition     = oneuptime_monitor.this["api"].monitor_steps[0].request_headers == tomap({ "User-Agent" = "probe/core", "Accept" = "application/json" })
    error_message = "request_headers should deep-merge: the stack's User-Agent kept, the monitor's Accept winning."
  }

  assert {
    condition     = oneuptime_monitor.this["docs"].monitor_steps[0].request_headers == tomap({ "User-Agent" = "probe/core", "Accept" = "text/plain" })
    error_message = "A Website monitor with no headers of its own should get the stack's headers."
  }

  assert {
    condition     = oneuptime_monitor.this["multi-region"].monitor_steps[0].request_headers == tomap({ "User-Agent" = "probe/core", "Accept" = "text/plain" })
    error_message = "Hand-written API steps should get the stack's headers too."
  }

  assert {
    condition = (
      oneuptime_monitor.this["runner"].monitor_steps[0].request_headers == null
      && oneuptime_monitor.this["edge"].monitor_steps[0].request_headers == null
      && oneuptime_monitor.this["backup"].monitor_steps[0].request_headers == null
    )
    error_message = "Stack request_headers should only reach monitor types that issue an HTTP request."
  }

  assert {
    condition = alltrue([
      for key in ["api", "docs", "edge", "runner"] :
      oneuptime_monitor.this[key].monitor_steps[0].request_timeout_in_ms == 10000
      && oneuptime_monitor.this[key].monitor_steps[0].retry_count == 2
      && oneuptime_monitor.this[key].monitor_steps[0].allow_self_signed_certificates == true
      && oneuptime_monitor.this[key].monitor_steps[0].do_not_follow_redirects == null
    ])
    error_message = "Stack step defaults should reach every generated step, sending the flags only when true."
  }

  assert {
    condition = (
      oneuptime_monitor.this["docs"].monitor_steps[0].criteria[0].incidents[0].incident_severity_id == "incident-severity-minor"
      && oneuptime_monitor.this["docs"].monitor_steps[0].criteria[1].alerts[0].alert_severity_id == "alert-severity-high"
      && oneuptime_monitor.this["api"].monitor_steps[0].criteria[0].incidents[0].incident_severity_id == "incident-severity-major"
    )
    error_message = "Stack severities should apply unless a criterion names its own."
  }

  assert {
    condition     = oneuptime_monitor.this["api"].monitor_steps[0].criteria[2].filter_condition == "Any"
    error_message = "An extra criterion without filter_condition should take the stack's criteria.filter_condition."
  }
}

run "outputs_expose_the_created_ids" {
  command = apply

  assert {
    condition     = output.monitor_ids == { for key, monitor in oneuptime_monitor.this : key => monitor.id }
    error_message = "monitor_ids should map every monitor slug to its id."
  }

  assert {
    condition     = output.monitor_group_ids == { for key, group in oneuptime_monitor_group.this : key => group.id }
    error_message = "monitor_group_ids should map every component to its monitor group id."
  }

  assert {
    condition = output.monitor_status_ids == {
      operational = "status-operational"
      degraded    = "status-degraded"
      offline     = "status-offline"
    }
    error_message = "monitor_status_ids should expose the three monitor status ids by name."
  }
}
