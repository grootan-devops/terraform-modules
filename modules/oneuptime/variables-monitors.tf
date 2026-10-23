// Inputs consumed by ./modules/monitors. See ./modules/monitors/README.md
// for the monitor_configs schema and one worked example per monitor type.

variable "monitors_component_mapping" {
  type        = map(list(string))
  description = "component -> monitor keys. The keys must exist in monitor_configs; this is what attaches the component, group and project labels to each monitor"

  // Without this, a slug listed here but missing from monitor_configs fails
  // deep inside the monitors submodule with a bare "Invalid index".
  validation {
    condition = length(setsubtract(
      toset(flatten(values(var.monitors_component_mapping))),
      toset(keys(var.monitor_configs)),
    )) == 0

    error_message = format(
      "Every monitor in monitors_component_mapping needs an entry with the same key in monitor_configs. Missing: %s.",
      join(", ", setsubtract(
        toset(flatten(values(var.monitors_component_mapping))),
        toset(keys(var.monitor_configs)),
      )),
    )
  }
}

variable "monitor_configs" {
  type        = any
  description = "One entry per monitor, keyed by the slug used in monitors_component_mapping"
  default     = {}

  // The module derives the whole step and every criterion from monitor_type,
  // so a wrong type produces a monitor with no steps rather than an obvious
  // error. Catch it here instead.
  validation {
    condition = alltrue([
      for key, config in var.monitor_configs : contains([
        "Manual", "Website", "API", "Ping", "IP", "Port", "Server", "SSL Certificate",
        "Incoming Request", "Incoming Email", "Synthetic Monitor",
        "Custom JavaScript Code", "SQL Query", "DNS", "DNSSEC", "Domain",
        "External Status Page", "Network Device", "Logs", "Metrics", "Traces",
        "Exceptions", "Profiles", "Security Events", "Kubernetes", "Docker",
        "Docker Swarm", "Podman", "Proxmox", "Ceph", "Host", "IoT Device",
      ], try(config.monitor_type, ""))
    ])

    error_message = format(
      "Every monitor needs a monitor_type from the list in modules/monitors/README.md §3. Wrong or missing on: %s.",
      join(", ", [
        for key, config in var.monitor_configs : key if !contains([
          "Manual", "Website", "API", "Ping", "IP", "Port", "Server", "SSL Certificate",
          "Incoming Request", "Incoming Email", "Synthetic Monitor",
          "Custom JavaScript Code", "SQL Query", "DNS", "DNSSEC", "Domain",
          "External Status Page", "Network Device", "Logs", "Metrics", "Traces",
          "Exceptions", "Profiles", "Security Events", "Kubernetes", "Docker",
          "Docker Swarm", "Podman", "Proxmox", "Ceph", "Host", "IoT Device",
        ], try(config.monitor_type, ""))
      ]),
    )
  }

  // Only the types with a preset catalogue can be written in the short form.
  // Anything else has to spell its monitor_steps out.
  validation {
    condition = alltrue([
      for key, config in var.monitor_configs :
      try(config.monitor_steps, null) != null || contains([
        "Manual", "API", "Website", "Ping", "IP", "Port", "SSL Certificate", "Server",
        "Custom JavaScript Code", "Synthetic Monitor", "DNS", "DNSSEC", "Domain",
        "SQL Query", "Incoming Request", "Incoming Email",
      ], try(config.monitor_type, ""))
    ])

    error_message = format(
      "These monitors have a monitor_type with no criteria presets, so they need explicit monitor_steps: %s.",
      join(", ", [
        for key, config in var.monitor_configs : key
        if try(config.monitor_steps, null) == null && !contains([
          "Manual", "API", "Website", "Ping", "IP", "Port", "SSL Certificate", "Server",
          "Custom JavaScript Code", "Synthetic Monitor", "DNS", "DNSSEC", "Domain",
          "SQL Query", "Incoming Request", "Incoming Email",
        ], try(config.monitor_type, ""))
      ]),
    )
  }

  // A probe monitor with no destination is accepted by the API and then never
  // checks anything.
  validation {
    condition = alltrue([
      for key, config in var.monitor_configs :
      try(config.monitor_steps, null) != null || try(config.target, null) != null
      || !contains(["API", "Website", "Ping", "IP", "Port", "SSL Certificate"], try(config.monitor_type, ""))
    ])

    error_message = format(
      "These monitors probe a destination, so they need `target` (or explicit monitor_steps): %s.",
      join(", ", [
        for key, config in var.monitor_configs : key
        if try(config.monitor_steps, null) == null && try(config.target, null) == null
        && contains(["API", "Website", "Ping", "IP", "Port", "SSL Certificate"], try(config.monitor_type, ""))
      ]),
    )
  }

  validation {
    condition = alltrue([
      for key, config in var.monitor_configs :
      try(config.monitor_steps, null) != null || try(config.port, null) != null
      || try(config.monitor_type, "") != "Port"
    ])

    error_message = format(
      "Port monitors need `port`: %s.",
      join(", ", [
        for key, config in var.monitor_configs : key
        if try(config.monitor_steps, null) == null && try(config.port, null) == null
        && try(config.monitor_type, "") == "Port"
      ]),
    )
  }

  // criteria carries values for a preset; a typo would otherwise be ignored in
  // silence, leaving the monitor on the shipped thresholds.
  validation {
    condition = alltrue(flatten([
      for key, config in var.monitor_configs : [
        for preset in keys(try(config.criteria, {})) :
        contains(["offline", "degraded", "operational"], preset)
      ]
    ]))

    error_message = "criteria keys must be preset names: \"offline\", \"degraded\" or \"operational\". Use extra_criteria for anything else."
  }

  validation {
    condition = alltrue(flatten([
      for key, config in var.monitor_configs : [
        for preset in try(config.criteria_presets, []) :
        contains(["offline", "degraded", "operational"], preset)
      ]
    ]))

    error_message = "criteria_presets must be drawn from \"offline\", \"degraded\" and \"operational\"."
  }
}


