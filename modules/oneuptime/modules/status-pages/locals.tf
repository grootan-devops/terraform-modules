locals {
  // Status pages follow the same defaulting model as monitors: the industry
  // standard lives in var.status_page_defaults, the project overrides it once
  // in the module block, and a page overrides it again only where it genuinely
  // differs. Precedence, lowest to highest:
  //
  //   1. the `default` on var.status_page_defaults - the industry-standard baseline
  //   2. `status_page_defaults` passed to the module - the project-wide baseline
  //   3. the page's own entry in status_page_configs - the per-page override
  //
  // coalesce() picks the first non-null, and every overridable attribute in
  // status_page_configs is `optional()` with no default, so it is null unless
  // the page actually sets it. Attributes that are not defaulted (titles, copy,
  // branding, SMTP ids) are passed straight through and simply not sent to
  // OneUptime when omitted.
  status_page_definitions = {
    for key, page in var.status_page_configs : key => {
      // Access
      is_public_status_page               = coalesce(page.is_public_status_page, var.status_page_defaults.is_public_status_page)
      enable_search_engine_indexing       = coalesce(page.enable_search_engine_indexing, var.status_page_defaults.enable_search_engine_indexing)
      hide_powered_by_one_uptime_branding = coalesce(page.hide_powered_by_one_uptime_branding, var.status_page_defaults.hide_powered_by_one_uptime_branding)
      enable_mcp_server                   = coalesce(page.enable_mcp_server, var.status_page_defaults.enable_mcp_server)
      enable_master_password              = coalesce(page.enable_master_password, var.status_page_defaults.enable_master_password)
      require_sso_for_login               = coalesce(page.require_sso_for_login, var.status_page_defaults.require_sso_for_login)

      // What the page shows
      show_incidents_on_status_page                    = coalesce(page.show_incidents_on_status_page, var.status_page_defaults.show_incidents_on_status_page)
      show_incident_labels_on_status_page              = coalesce(page.show_incident_labels_on_status_page, var.status_page_defaults.show_incident_labels_on_status_page)
      show_incident_history_in_days                    = coalesce(page.show_incident_history_in_days, var.status_page_defaults.show_incident_history_in_days)
      show_announcements_on_status_page                = coalesce(page.show_announcements_on_status_page, var.status_page_defaults.show_announcements_on_status_page)
      show_announcement_history_in_days                = coalesce(page.show_announcement_history_in_days, var.status_page_defaults.show_announcement_history_in_days)
      show_scheduled_maintenance_events_on_status_page = coalesce(page.show_scheduled_maintenance_events_on_status_page, var.status_page_defaults.show_scheduled_maintenance_events_on_status_page)
      show_scheduled_event_labels_on_status_page       = coalesce(page.show_scheduled_event_labels_on_status_page, var.status_page_defaults.show_scheduled_event_labels_on_status_page)
      show_scheduled_event_history_in_days             = coalesce(page.show_scheduled_event_history_in_days, var.status_page_defaults.show_scheduled_event_history_in_days)
      show_episodes_on_status_page                     = coalesce(page.show_episodes_on_status_page, var.status_page_defaults.show_episodes_on_status_page)
      show_episode_labels_on_status_page               = coalesce(page.show_episode_labels_on_status_page, var.status_page_defaults.show_episode_labels_on_status_page)
      show_episode_history_in_days                     = coalesce(page.show_episode_history_in_days, var.status_page_defaults.show_episode_history_in_days)
      show_uptime_history_in_days                      = coalesce(page.show_uptime_history_in_days, var.status_page_defaults.show_uptime_history_in_days)
      show_overall_uptime_percent_on_status_page       = coalesce(page.show_overall_uptime_percent_on_status_page, var.status_page_defaults.show_overall_uptime_percent_on_status_page)
      overall_uptime_percent_precision                 = coalesce(page.overall_uptime_percent_precision, var.status_page_defaults.overall_uptime_percent_precision)

      // Subscribers
      show_subscriber_page_on_status_page     = coalesce(page.show_subscriber_page_on_status_page, var.status_page_defaults.show_subscriber_page_on_status_page)
      enable_email_subscribers                = coalesce(page.enable_email_subscribers, var.status_page_defaults.enable_email_subscribers)
      enable_sms_subscribers                  = coalesce(page.enable_sms_subscribers, var.status_page_defaults.enable_sms_subscribers)
      enable_slack_subscribers                = coalesce(page.enable_slack_subscribers, var.status_page_defaults.enable_slack_subscribers)
      enable_microsoft_teams_subscribers      = coalesce(page.enable_microsoft_teams_subscribers, var.status_page_defaults.enable_microsoft_teams_subscribers)
      enable_webhook_subscribers              = coalesce(page.enable_webhook_subscribers, var.status_page_defaults.enable_webhook_subscribers)
      allow_subscribers_to_choose_resources   = coalesce(page.allow_subscribers_to_choose_resources, var.status_page_defaults.allow_subscribers_to_choose_resources)
      allow_subscribers_to_choose_event_types = coalesce(page.allow_subscribers_to_choose_event_types, var.status_page_defaults.allow_subscribers_to_choose_event_types)

      // Reporting. Off by default; the rest of the report_* attributes are only
      // read by OneUptime once is_report_enabled is true.
      is_report_enabled   = coalesce(page.is_report_enabled, var.status_page_defaults.is_report_enabled)
      report_data_in_days = coalesce(page.report_data_in_days, var.status_page_defaults.report_data_in_days)

      // Branding
      default_bar_color = coalesce(page.default_bar_color, var.status_page_defaults.default_bar_color)
    }
  }

  // Nested page configuration flattened to "<page key>.<child key>" maps, so
  // every child resource is driven by a single for_each. `order` falls back to
  // the child's position in the map (keys are sorted, so it is stable) and a
  // display name falls back to the map key, keeping a minimal page short.
  status_page_groups = merge([
    for key, page in var.status_page_configs : {
      for name, group in page.groups : "${key}.${name}" => {
        status_page_key = key
        name            = coalesce(group.name, name)
        description     = group.description
        order           = coalesce(group.order, index(keys(page.groups), name) + 1)

        is_expanded_by_default   = coalesce(group.is_expanded_by_default, var.status_page_defaults.group.is_expanded_by_default)
        show_current_status      = coalesce(group.show_current_status, var.status_page_defaults.group.show_current_status)
        show_uptime_percent      = coalesce(group.show_uptime_percent, var.status_page_defaults.group.show_uptime_percent)
        uptime_percent_precision = coalesce(group.uptime_percent_precision, var.status_page_defaults.group.uptime_percent_precision)
        view_mode                = coalesce(group.view_mode, var.status_page_defaults.group.view_mode)

        row_axis_label     = group.row_axis_label
        row_axis_values    = group.row_axis_values
        column_axis_label  = group.column_axis_label
        column_axis_values = group.column_axis_values
      }
    }
  ]...)

  status_page_resources = merge([
    for key, page in var.status_page_configs : {
      for name, resource in page.resources : "${key}.${name}" => {
        status_page_key  = key
        group_key        = resource.group_key
        monitor_key      = resource.monitor_key
        monitor_id       = resource.monitor_id
        monitor_group_id = resource.monitor_group_id

        // A component name from rbac_component_mapping - publishes the monitor
        // group this module already creates for that component.
        monitor_group_key = resource.monitor_group_key

        // Falls back to the monitor's own display name before the map key, so
        // a resource can be a one-liner: { monitor_key = "gitlab" }.
        display_name = coalesce(
          resource.display_name,
          try(var.monitor_configs[resource.monitor_key].display_name, null),
          name,
        )

        display_description = resource.display_description
        display_tooltip     = resource.display_tooltip
        order               = coalesce(resource.order, index(keys(page.resources), name) + 1)

        show_current_status       = coalesce(resource.show_current_status, var.status_page_defaults.resource.show_current_status)
        show_status_history_chart = coalesce(resource.show_status_history_chart, var.status_page_defaults.resource.show_status_history_chart)
        show_uptime_percent       = coalesce(resource.show_uptime_percent, var.status_page_defaults.resource.show_uptime_percent)
        uptime_percent_precision  = coalesce(resource.uptime_percent_precision, var.status_page_defaults.resource.uptime_percent_precision)

        row_axis_value    = resource.row_axis_value
        column_axis_value = resource.column_axis_value
      }
    }
  ]...)

  // Label-driven alternative to listing resources one by one: every monitor
  // carrying the named labels is published on the page automatically, so a new
  // monitor shows up without touching the status page config.
  status_page_monitor_rules = merge([
    for key, page in var.status_page_configs : {
      for name, rule in page.monitor_rules : "${key}.${name}" => {
        status_page_key = key
        group_key       = rule.group_key
        name            = coalesce(rule.name, name)
        description     = rule.description
        is_enabled      = coalesce(rule.is_enabled, true)

        label_names                 = rule.label_names
        monitor_name_pattern        = rule.monitor_name_pattern
        monitor_description_pattern = rule.monitor_description_pattern

        show_current_status       = coalesce(rule.show_current_status, var.status_page_defaults.resource.show_current_status)
        show_status_history_chart = coalesce(rule.show_status_history_chart, var.status_page_defaults.resource.show_status_history_chart)
        show_uptime_percent       = coalesce(rule.show_uptime_percent, var.status_page_defaults.resource.show_uptime_percent)
        uptime_percent_precision  = coalesce(rule.uptime_percent_precision, var.status_page_defaults.resource.uptime_percent_precision)
      }
    }
  ]...)

  status_page_header_links = merge([
    for key, page in var.status_page_configs : {
      for name, link in page.header_links : "${key}.${name}" => {
        status_page_key = key
        title           = coalesce(link.title, name)
        link            = link.link
        order           = coalesce(link.order, index(keys(page.header_links), name) + 1)
      }
    }
  ]...)

  status_page_footer_links = merge([
    for key, page in var.status_page_configs : {
      for name, link in page.footer_links : "${key}.${name}" => {
        status_page_key = key
        title           = coalesce(link.title, name)
        link            = link.link
        order           = coalesce(link.order, index(keys(page.footer_links), name) + 1)
      }
    }
  ]...)

  // Colour of each bar in the uptime history chart, by uptime threshold. The
  // page inherits the shipped green/amber/red bands unless it sets its own.
  status_page_bar_colors = merge([
    for key, page in var.status_page_configs : {
      for i, band in coalesce(page.history_chart_bar_colors, var.status_page_defaults.history_chart_bar_colors) :
      "${key}.${band.uptime_percent_greater_than_or_equal_to}" => {
        status_page_key                         = key
        bar_color                               = band.bar_color
        uptime_percent_greater_than_or_equal_to = band.uptime_percent_greater_than_or_equal_to
        order                                   = coalesce(band.order, i + 1)
      }
    }
  ]...)

  status_page_private_users = merge([
    for key, page in var.status_page_configs : {
      for name, user in page.private_users : "${key}.${name}" => merge(user, { status_page_key = key })
    }
  ]...)

  status_page_subscribers = merge([
    for key, page in var.status_page_configs : {
      for name, subscriber in page.subscribers : "${key}.${name}" => {
        status_page_key = key
        internal_note   = coalesce(subscriber.internal_note, "Managed by Terraform (${name})")

        subscriber_email                     = subscriber.subscriber_email
        subscriber_phone                     = subscriber.subscriber_phone
        subscriber_webhook                   = subscriber.subscriber_webhook
        slack_workspace_name                 = subscriber.slack_workspace_name
        slack_incoming_webhook_url           = subscriber.slack_incoming_webhook_url
        microsoft_teams_workspace_name       = subscriber.microsoft_teams_workspace_name
        microsoft_teams_incoming_webhook_url = subscriber.microsoft_teams_incoming_webhook_url

        status_page_event_types          = subscriber.status_page_event_types
        is_subscribed_to_all_resources   = coalesce(subscriber.is_subscribed_to_all_resources, var.status_page_defaults.subscriber.is_subscribed_to_all_resources)
        is_subscribed_to_all_event_types = coalesce(subscriber.is_subscribed_to_all_event_types, var.status_page_defaults.subscriber.is_subscribed_to_all_event_types)
        send_you_have_subscribed_message = coalesce(subscriber.send_you_have_subscribed_message, var.status_page_defaults.subscriber.send_you_have_subscribed_message)

        // A subscriber added by Terraform is one the operator vouched for, so
        // it does not have to confirm by email before it is notified.
        is_subscription_confirmed = coalesce(subscriber.is_subscription_confirmed, true)
      }
    }
  ]...)

  status_page_domains = {
    for key, page in var.status_page_configs :
    key => merge(page.domain, { status_page_key = key }) if page.domain != null
  }

  status_page_owner_teams = merge([
    for key, page in var.status_page_configs : {
      for group in page.owner_group_names : "${key}.${group}" => {
        status_page_key = key
        group           = group
      }
    }
  ]...)

  status_page_owner_users = merge([
    for key, page in var.status_page_configs : {
      for user_id in page.owner_user_ids : "${key}.${user_id}" => {
        status_page_key = key
        user_id         = user_id
      }
    }
  ]...)

  // Domain names looked up once each, however many pages reference them.
  status_page_domain_names = toset([for domain in local.status_page_domains : domain.domain_name])

  // Announcements are project-level in OneUptime (they carry the set of pages
  // they appear on), so they are configured next to the pages rather than
  // inside one. An announcement that names no pages appears on all of them.
  status_page_announcements = {
    for key, announcement in var.status_page_announcements : key => merge(announcement, {
      status_page_keys = length(announcement.status_page_keys) > 0 ? announcement.status_page_keys : toset(keys(var.status_page_configs))

      should_status_page_subscribers_be_notified = coalesce(
        announcement.should_status_page_subscribers_be_notified,
        var.status_page_defaults.announcement.should_status_page_subscribers_be_notified,
      )
    })
  }
}
