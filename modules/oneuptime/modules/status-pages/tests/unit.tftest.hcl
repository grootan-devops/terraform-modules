// Unit tests for modules/status-pages, called directly with the normalized
// inputs the parent module (modules/oneuptime) would pass it. No OneUptime
// instance or API key: the mock provider answers every call, so
// `command = apply` only builds state in memory.
mock_provider "oneuptime" {}

// The custom domain must already exist in OneUptime; give the lookup a fixed id.
override_data {
  target = data.oneuptime_domain.by_name
  values = { id = "domain-example" }
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

  // Read only for a published monitor's display_name.
  monitor_configs = {
    "api" = {
      display_name = "Core API"
      monitor_type = "API"
      target       = "https://api.example.com/health"
    }
  }

  // From the monitors submodule.
  monitor_ids = {
    "api" = "monitor-api"
  }

  monitor_group_ids = {
    "platform"    = "monitor-group-platform"
    "application" = "monitor-group-application"
  }

  // status_page_defaults = {} after the parent's optional() defaults
  // (modules/oneuptime/variables-status-pages.tf).
  status_page_defaults = {
    is_public_status_page                            = true
    enable_search_engine_indexing                    = true
    hide_powered_by_one_uptime_branding              = false
    enable_mcp_server                                = false
    enable_master_password                           = false
    require_sso_for_login                            = false
    show_incidents_on_status_page                    = true
    show_incident_labels_on_status_page              = false
    show_incident_history_in_days                    = 30
    show_announcements_on_status_page                = true
    show_announcement_history_in_days                = 14
    show_scheduled_maintenance_events_on_status_page = true
    show_scheduled_event_labels_on_status_page       = false
    show_scheduled_event_history_in_days             = 14
    show_episodes_on_status_page                     = true
    show_episode_labels_on_status_page               = false
    show_episode_history_in_days                     = 30
    show_uptime_history_in_days                      = 90
    show_overall_uptime_percent_on_status_page       = true
    overall_uptime_percent_precision                 = "99% (No Decimal)"
    show_subscriber_page_on_status_page              = false
    enable_email_subscribers                         = false
    enable_sms_subscribers                           = false
    enable_slack_subscribers                         = false
    enable_microsoft_teams_subscribers               = false
    enable_webhook_subscribers                       = false
    allow_subscribers_to_choose_resources            = true
    allow_subscribers_to_choose_event_types          = true
    is_report_enabled                                = false
    report_data_in_days                              = 7
    default_bar_color                                = "#0F9D58"
    group = {
      is_expanded_by_default   = true
      show_current_status      = true
      show_uptime_percent      = true
      uptime_percent_precision = "99% (No Decimal)"
      view_mode                = "List"
    }
    resource = {
      show_current_status       = true
      show_status_history_chart = true
      show_uptime_percent       = true
      uptime_percent_precision  = "99% (No Decimal)"
    }
    subscriber = {
      is_subscribed_to_all_resources   = true
      is_subscribed_to_all_event_types = true
      send_you_have_subscribed_message = true
    }
    announcement = {
      should_status_page_subscribers_be_notified = true
    }
    history_chart_bar_colors = []
  }

  // Helpers, not module inputs: what the parent's map(object(...)) types make
  // of an entry that sets nothing - every attribute present, null where unset
  // and empty where the type defaults a collection. Entries below merge their
  // own values over these.
  blank_page = {
    name                                                    = null
    description                                             = null
    label_names                                             = null
    page_title                                              = null
    page_description                                        = null
    overview_page_description                               = null
    copyright_text                                          = null
    default_language                                        = null
    enabled_languages                                       = null
    custom_fields                                           = null
    is_public_status_page                                   = null
    enable_search_engine_indexing                           = null
    hide_powered_by_one_uptime_branding                     = null
    enable_mcp_server                                       = null
    enable_master_password                                  = null
    master_password                                         = null
    require_sso_for_login                                   = null
    ip_whitelist                                            = null
    show_incidents_on_status_page                           = null
    show_incident_labels_on_status_page                     = null
    show_incident_history_in_days                           = null
    show_announcements_on_status_page                       = null
    show_announcement_history_in_days                       = null
    show_scheduled_maintenance_events_on_status_page        = null
    show_scheduled_event_labels_on_status_page              = null
    show_scheduled_event_history_in_days                    = null
    show_episodes_on_status_page                            = null
    show_episode_labels_on_status_page                      = null
    show_episode_history_in_days                            = null
    show_uptime_history_in_days                             = null
    show_overall_uptime_percent_on_status_page              = null
    overall_uptime_percent_precision                        = null
    show_subscriber_page_on_status_page                     = null
    enable_email_subscribers                                = null
    enable_sms_subscribers                                  = null
    enable_slack_subscribers                                = null
    enable_microsoft_teams_subscribers                      = null
    enable_webhook_subscribers                              = null
    allow_subscribers_to_choose_resources                   = null
    allow_subscribers_to_choose_event_types                 = null
    subscriber_timezones                                    = null
    subscriber_email_notification_footer_text               = null
    enable_custom_subscriber_email_notification_footer_text = null
    enable_embedded_overall_status                          = null
    embedded_overall_status_token                           = null
    is_report_enabled                                       = null
    report_data_in_days                                     = null
    report_recurring_interval                               = null
    report_period_type                                      = null
    report_start_date_time                                  = null
    report_timezone                                         = null
    logo_file_id                                            = null
    logo_alt_text                                           = null
    favicon_file_id                                         = null
    cover_image_file_id                                     = null
    cover_image_alt_text                                    = null
    default_bar_color                                       = null
    custom_css                                              = null
    custom_java_script                                      = null
    header_html                                             = null
    footer_html                                             = null
    smtp_config_id                                          = null
    call_sms_config_id                                      = null
    history_chart_bar_colors                                = null
    groups                                                  = {}
    resources                                               = {}
    monitor_rules                                           = {}
    header_links                                            = {}
    footer_links                                            = {}
    domain                                                  = null
    private_users                                           = {}
    subscribers                                             = {}
    owner_group_names                                       = []
    owner_user_ids                                          = []
  }

  blank_group = {
    name                     = null
    description              = null
    order                    = null
    is_expanded_by_default   = null
    show_current_status      = null
    show_uptime_percent      = null
    uptime_percent_precision = null
    view_mode                = null
    row_axis_label           = null
    row_axis_values          = null
    column_axis_label        = null
    column_axis_values       = null
  }

  blank_resource = {
    monitor_key               = null
    monitor_group_key         = null
    monitor_id                = null
    monitor_group_id          = null
    group_key                 = null
    display_name              = null
    display_description       = null
    display_tooltip           = null
    order                     = null
    show_current_status       = null
    show_status_history_chart = null
    show_uptime_percent       = null
    uptime_percent_precision  = null
    row_axis_value            = null
    column_axis_value         = null
  }

  blank_monitor_rule = {
    name                        = null
    description                 = null
    is_enabled                  = null
    group_key                   = null
    label_names                 = null
    monitor_name_pattern        = null
    monitor_description_pattern = null
    show_current_status         = null
    show_status_history_chart   = null
    show_uptime_percent         = null
    uptime_percent_precision    = null
  }

  blank_subscriber = {
    subscriber_email                     = null
    subscriber_phone                     = null
    subscriber_webhook                   = null
    slack_workspace_name                 = null
    slack_incoming_webhook_url           = null
    microsoft_teams_workspace_name       = null
    microsoft_teams_incoming_webhook_url = null
    status_page_event_types              = null
    is_subscribed_to_all_resources       = null
    is_subscribed_to_all_event_types     = null
    is_subscription_confirmed            = null
    send_you_have_subscribed_message     = null
    internal_note                        = null
  }

  status_page_configs = {
    // A page that sets most of what a page can set.
    "core" = merge(var.blank_page, {
      name                             = "Core Status"
      description                      = "Public status page for core services"
      label_names                      = toset(["platform", "core"])
      page_title                       = "Core service status"
      is_public_status_page            = false
      show_uptime_history_in_days      = 60
      overall_uptime_percent_precision = "99% (Two Decimal)"
      enable_email_subscribers         = true
      default_bar_color                = "#123456"

      history_chart_bar_colors = [
        { uptime_percent_greater_than_or_equal_to = 99, bar_color = "#0F9D58", order = null },
        { uptime_percent_greater_than_or_equal_to = 95, bar_color = "#F4B400", order = null },
        { uptime_percent_greater_than_or_equal_to = 0.01, bar_color = "#DB4437", order = 10 },
      ]

      groups = {
        "platform"    = merge(var.blank_group, { name = "Platform services" })
        "application" = var.blank_group
        "tools" = merge(var.blank_group, {
          order                  = 10
          is_expanded_by_default = false
          view_mode              = "Grid"
          row_axis_label         = "Region"
          row_axis_values        = "eu,us"
          column_axis_label      = "Tier"
          column_axis_values     = "web,db"
        })
      }

      resources = {
        "api" = merge(var.blank_resource, {
          monitor_key = "api"
          group_key   = "application"
        })
        "platform-group" = merge(var.blank_resource, {
          monitor_group_key = "platform"
          group_key         = "platform"
          display_name      = "Platform"
        })
        "external" = merge(var.blank_resource, {
          monitor_id               = "external-monitor-id"
          order                    = 7
          show_uptime_percent      = false
          uptime_percent_precision = "99% (One Decimal)"
        })
      }

      monitor_rules = {
        "platform" = merge(var.blank_monitor_rule, {
          group_key   = "platform"
          label_names = toset(["platform"])
        })
        "everything" = merge(var.blank_monitor_rule, {
          name                      = "All monitors"
          description               = "Every monitor in the project"
          is_enabled                = false
          group_key                 = "tools"
          monitor_name_pattern      = ".*"
          show_status_history_chart = false
        })
      }

      header_links = {
        "Docs"    = { link = "https://docs.example.com", title = null, order = null }
        "Support" = { link = "https://support.example.com", title = "Get help", order = 5 }
      }

      footer_links = {
        "Privacy" = { link = "https://example.com/privacy", title = null, order = null }
      }

      domain = {
        domain_name = "example.com"
        subdomain   = "status"
      }

      private_users = {
        "reviewer" = { email = "reviewer@example.com", password = null, is_sso_user = true }
      }

      subscribers = {
        "oncall" = merge(var.blank_subscriber, { subscriber_email = "oncall@example.com" })
        "webhook" = merge(var.blank_subscriber, {
          subscriber_webhook               = "https://example.com/hook"
          status_page_event_types          = "Incident"
          is_subscribed_to_all_event_types = false
          is_subscription_confirmed        = false
          internal_note                    = "Incident webhook"
        })
      }

      owner_group_names = toset(["devops"])
      owner_user_ids    = toset(["user-1234"])
    })

    // A page that sets nothing.
    "internal" = var.blank_page
  }

  status_page_announcements = {
    // No status_page_keys: every page.
    "upgrade" = {
      title                                      = "Platform upgrade"
      description                                = "Services may be briefly unavailable."
      show_announcement_at                       = "2026-09-01T09:00:00Z"
      end_announcement_at                        = null
      status_page_keys                           = toset([])
      monitor_keys                               = toset([])
      should_status_page_subscribers_be_notified = null
    }
    "api-maintenance" = {
      title                                      = "API maintenance"
      description                                = "The API will be read-only for 30 minutes."
      show_announcement_at                       = "2026-09-02T09:00:00Z"
      end_announcement_at                        = "2026-09-02T09:30:00Z"
      status_page_keys                           = toset(["core"])
      monitor_keys                               = toset(["api"])
      should_status_page_subscribers_be_notified = false
    }
  }
}

