terraform {
  required_version = ">= 1.9.0"

  required_providers {
    oneuptime = {
      source  = "oneuptime/oneuptime"
      version = ">= 13.0.6, < 14.0.0"
    }
  }
}

resource "oneuptime_status_page" "this" {
  for_each = local.status_page_definitions

  name        = coalesce(var.status_page_configs[each.key].name, each.key)
  description = var.status_page_configs[each.key].description

  // A page with no label_names of its own carries the project label, which is
  // what the status page owner and label rules below match on.
  labels = toset([
    for label_name in coalesce(var.status_page_configs[each.key].label_names, [var.application]) :
    var.label_ids[label_name]
  ])

  // Copy and SEO - passed straight through, omitted when not set.
  page_title                = var.status_page_configs[each.key].page_title
  page_description          = var.status_page_configs[each.key].page_description
  overview_page_description = var.status_page_configs[each.key].overview_page_description
  copyright_text            = var.status_page_configs[each.key].copyright_text
  default_language          = var.status_page_configs[each.key].default_language
  enabled_languages         = var.status_page_configs[each.key].enabled_languages
  custom_fields             = var.status_page_configs[each.key].custom_fields

  // Access
  is_public_status_page               = each.value.is_public_status_page
  enable_search_engine_indexing       = each.value.enable_search_engine_indexing
  hide_powered_by_one_uptime_branding = each.value.hide_powered_by_one_uptime_branding
  enable_mcp_server                   = each.value.enable_mcp_server
  enable_master_password              = each.value.enable_master_password
  master_password                     = var.status_page_configs[each.key].master_password
  require_sso_for_login               = each.value.require_sso_for_login
  ip_whitelist                        = var.status_page_configs[each.key].ip_whitelist

  // What the page shows
  show_incidents_on_status_page                    = each.value.show_incidents_on_status_page
  show_incident_labels_on_status_page              = each.value.show_incident_labels_on_status_page
  show_incident_history_in_days                    = each.value.show_incident_history_in_days
  show_announcements_on_status_page                = each.value.show_announcements_on_status_page
  show_announcement_history_in_days                = each.value.show_announcement_history_in_days
  show_scheduled_maintenance_events_on_status_page = each.value.show_scheduled_maintenance_events_on_status_page
  show_scheduled_event_labels_on_status_page       = each.value.show_scheduled_event_labels_on_status_page
  show_scheduled_event_history_in_days             = each.value.show_scheduled_event_history_in_days
  show_episodes_on_status_page                     = each.value.show_episodes_on_status_page
  show_episode_labels_on_status_page               = each.value.show_episode_labels_on_status_page
  show_episode_history_in_days                     = each.value.show_episode_history_in_days
  show_uptime_history_in_days                      = each.value.show_uptime_history_in_days
  show_overall_uptime_percent_on_status_page       = each.value.show_overall_uptime_percent_on_status_page
  overall_uptime_percent_precision                 = each.value.overall_uptime_percent_precision

  // Subscribers
  show_subscriber_page_on_status_page                     = each.value.show_subscriber_page_on_status_page
  enable_email_subscribers                                = each.value.enable_email_subscribers
  enable_sms_subscribers                                  = each.value.enable_sms_subscribers
  enable_slack_subscribers                                = each.value.enable_slack_subscribers
  enable_microsoft_teams_subscribers                      = each.value.enable_microsoft_teams_subscribers
  enable_webhook_subscribers                              = each.value.enable_webhook_subscribers
  allow_subscribers_to_choose_resources                   = each.value.allow_subscribers_to_choose_resources
  allow_subscribers_to_choose_event_types                 = each.value.allow_subscribers_to_choose_event_types
  subscriber_timezones                                    = var.status_page_configs[each.key].subscriber_timezones
  subscriber_email_notification_footer_text               = var.status_page_configs[each.key].subscriber_email_notification_footer_text
  enable_custom_subscriber_email_notification_footer_text = var.status_page_configs[each.key].enable_custom_subscriber_email_notification_footer_text

  // Embedded badge and scheduled reports
  enable_embedded_overall_status = var.status_page_configs[each.key].enable_embedded_overall_status
  embedded_overall_status_token  = var.status_page_configs[each.key].embedded_overall_status_token
  is_report_enabled              = each.value.is_report_enabled
  report_data_in_days            = each.value.report_data_in_days
  report_recurring_interval      = var.status_page_configs[each.key].report_recurring_interval
  report_period_type             = var.status_page_configs[each.key].report_period_type
  report_start_date_time         = var.status_page_configs[each.key].report_start_date_time
  report_timezone                = var.status_page_configs[each.key].report_timezone

  // Branding
  logo_file_id         = var.status_page_configs[each.key].logo_file_id
  logo_alt_text        = var.status_page_configs[each.key].logo_alt_text
  favicon_file_id      = var.status_page_configs[each.key].favicon_file_id
  cover_image_file_id  = var.status_page_configs[each.key].cover_image_file_id
  cover_image_alt_text = var.status_page_configs[each.key].cover_image_alt_text
  default_bar_color    = each.value.default_bar_color
  custom_css           = var.status_page_configs[each.key].custom_css
  custom_java_script   = var.status_page_configs[each.key].custom_java_script
  header_html          = var.status_page_configs[each.key].header_html
  footer_html          = var.status_page_configs[each.key].footer_html

  // Delivery
  smtp_config_id     = var.status_page_configs[each.key].smtp_config_id
  call_sms_config_id = var.status_page_configs[each.key].call_sms_config_id

}

