# `modules/status-pages`

Creates `oneuptime_status_page` and everything that hangs off it: groups,
resources, monitor rules, header and footer links, uptime-bar colours, custom
domain, private users, subscribers, announcements and owners — plus the
label-driven `oneuptime_status_page_owner_rule` and
`oneuptime_status_page_label_rule` keyed by component.

Inputs are set on the **parent module** (`modules/oneuptime`), not here — this
submodule receives them already normalized, along with resolved label, team,
monitor and monitor-group ids. See [../../README.md](../../README.md) for how to
call the module; this file is the reference for what a page can contain.

| Output | Contents |
| --- | --- |
| `status_page_ids` | status page key -> status page id. |
| `status_page_group_ids` | `"<page key>.<group key>"` -> group id. |

---

## 1. `status_page_defaults`

Status pages default the same way monitors do, so a page in
`status_page_configs` only declares what is genuinely its own — its name, what
it publishes, its domain. Precedence, lowest to highest:

1. the `default` in `../../variables-status-pages.tf` — the industry-standard baseline
2. `status_page_defaults` passed to the module — the stack-wide baseline
3. the page's own entry in `status_page_configs` — the per-page override

| Key | Default | Why |
| --- | --- | --- |
| `is_public_status_page` | `true` | A page is customer-facing unless it says otherwise. |
| `enable_search_engine_indexing` | `true` | Findable in search. Turn off for a link-only page. |
| `hide_powered_by_one_uptime_branding` | `false` | |
| `enable_mcp_server` | `false` | Off until you decide agents may read the page. |
| `enable_master_password` / `require_sso_for_login` | `false` | Only meaningful on a private page. |
| `show_incidents_on_status_page` | `true` | |
| `show_incident_history_in_days` | `30` | |
| `show_announcements_on_status_page` | `true` | |
| `show_announcement_history_in_days` | `14` | |
| `show_scheduled_maintenance_events_on_status_page` | `true` | |
| `show_scheduled_event_history_in_days` | `14` | |
| `show_episodes_on_status_page` | `true` | |
| `show_episode_history_in_days` | `30` | |
| `show_*_labels_on_status_page` | `false` | Internal labels mean nothing to a reader outside the team. |
| `show_uptime_history_in_days` | `90` | The server maximum, and what an SLA conversation asks for. |
| `show_overall_uptime_percent_on_status_page` | `true` | |
| `overall_uptime_percent_precision` | `"99% (No Decimal)"` | Set `"99% (Two Decimal)"` where an SLA is quoted to two places. |
| `show_subscriber_page_on_status_page` | `false` | |
| `enable_email_subscribers` | `false` | The one channel that needs no extra setup, once a page opts in. |
| `enable_sms_/slack_/microsoft_teams_/webhook_subscribers` | `false` | Each needs a configured integration first. |
| `allow_subscribers_to_choose_resources` | `true` | |
| `allow_subscribers_to_choose_event_types` | `true` | |
| `is_report_enabled` | `false` | |
| `report_data_in_days` | `7` | Only read once a page enables reports. |
| `default_bar_color` | `"#0F9D58"` | Bar colour when no band below matches. |
| `group.is_expanded_by_default` | `true` | every `groups[*]` |
| `group.show_current_status` | `true` | every `groups[*]` |
| `group.show_uptime_percent` | `true` | every `groups[*]` |
| `group.uptime_percent_precision` | `"99% (No Decimal)"` | every `groups[*]` |
| `group.view_mode` | `"List"` | every `groups[*]` |
| `resource.show_current_status` | `true` | every `resources[*]` and `monitor_rules[*]` |
| `resource.show_status_history_chart` | `true` | every `resources[*]` and `monitor_rules[*]` |
| `resource.show_uptime_percent` | `true` | every `resources[*]` and `monitor_rules[*]` |
| `resource.uptime_percent_precision` | `"99% (No Decimal)"` | every `resources[*]` and `monitor_rules[*]` |
| `subscriber.is_subscribed_to_all_resources` | `true` | every `subscribers[*]` |
| `subscriber.is_subscribed_to_all_event_types` | `true` | every `subscribers[*]` |
| `subscriber.send_you_have_subscribed_message` | `true` | every `subscribers[*]` |
| `announcement.should_status_page_subscribers_be_notified` | `true` | every `status_page_announcements[*]` |
| `history_chart_bar_colors` | `[]` | the uptime bars; empty leaves OneUptime's own colours (see below) |

Overriding one key keeps the shipped value for the rest:

```hcl
module "oneuptime" {
  # ...
  status_page_defaults = {
    show_uptime_history_in_days = 60
    enable_slack_subscribers    = true
    resource = {
      uptime_percent_precision = "99% (One Decimal)"
    }
  }
}
```

A page then only carries what differs — this is a complete, valid page:

```hcl
status_page_configs = {
  "core" = {}
}
```

It is named `core` after its key, is public and indexable, shows 90 days of
uptime history with whole-number percentages, and keeps OneUptime's own uptime
bar colours.

`history_chart_bar_colors` ships empty because the provider cannot manage the
bands yet: the API returns `uptimePercentGreaterThanOrEqualTo` as a string while
the provider declares a number, so it reads back as `null` and the apply fails
with "Provider produced inconsistent result after apply" (last checked on
12.0.26). The rules are created server-side; only the read-back is broken. A
threshold of `0` is rejected by the API, so start the bottom band at `0.01`.

Attributes that are **not** defaulted — titles, copy, branding, custom CSS,
SMTP/SMS config ids, report interval and timezone — are passed straight through
and are simply not sent to OneUptime when omitted.

---