run "pages_are_named_after_name_or_key" {
  command = plan

  assert {
    condition     = toset(keys(oneuptime_status_page.this)) == toset(["core", "internal"])
    error_message = "Expected one status page per status_page_configs entry."
  }

  assert {
    condition     = oneuptime_status_page.this["core"].name == "Core Status"
    error_message = "A page with a name should be named after it."
  }

  assert {
    condition     = oneuptime_status_page.this["internal"].name == "internal"
    error_message = "A page without a name should be named after its key."
  }

  assert {
    condition = (
      oneuptime_status_page.this["core"].description == "Public status page for core services"
      && oneuptime_status_page.this["core"].page_title == "Core service status"
    )
    error_message = "Description and copy should pass straight through."
  }

  assert {
    condition     = oneuptime_status_page.this["core"].labels == toset(["label-platform", "label-core"])
    error_message = "A page with label_names should carry exactly those labels."
  }

  assert {
    condition     = oneuptime_status_page.this["internal"].labels == toset(["label-core"])
    error_message = "A page without label_names should carry the application label."
  }
}

run "a_silent_page_takes_every_default" {
  command = plan

  assert {
    condition = (
      oneuptime_status_page.this["internal"].is_public_status_page == true
      && oneuptime_status_page.this["internal"].enable_search_engine_indexing == true
      && oneuptime_status_page.this["internal"].hide_powered_by_one_uptime_branding == false
      && oneuptime_status_page.this["internal"].enable_mcp_server == false
      && oneuptime_status_page.this["internal"].enable_master_password == false
      && oneuptime_status_page.this["internal"].require_sso_for_login == false
    )
    error_message = "A silent page should be public, indexable and unauthenticated."
  }

  assert {
    condition = (
      oneuptime_status_page.this["internal"].show_incidents_on_status_page == true
      && oneuptime_status_page.this["internal"].show_incident_labels_on_status_page == false
      && oneuptime_status_page.this["internal"].show_incident_history_in_days == 30
      && oneuptime_status_page.this["internal"].show_announcements_on_status_page == true
      && oneuptime_status_page.this["internal"].show_announcement_history_in_days == 14
      && oneuptime_status_page.this["internal"].show_scheduled_maintenance_events_on_status_page == true
      && oneuptime_status_page.this["internal"].show_scheduled_event_labels_on_status_page == false
      && oneuptime_status_page.this["internal"].show_scheduled_event_history_in_days == 14
      && oneuptime_status_page.this["internal"].show_episodes_on_status_page == true
      && oneuptime_status_page.this["internal"].show_episode_labels_on_status_page == false
      && oneuptime_status_page.this["internal"].show_episode_history_in_days == 30
    )
    error_message = "A silent page should show incidents, announcements, maintenance and episodes, without their labels."
  }

  assert {
    condition = (
      oneuptime_status_page.this["internal"].show_uptime_history_in_days == 90
      && oneuptime_status_page.this["internal"].show_overall_uptime_percent_on_status_page == true
      && oneuptime_status_page.this["internal"].overall_uptime_percent_precision == "99% (No Decimal)"
      && oneuptime_status_page.this["internal"].default_bar_color == "#0F9D58"
    )
    error_message = "A silent page should show 90 days of uptime at whole-number precision with the default bar colour."
  }

  assert {
    condition = (
      oneuptime_status_page.this["internal"].show_subscriber_page_on_status_page == false
      && oneuptime_status_page.this["internal"].enable_email_subscribers == false
      && oneuptime_status_page.this["internal"].enable_sms_subscribers == false
      && oneuptime_status_page.this["internal"].enable_slack_subscribers == false
      && oneuptime_status_page.this["internal"].enable_microsoft_teams_subscribers == false
      && oneuptime_status_page.this["internal"].enable_webhook_subscribers == false
      && oneuptime_status_page.this["internal"].allow_subscribers_to_choose_resources == true
      && oneuptime_status_page.this["internal"].allow_subscribers_to_choose_event_types == true
      && oneuptime_status_page.this["internal"].is_report_enabled == false
      && oneuptime_status_page.this["internal"].report_data_in_days == 7
    )
    error_message = "A silent page should have every subscriber channel and reports off."
  }
}

