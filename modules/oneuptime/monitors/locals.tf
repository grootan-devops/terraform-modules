locals {
  // -------------------------------------------------------------------------
  // Resolved ids
  //
  // A monitor names a status or a severity; the id lookup happens once here.
  // -------------------------------------------------------------------------
  monitor_status_ids = {
    operational = data.oneuptime_monitor_status.operational.id
    degraded    = data.oneuptime_monitor_status.degraded.id
    offline     = data.oneuptime_monitor_status.offline.id
  }

  incident_severity_ids = {
    critical = data.oneuptime_incident_severity.critical.id
    major    = data.oneuptime_incident_severity.major.id
    minor    = data.oneuptime_incident_severity.minor.id
  }

  alert_severity_ids = {
    high = data.oneuptime_alert_severity.high.id
    low  = data.oneuptime_alert_severity.low.id
  }

  // -------------------------------------------------------------------------
  // Step defaults
  // -------------------------------------------------------------------------

  // Defaults common to every monitor step, regardless of monitor type. Merged
  // underneath each step, so a step that sets one of these wins and a step that
  // omits it inherits the baseline.
  monitor_step_defaults = {
    request_timeout_in_ms          = var.monitor_defaults.monitor_step.request_timeout_in_ms
    retry_count                    = var.monitor_defaults.monitor_step.retry_count
    do_not_follow_redirects        = var.monitor_defaults.monitor_step.do_not_follow_redirects
    allow_self_signed_certificates = var.monitor_defaults.monitor_step.allow_self_signed_certificates
  }

  // The part of a step that is implied by monitor_type alone. This is what lets
  // an API monitor be declared with nothing but `target`: the destination type
  // and the request verb are not a choice, they follow from the type. A monitor
  // that needs something else sets it in its own `step` block.
  monitor_type_step_defaults = {
    "API"               = { monitor_destination_type = "URL", request_type = "GET" }
    "Website"           = { monitor_destination_type = "URL" }
    "Ping"              = { monitor_destination_type = "Hostname" }
    "IP"                = { monitor_destination_type = "IP" }
    "Port"              = { monitor_destination_type = "Hostname" }
    "SSL Certificate"   = { monitor_destination_type = "URL" }
    "Synthetic Monitor" = { browser_types = ["Chromium"], screen_size_types = ["Desktop"] }
  }

  // Same idea one level deeper: every criterion of every step inherits these.
  monitor_criteria_defaults = {
    filter_condition = var.monitor_defaults.criteria.filter_condition
    is_enabled       = var.monitor_defaults.criteria.is_enabled
  }

  // -------------------------------------------------------------------------
  // Monitor definitions
  // -------------------------------------------------------------------------

  // Flatten monitors_component_mapping (component -> monitor keys) into one
  // entry per monitor, keyed by the slug used in monitor_configs, so monitors
  // can be provisioned without re-deriving the component on every attribute.
  monitor_definitions = {
    for entry in flatten([
      for component, monitors in var.monitors_component_mapping : [
        for monitor in monitors : {
          key       = monitor
          component = component
        }
      ]
      ]) : entry.key => {
      component = entry.component
      config    = var.monitor_configs[entry.key]

      // Labels are never set in monitor_configs. Every monitor gets its
      // component label, the labels of the group(s) that own the component and
      // the project label, so labelling stays consistent across monitors.
      label_names = distinct(concat(
        try(var.component_definitions[entry.component].label_names, [entry.component]),
        [var.application],
      ))
    }
  }

  // Everything the step and criteria generators need, read out of the raw
  // config once with the defaults already applied, so the generators below can
  // use plain attribute access instead of try() on every line.
  monitor_specs = {
    for key, entry in local.monitor_definitions : key => {
      config       = entry.config
      monitor_type = entry.config.monitor_type
      display_name = try(entry.config.display_name, key)

      // A monitor that writes its own monitor_steps opts out of step
      // generation. Its steps may still leave `criteria` off and pick up the
      // generated ones - see main.tf.
      has_explicit_steps = can(entry.config.monitor_steps)

      // Which criteria are generated, in the order the preset catalogue
      // defines. Listing criteria_presets explicitly narrows or reorders the
      // set; the `criteria` map only carries values, never membership, so
      // tuning one preset never silently drops the others.
      criteria_presets = try(
        entry.config.criteria_presets,
        local.criteria_presets_by_type[entry.config.monitor_type],
        [],
      )

      // Thresholds for every criterion of this monitor. The middle of the
      // three levels: project defaults, then this, then criteria.<preset>.
      // A heartbeat window, for example, has to be the same for the offline
      // and the operational criterion, so it belongs here rather than on one
      // of them.
      thresholds = try(entry.config.thresholds, {})

      // Per-preset values. Everything not set here comes from `thresholds`,
      // var.monitor_defaults.thresholds and the preset itself.
      criteria = try(entry.config.criteria, {})

      // Fully-formed criteria appended after the generated ones, for the
      // occasional check no preset covers.
      extra_criteria = try(entry.config.extra_criteria, [])
    }
  }

  // -------------------------------------------------------------------------
  // Steps
  //
  // A monitor either declares the minimum its type needs (`target`, `port`,
  // `step`) and gets one generated step, or writes monitor_steps out in full.
  // -------------------------------------------------------------------------

  // The generated step: the monitor type decides the shape, the monitor decides
  // the destination. range() rather than a conditional so the result stays a
  // list of steps in both branches.
  generated_monitor_steps = {
    for key, spec in local.monitor_specs : key => [
      for _ in range(spec.has_explicit_steps || spec.monitor_type == "Manual" ? 0 : 1) : merge(
        local.monitor_step_defaults,
        try(local.monitor_type_step_defaults[spec.monitor_type], {}),

        try(spec.config.target, null) == null ? {} : { monitor_destination = spec.config.target },
        try(spec.config.target_type, null) == null ? {} : { monitor_destination_type = spec.config.target_type },
        try(spec.config.port, null) == null ? {} : { port = spec.config.port },

        // Anything else the step needs, passed through verbatim: request_body,
        // custom_code, tls_client_*, dns_monitor, sql_monitor and friends.
        try(spec.config.step, {}),

        // Headers deep-merge so a monitor can add one without losing the
        // project-wide ones. Only set the key when there is something to set,
        // otherwise non-HTTP monitor types would gain an empty map.
        length(local.monitor_request_headers[key]) > 0 ? {
          request_headers = local.monitor_request_headers[key]
        } : {},

        { criteria = local.monitor_criteria[key] },
      )
    ]
  }

  // Monitor types that issue an HTTP request, and so are the only ones the
  // project-wide request_headers apply to. Attaching a User-Agent to a Server
  // or heartbeat monitor would be noise on every step.
  monitor_types_with_requests = ["API", "Website"]

  monitor_request_headers = {
    for key, spec in local.monitor_specs : key => merge(
      contains(local.monitor_types_with_requests, spec.monitor_type) ? var.monitor_defaults.monitor_step.request_headers : {},
      try(spec.config.step.request_headers, {}),
    )
  }

  // Steps written out by hand, with the same defaults layered underneath. A
  // step that omits `criteria` still picks up the generated ones, so a monitor
  // can hand-write an unusual probe and keep the standard criteria.
  explicit_monitor_steps = {
    for key, spec in local.monitor_specs : key => [
      for step in try(spec.config.monitor_steps, []) : merge(
        local.monitor_step_defaults,
        step,

        length(merge(
          contains(local.monitor_types_with_requests, spec.monitor_type) ? var.monitor_defaults.monitor_step.request_headers : {},
          try(step.request_headers, {}),
          )) > 0 ? {
          request_headers = merge(
            contains(local.monitor_types_with_requests, spec.monitor_type) ? var.monitor_defaults.monitor_step.request_headers : {},
            try(step.request_headers, {}),
          )
        } : {},

        // criteria is required on every step, so it is always rebuilt. Order is
        // preserved because first match wins. concat() rather than a
        // conditional: the two branches are tuples of different lengths, which
        // a conditional refuses to unify.
        {
          criteria = concat(
            [for criterion in try(step.criteria, []) : merge(local.monitor_criteria_defaults, criterion)],
            flatten([for _ in range(can(step.criteria) ? 0 : 1) : local.monitor_criteria[key]]),
          )
        },
      )
    ]
  }

  // OneUptime drops these two from a step when they are false and returns a step
  // without them, so sending false fails the apply with "inconsistent values for
  // sensitive attribute". They are stripped unless actually on. Same falsy
  // handling that makes a 0 uptime threshold unsettable in variables-status-pages.tf.
  step_keys_omitted_when_false = ["do_not_follow_redirects", "allow_self_signed_certificates"]

  // Exactly one of the two is non-empty; Manual monitors have neither.
  monitor_steps = {
    for key, spec in local.monitor_specs : key => [
      for step in concat(
        local.explicit_monitor_steps[key],
        local.generated_monitor_steps[key],
        ) : {
        for attribute, value in step : attribute => value
        if !contains(local.step_keys_omitted_when_false, attribute) || value == true
      }
    ]
  }
}