resource "oneuptime_status_page_group" "this" {
  for_each                 = local.status_page_groups
  status_page_id           = oneuptime_status_page.this[each.value.status_page_key].id
  name                     = each.value.name
  description              = each.value.description
  order                    = each.value.order
  is_expanded_by_default   = each.value.is_expanded_by_default
  show_current_status      = each.value.show_current_status
  show_uptime_percent      = each.value.show_uptime_percent
  uptime_percent_precision = each.value.uptime_percent_precision
  view_mode                = each.value.view_mode
  row_axis_label           = each.value.row_axis_label
  row_axis_values          = each.value.row_axis_values
  column_axis_label        = each.value.column_axis_label
  column_axis_values       = each.value.column_axis_values
}

resource "oneuptime_status_page_resource" "this" {
  for_each             = local.status_page_resources
  status_page_id       = oneuptime_status_page.this[each.value.status_page_key].id
  status_page_group_id = each.value.group_key == null ? null : oneuptime_status_page_group.this["${each.value.status_page_key}.${each.value.group_key}"].id

  // monitor_key and monitor_group_key resolve against what this module already
  // creates; the *_id forms are the escape hatch for anything outside it.
  monitor_id       = each.value.monitor_key == null ? each.value.monitor_id : var.monitor_ids[each.value.monitor_key]
  monitor_group_id = each.value.monitor_group_key == null ? each.value.monitor_group_id : var.monitor_group_ids[each.value.monitor_group_key]

  display_name              = each.value.display_name
  display_description       = each.value.display_description
  display_tooltip           = each.value.display_tooltip
  order                     = each.value.order
  show_current_status       = each.value.show_current_status
  show_status_history_chart = each.value.show_status_history_chart
  show_uptime_percent       = each.value.show_uptime_percent
  uptime_percent_precision  = each.value.uptime_percent_precision
  row_axis_value            = each.value.row_axis_value
  column_axis_value         = each.value.column_axis_value
}

resource "oneuptime_status_page_monitor_rule" "this" {
  for_each             = local.status_page_monitor_rules
  status_page_id       = oneuptime_status_page.this[each.value.status_page_key].id
  status_page_group_id = each.value.group_key == null ? null : oneuptime_status_page_group.this["${each.value.status_page_key}.${each.value.group_key}"].id

  name        = each.value.name
  description = each.value.description
  is_enabled  = each.value.is_enabled

  monitor_labels = each.value.label_names == null ? null : toset([
    for label_name in each.value.label_names : var.label_ids[label_name]
  ])

  monitor_name_pattern        = each.value.monitor_name_pattern
  monitor_description_pattern = each.value.monitor_description_pattern
  show_current_status         = each.value.show_current_status
  show_status_history_chart   = each.value.show_status_history_chart
  show_uptime_percent         = each.value.show_uptime_percent
  uptime_percent_precision    = each.value.uptime_percent_precision

}

resource "oneuptime_status_page_header_link" "this" {
  for_each       = local.status_page_header_links
  status_page_id = oneuptime_status_page.this[each.value.status_page_key].id
  title          = each.value.title
  link           = each.value.link
  order          = each.value.order
}

resource "oneuptime_status_page_footer_link" "this" {
  for_each       = local.status_page_footer_links
  status_page_id = oneuptime_status_page.this[each.value.status_page_key].id
  title          = each.value.title
  link           = each.value.link
  order          = each.value.order
}

