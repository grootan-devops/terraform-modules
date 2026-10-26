// Inputs consumed by ./status-pages. See
// ./status-pages/README.md for the page schema and examples.

variable "status_page_defaults" {
  description = "Baseline configuration applied to every status page, overridable per project and per page"

  type = object({
    // Access. Public, indexable and unauthenticated is the common shape for a
    // customer-facing page; a private page flips is_public_status_page and adds
    // private_users, a master password or SSO.
    is_public_status_page               = optional(bool, true)
    enable_search_engine_indexing       = optional(bool, true)
    hide_powered_by_one_uptime_branding = optional(bool, false)
    enable_mcp_server                   = optional(bool, false)
    enable_master_password              = optional(bool, false)
    require_sso_for_login               = optional(bool, false)

    // What the page shows. Incidents, maintenance and announcements are on;
    // the internal labels behind them are not, since they mean nothing to a
    // reader outside the team.
    show_incidents_on_status_page                    = optional(bool, true)
    show_incident_labels_on_status_page              = optional(bool, false)
    show_incident_history_in_days                    = optional(number, 30)
    show_announcements_on_status_page                = optional(bool, true)
    show_announcement_history_in_days                = optional(number, 14)
    show_scheduled_maintenance_events_on_status_page = optional(bool, true)
    show_scheduled_event_labels_on_status_page       = optional(bool, false)
    show_scheduled_event_history_in_days             = optional(number, 14)
    show_episodes_on_status_page                     = optional(bool, true)
    show_episode_labels_on_status_page               = optional(bool, false)
    show_episode_history_in_days                     = optional(number, 30)

    // 90 days of history and a two-decimal uptime figure is what a page is
    // usually held to in an SLA conversation. 90 is the server maximum.
    show_uptime_history_in_days                = optional(number, 90)
    show_overall_uptime_percent_on_status_page = optional(bool, true)
    overall_uptime_percent_precision           = optional(string, "99% (No Decimal)")

    // Subscribers. Email is the one channel that needs no extra setup, so it is
    // the only one on by default; SMS, Slack, Teams and webhooks each need a
    // configured integration before they work.
    show_subscriber_page_on_status_page     = optional(bool, false)
    enable_email_subscribers                = optional(bool, false)
    enable_sms_subscribers                  = optional(bool, false)
    enable_slack_subscribers                = optional(bool, false)
    enable_microsoft_teams_subscribers      = optional(bool, false)
    enable_webhook_subscribers              = optional(bool, false)
    allow_subscribers_to_choose_resources   = optional(bool, true)
    allow_subscribers_to_choose_event_types = optional(bool, true)

    // Scheduled reports. Off by default - the remaining report_* attributes are
    // per-page (interval, period type, timezone) and are only read once a page
    // turns this on.
    is_report_enabled   = optional(bool, false)
    report_data_in_days = optional(number, 7)

    // Colour of an uptime bar that no history_chart_bar_colors band matches.
    default_bar_color = optional(string, "#0F9D58")

    // status_page_groups[*] - applies to every group of every page.
    group = optional(object({
      is_expanded_by_default   = optional(bool, true)
      show_current_status      = optional(bool, true)
      show_uptime_percent      = optional(bool, true)
      uptime_percent_precision = optional(string, "99% (No Decimal)")
      view_mode                = optional(string, "List")
    }), {})

    // status_page_resources[*] and the monitor rules that generate them.
    resource = optional(object({
      show_current_status       = optional(bool, true)
      show_status_history_chart = optional(bool, true)
      show_uptime_percent       = optional(bool, true)
      uptime_percent_precision  = optional(string, "99% (No Decimal)")
    }), {})

    // status_page_subscribers[*]. A subscriber added by Terraform is one the
    // operator vouched for, so it is subscribed to everything unless it says
    // otherwise.
    subscriber = optional(object({
      is_subscribed_to_all_resources   = optional(bool, true)
      is_subscribed_to_all_event_types = optional(bool, true)
      send_you_have_subscribed_message = optional(bool, true)
    }), {})

    // status_page_announcements[*].
    announcement = optional(object({
      should_status_page_subscribers_be_notified = optional(bool, true)
    }), {})

    // Colour of each bar in the uptime history chart, by the uptime percent it
    // covers. The bands are read highest threshold first, giving the usual
    // green / amber / red split.
    //
    // Empty by default, which leaves the chart on OneUptime's own colours,
    // because the provider cannot manage this resource: the API returns
    // uptimePercentGreaterThanOrEqualTo as a string ("95") while the provider
    // schema declares it a number, so it reads back as null and every apply
    // fails with "Provider produced inconsistent result after apply". The rules
    // are created correctly server-side - only the read-back is broken - so set
    // the bands here once the provider coerces the value. Verified still broken
    // in 12.0.26. A threshold of 0 is separately rejected by the API, which
    // falsy-checks the field; start the bottom band at 0.01.
    history_chart_bar_colors = optional(list(object({
      uptime_percent_greater_than_or_equal_to = number
      bar_color                               = string
      order                                   = optional(number)
    })), [])
  })

  default = {}

  validation {
    condition     = var.status_page_defaults.show_uptime_history_in_days > 0 && var.status_page_defaults.show_uptime_history_in_days <= 90
    error_message = "show_uptime_history_in_days must be between 1 and 90; the server caps it at 90."
  }

  validation {
    condition = alltrue([
      for precision in [
        var.status_page_defaults.overall_uptime_percent_precision,
        var.status_page_defaults.group.uptime_percent_precision,
        var.status_page_defaults.resource.uptime_percent_precision,
      ] : contains(["99% (No Decimal)", "99% (One Decimal)", "99% (Two Decimal)"], precision)
    ])
    error_message = "uptime percent precision must be one of \"99% (No Decimal)\", \"99% (One Decimal)\" or \"99% (Two Decimal)\"."
  }

  validation {
    condition     = contains(["List", "Grid"], var.status_page_defaults.group.view_mode)
    error_message = "group.view_mode must be either \"List\" or \"Grid\"."
  }

  validation {
    condition = alltrue([
      for band in var.status_page_defaults.history_chart_bar_colors :
      band.uptime_percent_greater_than_or_equal_to >= 0 && band.uptime_percent_greater_than_or_equal_to <= 100
    ])
    error_message = "history_chart_bar_colors thresholds must be between 0 and 100."
  }

  validation {
    condition = alltrue([
      for band in var.status_page_defaults.history_chart_bar_colors :
      band.uptime_percent_greater_than_or_equal_to != 0
    ])
    error_message = "history_chart_bar_colors threshold cannot be 0: the OneUptime API falsy-checks this field and rejects it as \"uptimePercentGreaterThanOrEqualTo is required\". Use a small non-zero value such as 0.01."
  }
}