run "page_values_win_over_the_defaults" {
  command = plan

  assert {
    condition = (
      oneuptime_status_page.this["core"].is_public_status_page == false
      && oneuptime_status_page.this["core"].show_uptime_history_in_days == 60
      && oneuptime_status_page.this["core"].overall_uptime_percent_precision == "99% (Two Decimal)"
      && oneuptime_status_page.this["core"].enable_email_subscribers == true
      && oneuptime_status_page.this["core"].default_bar_color == "#123456"
    )
    error_message = "A page's own values should win over status_page_defaults."
  }

  assert {
    condition = (
      oneuptime_status_page.this["core"].enable_search_engine_indexing == true
      && oneuptime_status_page.this["core"].show_incident_history_in_days == 30
    )
    error_message = "Attributes a page does not set should still come from the defaults."
  }
}

run "stack_defaults_apply_where_a_page_is_silent" {
  command = plan

  variables {
    status_page_defaults = merge(var.status_page_defaults, {
      show_uptime_history_in_days   = 45
      enable_search_engine_indexing = false
      group                         = merge(var.status_page_defaults.group, { view_mode = "Grid" })
      resource                      = merge(var.status_page_defaults.resource, { uptime_percent_precision = "99% (One Decimal)" })
      subscriber                    = merge(var.status_page_defaults.subscriber, { send_you_have_subscribed_message = false })
      announcement                  = { should_status_page_subscribers_be_notified = false }
    })
  }

  assert {
    condition = (
      oneuptime_status_page.this["internal"].show_uptime_history_in_days == 45
      && oneuptime_status_page.this["internal"].enable_search_engine_indexing == false
      && oneuptime_status_page.this["core"].show_uptime_history_in_days == 60
    )
    error_message = "Stack defaults should reach a silent page, and lose to a page's own value."
  }

  assert {
    condition = (
      oneuptime_status_page_group.this["core.application"].view_mode == "Grid"
      && oneuptime_status_page_group.this["core.tools"].view_mode == "Grid"
    )
    error_message = "status_page_defaults.group should reach every group that does not set its own."
  }

  assert {
    condition = (
      oneuptime_status_page_resource.this["core.api"].uptime_percent_precision == "99% (One Decimal)"
      && oneuptime_status_page_monitor_rule.this["core.platform"].uptime_percent_precision == "99% (One Decimal)"
    )
    error_message = "status_page_defaults.resource should reach resources and monitor rules alike."
  }

  assert {
    condition     = oneuptime_status_page_subscriber.this["core.oncall"].send_you_have_subscribed_message == false
    error_message = "status_page_defaults.subscriber should reach every subscriber."
  }

  assert {
    condition     = oneuptime_status_page_announcement.this["upgrade"].should_status_page_subscribers_be_notified == false
    error_message = "status_page_defaults.announcement should reach an announcement that does not set its own."
  }
}