resource "oneuptime_status_page_history_chart_bar_color" "this" {
  for_each                                = local.status_page_bar_colors
  status_page_id                          = oneuptime_status_page.this[each.value.status_page_key].id
  bar_color                               = each.value.bar_color
  uptime_percent_greater_than_or_equal_to = each.value.uptime_percent_greater_than_or_equal_to
  order                                   = each.value.order
}

resource "oneuptime_status_page_domain" "this" {
  for_each       = local.status_page_domains
  status_page_id = oneuptime_status_page.this[each.value.status_page_key].id
  domain_id      = data.oneuptime_domain.by_name[each.value.domain_name].id
  subdomain      = each.value.subdomain
  depends_on     = [data.oneuptime_domain.by_name]
}

resource "oneuptime_status_page_private_user" "this" {
  for_each       = local.status_page_private_users
  status_page_id = oneuptime_status_page.this[each.value.status_page_key].id
  email          = each.value.email
  password       = each.value.password
  is_sso_user    = each.value.is_sso_user
}

resource "oneuptime_status_page_subscriber" "this" {
  for_each       = local.status_page_subscribers
  status_page_id = oneuptime_status_page.this[each.value.status_page_key].id

  subscriber_email                     = each.value.subscriber_email
  subscriber_phone                     = each.value.subscriber_phone
  subscriber_webhook                   = each.value.subscriber_webhook
  slack_workspace_name                 = each.value.slack_workspace_name
  slack_incoming_webhook_url           = each.value.slack_incoming_webhook_url
  microsoft_teams_workspace_name       = each.value.microsoft_teams_workspace_name
  microsoft_teams_incoming_webhook_url = each.value.microsoft_teams_incoming_webhook_url

  status_page_event_types          = each.value.status_page_event_types
  is_subscribed_to_all_resources   = each.value.is_subscribed_to_all_resources
  is_subscribed_to_all_event_types = each.value.is_subscribed_to_all_event_types
  is_subscription_confirmed        = each.value.is_subscription_confirmed
  send_you_have_subscribed_message = each.value.send_you_have_subscribed_message
  internal_note                    = each.value.internal_note
}

resource "oneuptime_status_page_announcement" "this" {
  for_each    = local.status_page_announcements
  title       = each.value.title
  description = each.value.description

  status_pages = toset([
    for page_key in each.value.status_page_keys : oneuptime_status_page.this[page_key].id
  ])

  // An announcement that names no monitors is about the whole page.
  monitors = length(each.value.monitor_keys) == 0 ? null : toset([
    for monitor_key in each.value.monitor_keys : var.monitor_ids[monitor_key]
  ])

  show_announcement_at                       = each.value.show_announcement_at
  end_announcement_at                        = each.value.end_announcement_at
  should_status_page_subscribers_be_notified = each.value.should_status_page_subscribers_be_notified
}

// Ownership. Teams come from rbac_team_mapping, so a page is owned the same way
// monitors, alerts and incidents are.
resource "oneuptime_status_page_team_owner" "this" {
  for_each       = local.status_page_owner_teams
  status_page_id = oneuptime_status_page.this[each.value.status_page_key].id
  team_id        = var.team_ids[each.value.group]
}

// User ownership takes raw user ids: looking users up by name needs an API key
// wider than project scope, the same reason team membership is commented out in
// teams.tf.
resource "oneuptime_status_page_user_owner" "this" {
  for_each       = local.status_page_owner_users
  status_page_id = oneuptime_status_page.this[each.value.status_page_key].id
  user_id        = each.value.user_id
}

// Label-driven ownership, mirroring the alert/incident/monitor owner rules: any
// status page carrying a component's label is owned by the groups that own that
// component. Only created once there is at least one status page to match.
resource "oneuptime_status_page_owner_rule" "this" {
  for_each = length(var.status_page_configs) == 0 ? {} : var.component_definitions

  name               = each.key
  is_enabled         = true
  description        = "status page owner rule for component ${each.key}"
  status_page_labels = toset([var.label_ids[each.key]])
  notify_owners      = true

  owner_teams = toset([
    for group in each.value.groups : var.team_ids[group]
  ])
}

resource "oneuptime_status_page_label_rule" "this" {
  for_each = length(var.status_page_configs) == 0 ? {} : var.component_definitions

  name               = each.key
  is_enabled         = true
  description        = "status page label rule for component ${each.key}"
  status_page_labels = toset([var.label_ids[each.key]])

  // The component label matches; the rule adds the labels of the owning groups.
  labels_to_add = toset([
    for group in each.value.groups : var.label_ids[group]
  ])
}