## 2. Configuring a page

`status_page_configs` is keyed by a short identifier. Every attribute is
optional: the key becomes the name, and everything else comes from
`status_page_defaults` (§1) until the page overrides it.

```hcl
status_page_configs = {
  "core" = {
    name        = "Core Status"
    description = "Public status page for core platform services"
    label_names = ["platform", "core"]

    groups = {
      "platform" = {}
    }

    monitor_rules = {
      "platform" = {
        group_key   = "platform"
        label_names = ["platform"]
      }
    }

    footer_links      = { "Documentation" = { link = "https://docs.example.com" } }
    owner_group_names = ["devops"]
  }
}
```

### 2.1 Publishing monitors

Two ways, and they can be mixed on one page:

| | When to use |
| --- | --- |
| `monitor_rules` | Publish everything carrying a label. A new monitor with that label appears on the page without editing this file. Preferred. |
| `resources` | Publish named monitors one at a time, in a chosen order, with per-monitor copy. |

A `resources` entry must set **exactly one** monitor source:

| Key | Resolves to |
| --- | --- |
| `monitor_key` | `oneuptime_monitor.this[<key>]` — a key of `monitor_configs`. |
| `monitor_group_key` | `oneuptime_monitor_group.this[<component>]` — a component of `rbac_component_mapping`, so a whole component is published as one row. |
| `monitor_id` | A monitor that exists outside this module. |
| `monitor_group_id` | A monitor group that exists outside this module. |

`display_name` falls back to the monitor's own `display_name`, then to the map
key, so a row can be one line:

```hcl
resources = {
  "gitlab" = { monitor_key = "gitlab", group_key = "platform" }
}
```

`order` falls back to the entry's position among the sorted keys, for
`groups`, `resources`, `header_links` and `footer_links` alike. Set it
explicitly when alphabetical is not the order you want.

A `monitor_rules` entry must set at least one of `label_names`,
`monitor_name_pattern` or `monitor_description_pattern` — a rule with none of
them matches nothing. The patterns are case-insensitive regexes; `.*` matches
every monitor.

### 2.2 Groups

`groups` is keyed the same way; `name` defaults to the key. `view_mode = "Grid"`
renders the group as a matrix, in which case set `row_axis_values` /
`column_axis_values` on the group and `row_axis_value` / `column_axis_value` on
each resource in it.

### 2.3 Ownership and access

| Key | Notes |
| --- | --- |
| `owner_group_names` | Groups from `rbac_team_mapping`. Resolves to `oneuptime_team`. |
| `owner_user_ids` | Raw user ids — looking users up by name needs an API key wider than project scope, the same reason team membership is commented out in `../../teams.tf`. |
| `label_names` | Defaults to the project label. Give a page its **component** label and the label-driven `oneuptime_status_page_owner_rule` hands it to the groups that own that component, exactly like the alert, incident and monitor owner rules. |
| `private_users` | Only meaningful with `is_public_status_page = false`. |
| `domain` | `{ domain_name, subdomain }`. The domain must already exist and be verified in the OneUptime project; the module looks it up by name and attaches it. |

### 2.4 Subscribers

`subscribers` seeds the notification list from code — a mailing list, a Slack
channel, a webhook. Set exactly one channel per entry. Terraform-managed
subscribers are confirmed on creation, since the operator vouched for them
rather than the subscriber opting in.

```hcl
subscribers = {
  "oncall"  = { subscriber_email = "oncall@example.com" }
  "slack"   = { slack_workspace_name = "example", slack_incoming_webhook_url = var.status_slack_webhook_url }
}
```

Note that the matching `enable_*_subscribers` flag must be on for that channel —
none of them is on by default.

### 2.5 Announcements

Announcements are project-level in OneUptime (they carry the set of pages they
appear on), so they are a sibling input rather than nested in a page:

```hcl
status_page_announcements = {
  "gitlab-upgrade" = {
    title                = "GitLab upgrade"
    description          = "GitLab will be unavailable for up to 30 minutes."
    show_announcement_at = "2026-09-01T09:00:00Z"
    end_announcement_at  = "2026-09-01T10:00:00Z"
    monitor_keys         = ["gitlab"]
  }
}
```

Empty `status_page_keys` means every page the module manages; empty
`monitor_keys` means the announcement is about the whole page.

### 2.6 What the module creates

`oneuptime_status_page` plus, driven by the config above:
`_group`, `_resource`, `_monitor_rule`, `_header_link`, `_footer_link`,
`_history_chart_bar_color`, `_domain`, `_private_user`, `_subscriber`,
`_announcement`, `_team_owner`, `_user_owner`, and — driven by
`rbac_component_mapping`, not by any page — `_owner_rule` and `_label_rule`.

Not wired up: `_sso`, `_oidc` and `_scim` (identity federation, needs secrets
and out-of-band verification), `_custom_field`, and `_announcement_template`.
Add them the same way if a stack needs them.

### 2.7 Gotchas

- `show_uptime_history_in_days` is capped at `90` server-side.
- Uptime precision is one of `"99% (No Decimal)"`, `"99% (One Decimal)"`, `"99% (Two Decimal)"`.
- `history_chart_bar_colors` on a page **replaces** `status_page_defaults.history_chart_bar_colors`
  wholesale rather than merging into it.
- `master_password` and private user `password` are not marked `sensitive`, so
  they appear in plan output and in state. Prefer SSO, or set them in the
  dashboard.
- An empty string on a defaulted attribute reads as unset and falls back to the
  default. Use the intended value, not `""`.
- The status page owner and label rules are only created once at least one page
  exists, so a stack with no status pages provisions nothing extra.