run "groups_fall_back_to_their_key_and_sorted_position" {
  command = plan

  assert {
    condition = (
      oneuptime_status_page_group.this["core.platform"].name == "Platform services"
      && oneuptime_status_page_group.this["core.application"].name == "application"
      && oneuptime_status_page_group.this["core.tools"].name == "tools"
    )
    error_message = "A group should be named after its name, else its key."
  }

  assert {
    condition = (
      oneuptime_status_page_group.this["core.application"].order == 1
      && oneuptime_status_page_group.this["core.platform"].order == 2
      && oneuptime_status_page_group.this["core.tools"].order == 10
    )
    error_message = "A group's order should be its own, else its position among the sorted keys."
  }

  assert {
    condition = (
      oneuptime_status_page_group.this["core.application"].is_expanded_by_default == true
      && oneuptime_status_page_group.this["core.application"].show_current_status == true
      && oneuptime_status_page_group.this["core.application"].show_uptime_percent == true
      && oneuptime_status_page_group.this["core.application"].uptime_percent_precision == "99% (No Decimal)"
      && oneuptime_status_page_group.this["core.application"].view_mode == "List"
    )
    error_message = "A silent group should take status_page_defaults.group."
  }

  assert {
    condition = (
      oneuptime_status_page_group.this["core.tools"].is_expanded_by_default == false
      && oneuptime_status_page_group.this["core.tools"].view_mode == "Grid"
      && oneuptime_status_page_group.this["core.tools"].row_axis_values == "eu,us"
      && oneuptime_status_page_group.this["core.tools"].column_axis_label == "Tier"
    )
    error_message = "A group's own view settings and grid axes should pass through."
  }
}

