// Criteria are the bulk of a monitor, and across monitor types they are the
// same shape every time: worst case first, each one flipping the monitor status
// and optionally opening an incident or an alert. Only the *filters* actually
// differ per monitor type, and within a type only the threshold values differ
// per monitor.
//
// So the envelope is built once, generically, at the bottom of this file, and
// the catalogue in the middle carries nothing but the filters. A monitor names
// the presets it wants (or takes the default set for its type) and supplies
// values; everything else is derived.

locals {
  // -------------------------------------------------------------------------
  // The catalogue index
  //
  // Which presets exist per monitor type, in evaluation order. Doubles as the
  // default criteria set: a monitor that says nothing gets all of them.
  // A type that is not listed here has no presets - such a monitor writes its
  // own monitor_steps.
  // -------------------------------------------------------------------------
  criteria_presets_by_type = {
    "API"                    = ["offline", "degraded", "operational"]
    "Website"                = ["offline", "degraded", "operational"]
    "Ping"                   = ["offline", "degraded", "operational"]
    "IP"                     = ["offline", "degraded", "operational"]
    "Port"                   = ["offline", "degraded", "operational"]
    "SSL Certificate"        = ["offline", "degraded", "operational"]
    "Server"                 = ["offline", "degraded", "operational"]
    "Custom JavaScript Code" = ["offline", "degraded", "operational"]
    "Synthetic Monitor"      = ["offline", "degraded", "operational"]
    "DNS"                    = ["offline", "degraded", "operational"]
    "DNSSEC"                 = ["offline", "degraded", "operational"]
    "Domain"                 = ["offline", "degraded", "operational"]
    "SQL Query"              = ["offline", "degraded", "operational"]
    "Incoming Request"       = ["offline", "operational"]
    "Incoming Email"         = ["offline", "operational"]
    "Manual"                 = []
  }

  // What a preset means, independent of monitor type. `order` is what makes
  // criteria evaluate worst-case first no matter which presets a monitor picked
  // or what order it listed them in - first match wins server-side.
  criteria_preset_defaults = {
    offline = {
      order            = 10
      name             = "Offline"
      summary          = "is unreachable or failing its health check"
      monitor_status   = "offline"
      filter_condition = "Any"
      creates          = "incident"
    }
    degraded = {
      order            = 20
      name             = "Degraded"
      summary          = "is responding, but outside its expected thresholds"
      monitor_status   = "degraded"
      filter_condition = "All"
      creates          = "alert"
    }
    operational = {
      order            = 90
      name             = "Operational"
      summary          = "is healthy"
      monitor_status   = "operational"
      filter_condition = "All"
      creates          = "nothing"
    }
  }

  // Every value a preset can read, with the project-wide thresholds underneath.
  // Defaulting them here is what allows the catalogue below to use plain
  // attribute access - a preset never has to guard against an unset key.
  criteria_param_defaults = merge(var.monitor_defaults.thresholds, {
    // Envelope overrides, null meaning "derive it".
    name              = null
    description       = null
    filter_condition  = null
    is_enabled        = null
    body_contains     = null
    remediation_notes = null

    // null, so the preset decides what it creates (see criteria_creates);
    // `true` here made every preset open an incident and raise an alert.
    incident_severity    = var.monitor_defaults.severities.incident
    incident_title       = null
    incident_description = null
    create_incidents     = null

    alert_severity    = var.monitor_defaults.severities.alert
    alert_title       = null
    alert_description = null
    create_alerts     = null

    // Last-word escape hatch, merged over the finished criterion.
    overrides = {}
  })

  // One context per (monitor, preset), so the catalogue and the envelope below
  // are written once against `ctx` rather than once per monitor.
  criteria_contexts = flatten([
    for key, spec in local.monitor_specs : [
      for preset in spec.criteria_presets : {
        id           = format("%s~%03d~%s", key, local.criteria_preset_defaults[preset].order, preset)
        monitor      = key
        preset       = preset
        monitor_type = spec.monitor_type
        display_name = spec.display_name
        // Three levels, lowest first: the project's thresholds, the
        // monitor's, then this criterion's own values.
        params = merge(
          local.criteria_param_defaults,
          spec.thresholds,
          try(spec.criteria[preset], {}),
        )
      }
    ]
  ])

  // -------------------------------------------------------------------------
  // The catalogue
  //
  // monitor type -> preset -> filters. The only part of a criterion that is
  // genuinely type-specific. `p` is the monitor's values merged over the
  // project thresholds, so every threshold below is overridable per monitor
  // without the catalogue knowing about it.
  // -------------------------------------------------------------------------
  criteria_filters = {
    for ctx in local.criteria_contexts : ctx.id => try({
      "API" = local.http_criteria_filters[ctx.id]

      "Website" = local.http_criteria_filters[ctx.id]

      "Ping" = local.icmp_criteria_filters[ctx.id]

      "IP" = local.icmp_criteria_filters[ctx.id]

      "Port" = {
        offline = [
          { check_on = "Is Online", filter_type = "False" },
          { check_on = "Is Request Timeout", filter_type = "True" },
        ]
        degraded = [
          { check_on = "Response Time (in ms)", filter_type = "Greater Than", value = tostring(ctx.params.response_time_ms) },
        ]
        operational = [
          { check_on = "Is Online", filter_type = "True" },
        ]
      }

      "SSL Certificate" = {
        offline = [
          { check_on = "Is Expired Certificate", filter_type = "True" },
          { check_on = "Is Not A Valid Certificate", filter_type = "True" },
          { check_on = "Is Self Signed Certificate", filter_type = "True" },
        ]
        degraded = [
          { check_on = "Expires In Days", filter_type = "Less Than", value = tostring(ctx.params.certificate_expiry_days) },
        ]
        operational = [
          { check_on = "Is Valid Certificate", filter_type = "True" },
        ]
      }

      "Server" = {
        offline = [
          { check_on = "Is Online", filter_type = "False" },
        ]
        degraded = [
          { check_on = "CPU Usage (in %)", filter_type = "Greater Than", value = tostring(ctx.params.cpu_percent) },
          { check_on = "Memory Usage (in %)", filter_type = "Greater Than", value = tostring(ctx.params.memory_percent) },
          { check_on = "Swap Usage (in %)", filter_type = "Greater Than", value = tostring(ctx.params.swap_percent) },
          { check_on = "Disk Usage (in %)", filter_type = "Greater Than", value = tostring(ctx.params.disk_percent), disk_path = ctx.params.disk_path },
        ]
        operational = [
          { check_on = "Is Online", filter_type = "True" },
        ]
      }

      "Custom JavaScript Code" = local.script_criteria_filters[ctx.id]

      "Synthetic Monitor" = local.script_criteria_filters[ctx.id]

      "DNS" = {
        offline = [
          { check_on = "DNS Is Online", filter_type = "False" },
          { check_on = "DNS Record Exists", filter_type = "False" },
        ]
        degraded = [
          { check_on = "DNS Response Time (in ms)", filter_type = "Greater Than", value = tostring(ctx.params.dns_response_time_ms) },
        ]
        operational = [
          { check_on = "DNS Is Online", filter_type = "True" },
        ]
      }

      "DNSSEC" = {
        offline = [
          { check_on = "DNSSEC Chain Is Valid", filter_type = "False" },
          { check_on = "DNSSEC DNSKEY Record Exists", filter_type = "False" },
          { check_on = "DNSSEC DS Record Exists At Parent", filter_type = "False" },
          { check_on = "DNSSEC Resolver Consensus (AD Flag)", filter_type = "False" },
        ]
        degraded = [
          { check_on = "DNSSEC Signature Expires In Days", filter_type = "Less Than", value = tostring(ctx.params.dnssec_expiry_days) },
        ]
        operational = [
          { check_on = "DNSSEC Chain Is Valid", filter_type = "True" },
        ]
      }

      "Domain" = {
        offline = [
          { check_on = "Domain Is Expired", filter_type = "True" },
        ]
        degraded = [
          { check_on = "Domain Expires In Days", filter_type = "Less Than", value = tostring(ctx.params.domain_expiry_days) },
        ]
        operational = [
          { check_on = "Domain Is Expired", filter_type = "False" },
        ]
      }

      "SQL Query" = {
        offline = [
          { check_on = "SQL Is Online", filter_type = "False" },
          { check_on = "SQL Query Error", filter_type = "Is Not Empty" },
        ]
        degraded = [
          { check_on = "SQL Query Execution Time (in ms)", filter_type = "Greater Than", value = tostring(ctx.params.query_time_ms) },
        ]
        operational = [
          { check_on = "SQL Is Online", filter_type = "True" },
        ]
      }

      // Heartbeats: the monitor is offline when nothing arrived inside the
      // window, and operational when something did. "Recieved" is misspelled
      // upstream and has to be passed through as-is.
      "Incoming Request" = {
        offline = [
          { check_on = "Incoming Request", filter_type = "Not Recieved In Minutes", value = tostring(ctx.params.heartbeat_timeout_minutes) },
        ]
        operational = [
          { check_on = "Incoming Request", filter_type = "Recieved In Minutes", value = tostring(ctx.params.heartbeat_timeout_minutes) },
        ]
      }

      "Incoming Email" = {
        offline = [
          { check_on = "Email Received", filter_type = "Not Recieved In Minutes", value = tostring(ctx.params.heartbeat_timeout_minutes) },
        ]
        operational = [
          { check_on = "Email Received", filter_type = "Recieved In Minutes", value = tostring(ctx.params.heartbeat_timeout_minutes) },
        ]
      }
    }[ctx.monitor_type][ctx.preset], [])
  }

  // API and Website probe the same way, so their filters are shared rather than
  // written twice. Same for Ping/IP and for the two script-driven types.
  http_criteria_filters = {
    for ctx in local.criteria_contexts : ctx.id => {
      offline = concat(
        [
          { check_on = "Is Online", filter_type = "False" },
          { check_on = "Response Status Code", filter_type = "Not Equal To", value = tostring(ctx.params.expected_status_code) },
          { check_on = "Is Request Timeout", filter_type = "True" },
        ],
        // Only worth a filter when the monitor says what a healthy body says.
        ctx.params.body_contains == null ? [] : [
          { check_on = "Response Body", filter_type = "Not Contains", value = ctx.params.body_contains },
        ],
      )
      degraded = [
        { check_on = "Response Status Code", filter_type = "Equal To", value = tostring(ctx.params.expected_status_code) },
        {
          check_on                          = "Response Time (in ms)"
          filter_type                       = "Greater Than"
          value                             = tostring(ctx.params.response_time_ms)
          evaluate_over_time                = true
          evaluate_over_time_minutes        = ctx.params.evaluate_over_time_minutes
          evaluate_over_time_type           = ctx.params.evaluate_over_time_type
          evaluate_over_time_no_data_policy = ctx.params.evaluate_over_time_no_data_policy
        },
      ]
      operational = [
        { check_on = "Is Online", filter_type = "True" },
        { check_on = "Response Status Code", filter_type = "Equal To", value = tostring(ctx.params.expected_status_code) },
      ]
    }
  }

  icmp_criteria_filters = {
    for ctx in local.criteria_contexts : ctx.id => {
      offline = [
        { check_on = "Is Online", filter_type = "False" },
        { check_on = "Is Request Timeout", filter_type = "True" },
      ]
      degraded = [
        { check_on = "Packet Loss (in %)", filter_type = "Greater Than", value = tostring(ctx.params.packet_loss_percent) },
        { check_on = "Jitter (in ms)", filter_type = "Greater Than", value = tostring(ctx.params.jitter_ms) },
        { check_on = "Response Time (in ms)", filter_type = "Greater Than", value = tostring(ctx.params.response_time_ms) },
      ]
      operational = [
        { check_on = "Is Online", filter_type = "True" },
      ]
    }
  }

  script_criteria_filters = {
    for ctx in local.criteria_contexts : ctx.id => {
      offline = [
        { check_on = "Error", filter_type = "Is Not Empty" },
      ]
      degraded = [
        { check_on = "Execution Time (in ms)", filter_type = "Greater Than", value = tostring(ctx.params.execution_time_ms) },
      ]
      operational = [
        { check_on = "Error", filter_type = "Is Empty" },
      ]
    }
  }

  // -------------------------------------------------------------------------
  // The envelope
  //
  // Identical for every monitor type: name, description, the status flip, and
  // the incident or alert the preset opens. Built once, here.
  // -------------------------------------------------------------------------

  // What each criterion creates. The preset decides - offline an incident,
  // degraded an alert - and criteria.<preset>.create_incidents / create_alerts
  // override it. Operational is the recovery criterion and never creates
  // either. Resolved once, so the flags and the incidents / alerts blocks
  // below cannot disagree.
  criteria_creates = {
    for ctx in local.criteria_contexts : ctx.id => {
      incidents = local.criteria_preset_defaults[ctx.preset].creates != "nothing" && coalesce(
        ctx.params.create_incidents,
        local.criteria_preset_defaults[ctx.preset].creates == "incident",
      )
      alerts = local.criteria_preset_defaults[ctx.preset].creates != "nothing" && coalesce(
        ctx.params.create_alerts,
        local.criteria_preset_defaults[ctx.preset].creates == "alert",
      )
    }
  }

  criteria_rendered_presets = {
    for ctx in local.criteria_contexts : ctx.id => merge(
      local.monitor_criteria_defaults,

      {
        name             = coalesce(ctx.params.name, local.criteria_preset_defaults[ctx.preset].name)
        description      = coalesce(ctx.params.description, "${ctx.display_name} ${local.criteria_preset_defaults[ctx.preset].summary}")
        filter_condition = coalesce(ctx.params.filter_condition, local.criteria_preset_defaults[ctx.preset].filter_condition)
        filters          = local.criteria_filters[ctx.id]

        // Every preset maps to a monitor status and must be able to set it.
        // Excluding `operational` here made recovery impossible: a monitor
        // could be flipped to Offline or Degraded, but the one criterion that
        // returns it to healthy was told not to change the status, so it stayed
        // down for good while the probe reported 200. Suppressing the incident
        // and the alert for `operational` is the job of criteria_creates,
        // not of this flag.
        change_monitor_status = true
        monitor_status_id     = local.monitor_status_ids[local.criteria_preset_defaults[ctx.preset].monitor_status]

        create_incidents = local.criteria_creates[ctx.id].incidents
        create_alerts    = local.criteria_creates[ctx.id].alerts
      },

      ctx.params.is_enabled == null ? {} : { is_enabled = ctx.params.is_enabled },

      // incidents / alerts are only emitted when the criterion actually creates
      // one - the provider wants the key absent, not an empty list.
      local.criteria_creates[ctx.id].incidents ? {
        incidents = [
          merge(
            {
              title                        = coalesce(ctx.params.incident_title, "${ctx.display_name} is offline")
              description                  = coalesce(ctx.params.incident_description, "${ctx.display_name} failed its ${ctx.monitor_type} check.")
              incident_severity_id         = local.incident_severity_ids[ctx.params.incident_severity]
              auto_resolve_incident        = true
              show_incident_on_status_page = true
              is_private                   = false
            },
            ctx.params.remediation_notes == null ? {} : { remediation_notes = ctx.params.remediation_notes },
          )
        ]
      } : {},

      local.criteria_creates[ctx.id].alerts ? {
        alerts = [
          merge(
            {
              title              = coalesce(ctx.params.alert_title, "${ctx.display_name} is degraded")
              description        = coalesce(ctx.params.alert_description, "${ctx.display_name} responded outside its expected thresholds.")
              alert_severity_id  = local.alert_severity_ids[ctx.params.alert_severity]
              auto_resolve_alert = true
              is_private         = false
            },
            ctx.params.remediation_notes == null ? {} : { remediation_notes = ctx.params.remediation_notes },
          )
        ]
      } : {},

      ctx.params.overrides,
    )
  }

  // Hand-written criteria, evaluated after the offline/degraded presets and
  // before operational, in the order the monitor listed them.
  criteria_rendered_extra = {
    for entry in flatten([
      for key, spec in local.monitor_specs : [
        for index, criterion in spec.extra_criteria : {
          id        = format("%s~%03d~%03d", key, 50, index)
          criterion = criterion
        }
      ]
    ]) : entry.id => merge(local.monitor_criteria_defaults, entry.criterion)
  }

  criteria_rendered = merge(local.criteria_rendered_presets, local.criteria_rendered_extra)

  // Regrouped per monitor. The id encodes the preset order, so sorting the keys
  // is what puts the criteria in evaluation order.
  monitor_criteria = {
    for key, spec in local.monitor_specs : key => [
      for id in sort([
        for candidate in keys(local.criteria_rendered) : candidate
        if startswith(candidate, "${key}~")
      ]) : local.criteria_rendered[id]
    ]
  }
}