variable "status_page_configs" {
  description = "Status pages to create, keyed by a short identifier. Everything is optional - a page with no attributes at all is named after its key and inherits status_page_defaults."
  default     = {}

  type = map(object({
    // Name shown on the page and in the dashboard. Defaults to the map key.
    name = optional(string)
    // Friendly description that helps you remember what this page is for. Internal only.
    description = optional(string)
    // Labels attached to this status page. Must be keys of `labels_config` or
    // `application`. Defaults to the project label. Give a page its component
    // label to have the status page owner and label rules pick it up.
    label_names = optional(set(string))

    // Copy and SEO
    page_title                = optional(string)
    page_description          = optional(string)
    overview_page_description = optional(string)
    copyright_text            = optional(string)
    default_language          = optional(string)
    enabled_languages         = optional(string)
    custom_fields             = optional(string)

    // Access - overrides status_page_defaults
    is_public_status_page               = optional(bool)
    enable_search_engine_indexing       = optional(bool)
    hide_powered_by_one_uptime_branding = optional(bool)
    enable_mcp_server                   = optional(bool)
    enable_master_password              = optional(bool)
    master_password                     = optional(string)
    require_sso_for_login               = optional(bool)
    ip_whitelist                        = optional(string)

    // What the page shows - overrides status_page_defaults
    show_incidents_on_status_page                    = optional(bool)
    show_incident_labels_on_status_page              = optional(bool)
    show_incident_history_in_days                    = optional(number)
    show_announcements_on_status_page                = optional(bool)
    show_announcement_history_in_days                = optional(number)
    show_scheduled_maintenance_events_on_status_page = optional(bool)
    show_scheduled_event_labels_on_status_page       = optional(bool)
    show_scheduled_event_history_in_days             = optional(number)
    show_episodes_on_status_page                     = optional(bool)
    show_episode_labels_on_status_page               = optional(bool)
    show_episode_history_in_days                     = optional(number)
    show_uptime_history_in_days                      = optional(number)
    show_overall_uptime_percent_on_status_page       = optional(bool)
    overall_uptime_percent_precision                 = optional(string)

    // Subscribers - overrides status_page_defaults
    show_subscriber_page_on_status_page                     = optional(bool)
    enable_email_subscribers                                = optional(bool)
    enable_sms_subscribers                                  = optional(bool)
    enable_slack_subscribers                                = optional(bool)
    enable_microsoft_teams_subscribers                      = optional(bool)
    enable_webhook_subscribers                              = optional(bool)
    allow_subscribers_to_choose_resources                   = optional(bool)
    allow_subscribers_to_choose_event_types                 = optional(bool)
    subscriber_timezones                                    = optional(string)
    subscriber_email_notification_footer_text               = optional(string)
    enable_custom_subscriber_email_notification_footer_text = optional(bool)

    // Embedded badge and scheduled reports
    enable_embedded_overall_status = optional(bool)
    embedded_overall_status_token  = optional(string)
    is_report_enabled              = optional(bool)
    report_data_in_days            = optional(number)
    report_recurring_interval      = optional(string)
    report_period_type             = optional(string)
    report_start_date_time         = optional(string)
    report_timezone                = optional(string)

    // Branding
    logo_file_id         = optional(string)
    logo_alt_text        = optional(string)
    favicon_file_id      = optional(string)
    cover_image_file_id  = optional(string)
    cover_image_alt_text = optional(string)
    default_bar_color    = optional(string)
    custom_css           = optional(string)
    custom_java_script   = optional(string)
    header_html          = optional(string)
    footer_html          = optional(string)

    // Delivery
    smtp_config_id     = optional(string)
    call_sms_config_id = optional(string)

    // Colour bands of the uptime history chart. Replaces the shipped
    // green/amber/red bands wholesale when set.
    history_chart_bar_colors = optional(list(object({
      uptime_percent_greater_than_or_equal_to = number
      bar_color                               = string
      order                                   = optional(number)
    })))

    // Groups the resources on this page are organised into, keyed by a short
    // identifier that `resources.group_key` and `monitor_rules.group_key`
    // refer to. `name` defaults to the key, `order` to the key's position.
    groups = optional(map(object({
      name                     = optional(string)
      description              = optional(string)
      order                    = optional(number)
      is_expanded_by_default   = optional(bool)
      show_current_status      = optional(bool)
      show_uptime_percent      = optional(bool)
      uptime_percent_precision = optional(string)
      // `List` stacks resources vertically, `Grid` renders them as a matrix
      // using the row and column axes below.
      view_mode          = optional(string)
      row_axis_label     = optional(string)
      row_axis_values    = optional(string)
      column_axis_label  = optional(string)
      column_axis_values = optional(string)
    })), {})

    // Monitors published on this page, listed one by one. Exactly one of
    // monitor_key, monitor_group_key, monitor_id or monitor_group_id must be
    // set. Prefer monitor_rules below when a whole label should be published.
    resources = optional(map(object({
      // Key of an entry in monitor_configs.
      monitor_key = optional(string)
      // Component name from rbac_component_mapping - publishes the monitor
      // group this module creates for that component.
      monitor_group_key = optional(string)
      // Ids of a monitor or monitor group that exists outside this module.
      monitor_id       = optional(string)
      monitor_group_id = optional(string)

      group_key                 = optional(string)
      display_name              = optional(string)
      display_description       = optional(string)
      display_tooltip           = optional(string)
      order                     = optional(number)
      show_current_status       = optional(bool)
      show_status_history_chart = optional(bool)
      show_uptime_percent       = optional(bool)
      uptime_percent_precision  = optional(string)
      // Only read when the group this resource sits in uses `Grid` view_mode;
      // must match one of the group's row/column axis values.
      row_axis_value    = optional(string)
      column_axis_value = optional(string)
    })), {})

    // Publishes every monitor matching a filter, so a new monitor appears on
    // the page without editing it. At least one of label_names,
    // monitor_name_pattern or monitor_description_pattern must be set.
    monitor_rules = optional(map(object({
      name        = optional(string)
      description = optional(string)
      is_enabled  = optional(bool)
      group_key   = optional(string)

      // Labels a monitor must carry to be published. Must be keys of
      // `labels_config` or `application`.
      label_names = optional(set(string))
      // Case-insensitive regexes. Use ".*" to match every monitor.
      monitor_name_pattern        = optional(string)
      monitor_description_pattern = optional(string)

      show_current_status       = optional(bool)
      show_status_history_chart = optional(bool)
      show_uptime_percent       = optional(bool)
      uptime_percent_precision  = optional(string)
    })), {})

    // Links shown in the page header and footer. `title` defaults to the key.
    header_links = optional(map(object({
      link  = string
      title = optional(string)
      order = optional(number)
    })), {})

    footer_links = optional(map(object({
      link  = string
      title = optional(string)
      order = optional(number)
    })), {})

    // Custom domain this page is served on. The domain must already be added
    // and verified in the OneUptime project.
    domain = optional(object({
      // Name of the domain in OneUptime, e.g. "example.com".
      domain_name = string
      // Subdomain label such as "status". Leave blank or "@" for the root.
      subdomain = optional(string)
    }))

    // Users allowed to log in to a private page.
    private_users = optional(map(object({
      email       = string
      password    = optional(string)
      is_sso_user = optional(bool)
    })), {})

    // Subscribers seeded by Terraform - a mailing list, a Slack channel or a
    // webhook that should always be notified. Set exactly one channel per
    // entry.
    subscribers = optional(map(object({
      subscriber_email                     = optional(string)
      subscriber_phone                     = optional(string)
      subscriber_webhook                   = optional(string)
      slack_workspace_name                 = optional(string)
      slack_incoming_webhook_url           = optional(string)
      microsoft_teams_workspace_name       = optional(string)
      microsoft_teams_incoming_webhook_url = optional(string)

      // Comma-separated event types, e.g. "Incident,Announcement". Only read
      // when is_subscribed_to_all_event_types is false.
      status_page_event_types          = optional(string)
      is_subscribed_to_all_resources   = optional(bool)
      is_subscribed_to_all_event_types = optional(bool)
      is_subscription_confirmed        = optional(bool)
      send_you_have_subscribed_message = optional(bool)
      internal_note                    = optional(string)
    })), {})

    // Groups from rbac_team_mapping that own this page, and raw ids of users
    // that own it (looking users up by name needs a wider API key).
    owner_group_names = optional(set(string), [])
    owner_user_ids    = optional(set(string), [])
  }))

  validation {
    condition = alltrue([
      for page in var.status_page_configs : alltrue([
        for resource in page.resources : length([
          for id in [resource.monitor_key, resource.monitor_group_key, resource.monitor_id, resource.monitor_group_id] : id if id != null
        ]) == 1
      ])
    ])
    error_message = "Each status page resource must set exactly one of monitor_key, monitor_group_key, monitor_id or monitor_group_id."
  }

  validation {
    condition = alltrue([
      for page in var.status_page_configs : alltrue([
        for resource in page.resources :
        resource.monitor_key == null || contains(keys(var.monitor_configs), coalesce(resource.monitor_key, ""))
      ])
    ])
    error_message = "Each status page resource monitor_key must match a key in monitor_configs."
  }

  validation {
    condition = alltrue([
      for page in var.status_page_configs : alltrue([
        for resource in page.resources :
        resource.monitor_group_key == null || contains(keys(var.rbac_component_mapping), coalesce(resource.monitor_group_key, ""))
      ])
    ])
    error_message = "Each status page resource monitor_group_key must match a component in rbac_component_mapping."
  }

  validation {
    condition = alltrue([
      for page in var.status_page_configs : alltrue(concat(
        [for resource in page.resources : resource.group_key == null || contains(keys(page.groups), coalesce(resource.group_key, ""))],
        [for rule in page.monitor_rules : rule.group_key == null || contains(keys(page.groups), coalesce(rule.group_key, ""))],
      ))
    ])
    error_message = "Each status page resource and monitor rule group_key must match a key in the groups of the same status page."
  }

  validation {
    condition = alltrue([
      for page in var.status_page_configs : alltrue([
        for rule in page.monitor_rules :
        rule.label_names != null || rule.monitor_name_pattern != null || rule.monitor_description_pattern != null
      ])
    ])
    error_message = "Each status page monitor rule must set at least one of label_names, monitor_name_pattern or monitor_description_pattern, otherwise it matches nothing."
  }
}