run "resources_resolve_their_monitor_and_fall_back_on_names" {
  command = plan

  assert {
    condition     = toset(keys(oneuptime_status_page_resource.this)) == toset(["core.api", "core.platform-group", "core.external"])
    error_message = "Resources should be keyed \"<page>.<resource>\"."
  }

  assert {
    condition = (
      oneuptime_status_page_resource.this["core.api"].monitor_id == "monitor-api"
      && oneuptime_status_page_resource.this["core.api"].display_name == "Core API"
    )
    error_message = "A monitor_key resource should publish that monitor's id under its display_name."
  }

  assert {
    condition = (
      oneuptime_status_page_resource.this["core.platform-group"].monitor_group_id == "monitor-group-platform"
      && oneuptime_status_page_resource.this["core.platform-group"].display_name == "Platform"
    )
    error_message = "A monitor_group_key resource should publish that component's monitor group under its own display_name."
  }

  assert {
    condition = (
      oneuptime_status_page_resource.this["core.external"].monitor_id == "external-monitor-id"
      && oneuptime_status_page_resource.this["core.external"].display_name == "external"
    )
    error_message = "A monitor_id resource should pass the id through and fall back to its key for a name."
  }

  assert {
    condition = (
      oneuptime_status_page_resource.this["core.api"].order == 1
      && oneuptime_status_page_resource.this["core.external"].order == 7
      && oneuptime_status_page_resource.this["core.platform-group"].order == 3
    )
    error_message = "A resource's order should be its own, else its position among the sorted keys."
  }

  assert {
    condition = (
      oneuptime_status_page_resource.this["core.api"].show_current_status == true
      && oneuptime_status_page_resource.this["core.api"].show_status_history_chart == true
      && oneuptime_status_page_resource.this["core.api"].show_uptime_percent == true
      && oneuptime_status_page_resource.this["core.api"].uptime_percent_precision == "99% (No Decimal)"
      && oneuptime_status_page_resource.this["core.external"].show_uptime_percent == false
      && oneuptime_status_page_resource.this["core.external"].uptime_percent_precision == "99% (One Decimal)"
    )
    error_message = "Resources should take status_page_defaults.resource unless they set their own."
  }
}