variable "monitor_defaults" {
  description = "Baseline configuration applied to every monitor, overridable per project and per monitor"

  type = object({
    // Envelope - applies to every monitor type.
    monitoring_interval       = optional(string, "* * * * *")
    disable_active_monitoring = optional(bool, false)
    minimum_probe_agreement   = optional(number, 1)

    // monitor_steps[*] - applies to every step of every monitor.
    monitor_step = optional(object({
      request_timeout_in_ms          = optional(number, 5000)
      retry_count                    = optional(number, 3)
      do_not_follow_redirects        = optional(bool, false)
      allow_self_signed_certificates = optional(bool, false)

      // Deep-merged with the step's own request_headers, so a monitor can add
      // a header without dropping the project-wide ones. Empty by default so
      // non-HTTP monitor types are left untouched.
      request_headers = optional(map(string), {})
    }), {})

    // monitor_steps[*].criteria[*] - applies to every criterion of every step.
    criteria = optional(object({
      filter_condition = optional(string, "All")
      is_enabled       = optional(bool, true)
    }), {})

    // Values the generated criteria compare against. A monitor overrides any
    // of them for one criterion (criteria.<preset>.<key>); setting one here
    // moves it for the whole project. See modules/monitors/README.md.
    thresholds = optional(object({
      // API / Website
      expected_status_code              = optional(number, 200)
      response_time_ms                  = optional(number, 5000)
      evaluate_over_time_minutes        = optional(number, 15)
      evaluate_over_time_type           = optional(string, "Average")
      evaluate_over_time_no_data_policy = optional(string, "Ignore")

      // Ping / IP
      packet_loss_percent = optional(number, 10)
      jitter_ms           = optional(number, 50)

      // Certificates, domains, DNSSEC signatures
      certificate_expiry_days = optional(number, 21)
      domain_expiry_days      = optional(number, 30)
      dnssec_expiry_days      = optional(number, 7)

      // Heartbeats: Incoming Request / Incoming Email
      heartbeat_timeout_minutes = optional(number, 60)

      // Scripted checks and queries
      execution_time_ms    = optional(number, 10000)
      query_time_ms        = optional(number, 5000)
      dns_response_time_ms = optional(number, 500)

      // Server
      cpu_percent    = optional(number, 90)
      memory_percent = optional(number, 90)
      disk_percent   = optional(number, 85)
      swap_percent   = optional(number, 50)
      disk_path      = optional(string, "/")
    }), {})

    // Severity of the incident the offline preset opens and of the alert the
    // degraded preset raises, by name. Overridable per criterion.
    severities = optional(object({
      incident = optional(string, "critical")
      alert    = optional(string, "low")
    }), {})
  })

  default = {}

  validation {
    condition = contains([
      "* * * * *", "*/2 * * * *", "*/5 * * * *", "*/10 * * * *", "*/15 * * * *",
      "*/30 * * * *", "0 * * * *", "0 0 * * *", "0 0 * * 0",
    ], var.monitor_defaults.monitoring_interval)
    error_message = "monitoring_interval must be one of the cron expressions the OneUptime dashboard offers, e.g. \"*/5 * * * *\"."
  }

  validation {
    condition     = var.monitor_defaults.minimum_probe_agreement >= 1
    error_message = "minimum_probe_agreement must be at least 1."
  }

  validation {
    condition     = var.monitor_defaults.monitor_step.request_timeout_in_ms > 0 && var.monitor_defaults.monitor_step.request_timeout_in_ms <= 60000
    error_message = "request_timeout_in_ms must be between 1 and 60000; the server caps it at 60000."
  }

  validation {
    condition     = var.monitor_defaults.monitor_step.retry_count >= 0 && var.monitor_defaults.monitor_step.retry_count <= 3
    error_message = "retry_count must be between 0 and 3; the server caps it at 3."
  }

  validation {
    condition     = contains(["All", "Any"], var.monitor_defaults.criteria.filter_condition)
    error_message = "criteria.filter_condition must be either \"All\" or \"Any\"."
  }

  validation {
    condition     = contains(["critical", "major", "minor"], var.monitor_defaults.severities.incident)
    error_message = "severities.incident must be one of \"critical\", \"major\" or \"minor\"."
  }

  validation {
    condition     = contains(["high", "low"], var.monitor_defaults.severities.alert)
    error_message = "severities.alert must be one of \"high\" or \"low\"."
  }

  validation {
    condition = contains([
      "Average", "Sum", "Maximum Value", "Minimum Value", "All Values", "Any Value",
    ], var.monitor_defaults.thresholds.evaluate_over_time_type)
    error_message = "thresholds.evaluate_over_time_type must be one of the aggregations OneUptime offers, e.g. \"Average\"."
  }

  validation {
    condition = contains([
      2, 3, 5, 10, 15, 20, 30, 45, 60,
    ], var.monitor_defaults.thresholds.evaluate_over_time_minutes)
    error_message = "thresholds.evaluate_over_time_minutes must be one of 2, 3, 5, 10, 15, 20, 30, 45 or 60."
  }
}