variable "status_page_announcements" {
  description = "Announcements published on status pages, keyed by a short identifier. Announcements are project-level in OneUptime, so one entry can appear on several pages."
  default     = {}

  type = map(object({
    title       = string
    description = string
    // RFC3339 timestamps, e.g. "2026-09-01T09:00:00Z".
    show_announcement_at = string
    end_announcement_at  = optional(string)
    // Keys of status_page_configs. Empty means every page this module manages.
    status_page_keys = optional(set(string), [])
    // Keys of monitor_configs the announcement is about. Empty means the whole page.
    monitor_keys                               = optional(set(string), [])
    should_status_page_subscribers_be_notified = optional(bool)
  }))

  validation {
    condition = alltrue([
      for announcement in var.status_page_announcements : alltrue([
        for monitor_key in announcement.monitor_keys : contains(keys(var.monitor_configs), monitor_key)
      ])
    ])
    error_message = "Each status page announcement monitor_keys entry must match a key in monitor_configs."
  }

  validation {
    condition = alltrue([
      for announcement in var.status_page_announcements : alltrue([
        for page_key in announcement.status_page_keys : contains(keys(var.status_page_configs), page_key)
      ])
    ])
    error_message = "Each status page announcement status_page_keys entry must match a key in status_page_configs."
  }
}