run "monitor_rules_publish_by_label_or_pattern" {
  command = plan

  assert {
    condition = (
      oneuptime_status_page_monitor_rule.this["core.platform"].name == "platform"
      && oneuptime_status_page_monitor_rule.this["core.platform"].is_enabled == true
      && oneuptime_status_page_monitor_rule.this["core.platform"].monitor_labels == toset(["label-platform"])
    )
    error_message = "A label rule should be named after its key, enabled, and match the named labels' ids."
  }

  assert {
    condition = (
      oneuptime_status_page_monitor_rule.this["core.everything"].name == "All monitors"
      && oneuptime_status_page_monitor_rule.this["core.everything"].description == "Every monitor in the project"
      && oneuptime_status_page_monitor_rule.this["core.everything"].is_enabled == false
      && oneuptime_status_page_monitor_rule.this["core.everything"].monitor_name_pattern == ".*"
    )
    error_message = "A pattern rule should keep its own name, description, is_enabled and pattern."
  }

  assert {
    condition = (
      oneuptime_status_page_monitor_rule.this["core.everything"].show_status_history_chart == false
      && oneuptime_status_page_monitor_rule.this["core.everything"].show_current_status == true
      && oneuptime_status_page_monitor_rule.this["core.everything"].show_uptime_percent == true
    )
    error_message = "Monitor rules should take status_page_defaults.resource unless they set their own."
  }
}

run "links_fall_back_to_their_key_and_sorted_position" {
  command = plan

  assert {
    condition = (
      oneuptime_status_page_header_link.this["core.Docs"].title == "Docs"
      && oneuptime_status_page_header_link.this["core.Docs"].link == "https://docs.example.com"
      && oneuptime_status_page_header_link.this["core.Docs"].order == 1
    )
    error_message = "A header link without title or order should take its key and its sorted position."
  }

  assert {
    condition = (
      oneuptime_status_page_header_link.this["core.Support"].title == "Get help"
      && oneuptime_status_page_header_link.this["core.Support"].order == 5
    )
    error_message = "A header link's own title and order should win."
  }

  assert {
    condition = (
      oneuptime_status_page_footer_link.this["core.Privacy"].title == "Privacy"
      && oneuptime_status_page_footer_link.this["core.Privacy"].link == "https://example.com/privacy"
      && oneuptime_status_page_footer_link.this["core.Privacy"].order == 1
    )
    error_message = "Footer links should fall back the same way as header links."
  }
}

run "a_pages_uptime_bands_replace_the_empty_default" {
  command = plan

  assert {
    condition     = toset(keys(oneuptime_status_page_history_chart_bar_color.this)) == toset(["core.99", "core.95", "core.0.01"])
    error_message = "Only the page that sets bands should get them, keyed \"<page>.<threshold>\"."
  }

  assert {
    condition = (
      oneuptime_status_page_history_chart_bar_color.this["core.99"].order == 1
      && oneuptime_status_page_history_chart_bar_color.this["core.95"].order == 2
      && oneuptime_status_page_history_chart_bar_color.this["core.0.01"].order == 10
      && oneuptime_status_page_history_chart_bar_color.this["core.95"].bar_color == "#F4B400"
    )
    error_message = "A band's order should be its own, else its position in the list."
  }
}

run "subscribers_private_users_and_owners" {
  command = plan

  assert {
    condition = (
      oneuptime_status_page_subscriber.this["core.oncall"].subscriber_email == "oncall@example.com"
      && oneuptime_status_page_subscriber.this["core.oncall"].internal_note == "Managed by Terraform (oncall)"
      && oneuptime_status_page_subscriber.this["core.oncall"].is_subscription_confirmed == true
      && oneuptime_status_page_subscriber.this["core.oncall"].is_subscribed_to_all_resources == true
      && oneuptime_status_page_subscriber.this["core.oncall"].is_subscribed_to_all_event_types == true
      && oneuptime_status_page_subscriber.this["core.oncall"].send_you_have_subscribed_message == true
    )
    error_message = "A silent subscriber should be confirmed, subscribed to everything and noted as Terraform-managed."
  }

  assert {
    condition = (
      oneuptime_status_page_subscriber.this["core.webhook"].subscriber_webhook == "https://example.com/hook"
      && oneuptime_status_page_subscriber.this["core.webhook"].status_page_event_types == "Incident"
      && oneuptime_status_page_subscriber.this["core.webhook"].is_subscribed_to_all_event_types == false
      && oneuptime_status_page_subscriber.this["core.webhook"].is_subscription_confirmed == false
      && oneuptime_status_page_subscriber.this["core.webhook"].internal_note == "Incident webhook"
    )
    error_message = "A subscriber's own values should win."
  }

  assert {
    condition = (
      oneuptime_status_page_private_user.this["core.reviewer"].email == "reviewer@example.com"
      && oneuptime_status_page_private_user.this["core.reviewer"].is_sso_user == true
    )
    error_message = "Private users should pass through, keyed \"<page>.<user>\"."
  }

  assert {
    condition = (
      keys(oneuptime_status_page_team_owner.this) == ["core.devops"]
      && oneuptime_status_page_team_owner.this["core.devops"].team_id == "team-devops"
    )
    error_message = "owner_group_names should resolve to team ids."
  }

  assert {
    condition = (
      keys(oneuptime_status_page_user_owner.this) == ["core.user-1234"]
      && oneuptime_status_page_user_owner.this["core.user-1234"].user_id == "user-1234"
    )
    error_message = "owner_user_ids should pass through as raw ids."
  }

  assert {
    condition = (
      keys(oneuptime_status_page_domain.this) == ["core"]
      && oneuptime_status_page_domain.this["core"].domain_id == "domain-example"
      && oneuptime_status_page_domain.this["core"].subdomain == "status"
    )
    error_message = "A page's domain should be looked up by name and attached with its subdomain."
  }
}

run "announcements_without_pages_target_every_page" {
  command = plan

  assert {
    condition     = local.status_page_announcements["upgrade"].status_page_keys == toset(["core", "internal"])
    error_message = "An announcement with no status_page_keys should target every page."
  }

  assert {
    condition     = local.status_page_announcements["api-maintenance"].status_page_keys == toset(["core"])
    error_message = "An announcement with status_page_keys should target only those pages."
  }

  assert {
    condition = (
      oneuptime_status_page_announcement.this["upgrade"].title == "Platform upgrade"
      && oneuptime_status_page_announcement.this["upgrade"].show_announcement_at == "2026-09-01T09:00:00Z"
      && oneuptime_status_page_announcement.this["upgrade"].should_status_page_subscribers_be_notified == true
    )
    error_message = "An announcement should pass its copy through and notify subscribers by default."
  }

  assert {
    condition = (
      oneuptime_status_page_announcement.this["api-maintenance"].monitors == toset(["monitor-api"])
      && oneuptime_status_page_announcement.this["api-maintenance"].end_announcement_at == "2026-09-02T09:30:00Z"
      && oneuptime_status_page_announcement.this["api-maintenance"].should_status_page_subscribers_be_notified == false
    )
    error_message = "monitor_keys should resolve to monitor ids, and the announcement's own notify flag should win."
  }
}

run "one_owner_and_label_rule_per_component_once_a_page_exists" {
  command = plan

  assert {
    condition = (
      toset(keys(oneuptime_status_page_owner_rule.this)) == toset(["platform", "application"])
      && toset(keys(oneuptime_status_page_label_rule.this)) == toset(["platform", "application"])
    )
    error_message = "Expected one status page owner rule and label rule per component."
  }

  assert {
    condition = alltrue([
      for key, rule in oneuptime_status_page_owner_rule.this :
      rule.name == key
      && rule.description == "status page owner rule for component ${key}"
      && rule.status_page_labels == toset(["label-${key}"])
      && rule.notify_owners
      && rule.is_enabled
    ])
    error_message = "Owner rules should be named after the component, match its label and notify owners."
  }

  assert {
    condition     = oneuptime_status_page_owner_rule.this["application"].owner_teams == toset(["team-developers", "team-devops"])
    error_message = "A component owned by two groups should get one owner rule naming both teams."
  }

  assert {
    condition = alltrue([
      for key, rule in oneuptime_status_page_label_rule.this :
      rule.name == key
      && rule.description == "status page label rule for component ${key}"
      && rule.status_page_labels == toset(["label-${key}"])
      && rule.is_enabled
    ])
    error_message = "Label rules should be named after the component and match its label."
  }

  // The component label is what the rule matches on, so it only adds the
  // owning groups' labels - see main.tf.
  assert {
    condition     = oneuptime_status_page_label_rule.this["application"].labels_to_add == toset(["label-developers", "label-devops"])
    error_message = "The application label rule should add both owning groups' labels."
  }
}

run "no_pages_means_no_component_rules" {
  command = plan

  variables {
    status_page_configs       = {}
    status_page_announcements = {}
  }

  assert {
    condition = (
      length(oneuptime_status_page.this) == 0
      && length(oneuptime_status_page_owner_rule.this) == 0
      && length(oneuptime_status_page_label_rule.this) == 0
    )
    error_message = "With no status pages, no page, owner rule or label rule should be created."
  }
}

run "children_attach_to_their_page_and_group" {
  command = apply

  assert {
    condition = alltrue([
      for key, group in oneuptime_status_page_group.this :
      group.status_page_id == oneuptime_status_page.this["core"].id
    ])
    error_message = "Every group should sit on its own page."
  }

  assert {
    condition = (
      oneuptime_status_page_resource.this["core.api"].status_page_group_id == oneuptime_status_page_group.this["core.application"].id
      && oneuptime_status_page_resource.this["core.platform-group"].status_page_group_id == oneuptime_status_page_group.this["core.platform"].id
      && oneuptime_status_page_monitor_rule.this["core.everything"].status_page_group_id == oneuptime_status_page_group.this["core.tools"].id
    )
    error_message = "group_key should resolve to the id of that group on the same page."
  }

  assert {
    condition = alltrue([
      for child in concat(
        values(oneuptime_status_page_resource.this),
        values(oneuptime_status_page_monitor_rule.this),
        values(oneuptime_status_page_header_link.this),
        values(oneuptime_status_page_subscriber.this),
        values(oneuptime_status_page_team_owner.this),
        values(oneuptime_status_page_domain.this),
      ) : child.status_page_id == oneuptime_status_page.this["core"].id
    ])
    error_message = "Every child of the core page should carry the core page's id."
  }

  assert {
    condition     = oneuptime_status_page_announcement.this["upgrade"].status_pages == toset([oneuptime_status_page.this["core"].id, oneuptime_status_page.this["internal"].id])
    error_message = "An announcement with no status_page_keys should be published on every page's id."
  }

  assert {
    condition     = oneuptime_status_page_announcement.this["api-maintenance"].status_pages == toset([oneuptime_status_page.this["core"].id])
    error_message = "An announcement with status_page_keys should be published on those pages' ids only."
  }

  assert {
    condition     = output.status_page_ids == { for key, page in oneuptime_status_page.this : key => page.id }
    error_message = "status_page_ids should map every page key to its id."
  }

  assert {
    condition     = output.status_page_group_ids == { for key, group in oneuptime_status_page_group.this : key => group.id }
    error_message = "status_page_group_ids should map every \"<page>.<group>\" key to its id."
  }
}
