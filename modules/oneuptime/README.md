# OneUptime Observability Module

The `oneuptime` module turns an inventory — which components exist, which groups own them and
what is monitored — into the OneUptime resources that watch it: labels, teams, monitors,
alert and incident rules, on-call policies, status pages and workflows. The calling stack owns
**what** is monitored; this module owns **how** that becomes resources.

## Architecture & Managed Resources

Labels and teams are created at the root, because every area needs their ids. Everything else
is grouped by the part of OneUptime it configures, one submodule per area, so a change to
on-call never touches monitors.

| Area | Resources | One per |
| --- | --- | --- |
| Root | `oneuptime_label.this` | label name in `labels_config`, plus the `application` label |
| Root | `oneuptime_team.this` | group in `rbac_team_mapping` |
| [Monitors](modules/monitors/README.md) | `oneuptime_monitor` | slug in `monitors_component_mapping` |
| [Monitors](modules/monitors/README.md) | `oneuptime_monitor_group`, `_owner_rule`, `_label_rule` | component |
| [Alerts](modules/alerts/README.md) | `oneuptime_alert_owner_rule`, `_label_rule`, `_grouping_rule` | component |
| [Incidents](modules/incidents/README.md) | `oneuptime_incident_owner_rule`, `_label_rule`, `_grouping_rule` | component |
| [On-call](modules/oncall/README.md) | `oneuptime_on_call_policy`, `_owner_rule`, `oneuptime_escalation_rule`, `oneuptime_on_call_policy_schedule`, `oneuptime_on_call_schedule_layer`, `oneuptime_schedules_on_call_duty_escalation_rule` | component |
| [Status pages](modules/status-pages/README.md) | `oneuptime_status_page` and its groups, resources, monitor rules, links, domain, private users, subscribers, announcements and owners | entry in `status_page_configs` |
| [Status pages](modules/status-pages/README.md) | `oneuptime_status_page_owner_rule`, `_label_rule` | component, once a page exists |
| [Workflows](modules/workflows/README.md) | `oneuptime_workflow`, `oneuptime_workflow_variable` | entry in `workflow_configs` |

Read-only lookups: the `Operational` / `Degraded` / `Offline` monitor statuses and the incident
and alert severities (in `modules/monitors`), and custom domains by name (in
`modules/status-pages`). They already exist in every OneUptime project.

[`modules/workflows-templates/teams-notification`](modules/workflows-templates/teams-notification/README.md)
creates nothing: it builds `workflow_configs` for the five standard Microsoft Teams
notifications.

`rbac_component_mapping` maps a component to the **list** of groups that own it.
`local.component_definitions` resolves that list once:

```text
component -> { groups = [...], label_names = [component, ...groups] }
```

Every area iterates that map, so a component owned by two groups gets **one** rule naming both
teams, never one rule per group. Monitors carry the component label, the label of every group
that owns the component and the `application` label; labels are never written on a monitor.

`modules/status-pages` takes `monitor_ids` and `monitor_group_ids` from `modules/monitors`, and
`modules/workflows` takes the project id and monitor status ids. Those are the only
dependencies between areas, and they are data, never `depends_on`.

### Security & Compliance Guardrails

- **Caller-owned provider**: the module declares no `provider "oneuptime"` block, no URL and no
  API key. Pass the key through `ONEUPTIME_API_KEY`, never in a `.tf` file.
- **Project-scoped API key**: everything here works with a project-scoped key. Team membership
  needs a wider key, so `oneuptime_team_member` is deliberately not managed (see `teams.tf`);
  add members in the OneUptime dashboard.
- **Secrets stay out of state**: monitors reference credentials as
  `"{{monitorSecrets.<name>}}"`. Workflow variable content (`workflow_variable_contents`) is
  `sensitive`, applied on create and then ignored, because OneUptime never returns it.
- **Public status pages by default**: `status_page_defaults` ships pages public and indexable,
  which is the common shape for a customer-facing page. Set `is_public_status_page = false`
  and `enable_search_engine_indexing = false` for an internal page. The MCP server is off.
- **Validated inputs**: an unknown `monitor_type`, a probe monitor with no `target`, a `Port`
  monitor with no `port`, a mapped slug with no `monitor_configs` entry, and a status page or
  workflow that references something undeclared each fail at plan time, naming the offenders.

Tags, customer-managed keys and TLS settings from the AWS baseline are `not_applicable`: the
OneUptime API has no such arguments. Labels take the place of governance tags.

---

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.9.0` |
| `oneuptime` (`oneuptime/oneuptime`) | `>= 13.0.6, < 14.0.0` |

Terraform `1.9.0` is the floor because validations compare one input against another
(`monitors_component_mapping` against `monitor_configs`, for example). The provider is bounded
to the major the module is validated against: 14.x drops the `name` argument of the
`oneuptime_domain` data source that custom status page domains are looked up by.

---

## Usage Examples

The calling stack configures the provider. `oneuptime_url` defaults to `oneuptime.com`; set it
for a self-hosted instance.

```hcl
provider "oneuptime" {
  oneuptime_url = "https://oneuptime.example.com"
  # api_key is read from ONEUPTIME_API_KEY
}
```

### Minimal Working Example

```hcl
module "oneuptime" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/oneuptime?ref=1.5.0"

  application = "core"

  labels_config = {
    "component" = { "platform" = "#614C3F" }
    "group"     = { "devops" = "#CED431" }
  }

  rbac_component_mapping = { "platform" = ["devops"] }
  rbac_team_mapping      = { "devops" = ["devops@example.com"] }

  monitors_component_mapping = { "platform" = ["api"] }

  monitor_configs = {
    "api" = {
      display_name = "Core API"
      monitor_type = "API"
      target       = "https://api.example.com/health"
    }
  }
}
```

That is a complete stack. The monitor probes every minute, opens a critical incident when the
endpoint stops answering `200`, raises a low alert when it averages over 5 seconds across 15
minutes, and returns to Operational on its own. Probe intervals, retry counts, grouping windows,
escalation timings and status page behaviour all come from the module's defaults.

### Complete Production Example

```hcl
module "teams_notifications" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/oneuptime/modules/workflows-templates/teams-notification?ref=1.5.0"

  project_name      = "Core"
  dashboard_url     = "https://oneuptime.example.com"
  teams_webhook_url = var.teams_webhook_url
}

module "oneuptime" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/oneuptime?ref=1.5.0"

  application = "core"

  labels_config = {
    "component" = {
      "platform"       = "#614C3F"
      "application"    = "#F52750"
      "infrastructure" = "#CED431"
    }
    "group" = {
      "devops"     = "#CED431"
      "developers" = "#F52750"
    }
  }

  rbac_component_mapping = {
    "platform"       = ["devops"]
    "application"    = ["developers", "devops"]
    "infrastructure" = ["devops"]
  }

  rbac_team_mapping = {
    "devops"     = ["devops@example.com"]
    "developers" = ["developers@example.com"]
  }

  monitors_component_mapping = {
    "platform"       = ["git", "ci"]
    "application"    = ["api"]
    "infrastructure" = ["postgres", "tls"]
  }

  // Keep the bulky per-monitor configuration in the stack's locals.tf.
  monitor_configs = local.oneuptime_monitor_configs

  monitor_defaults = {
    monitoring_interval = "*/2 * * * *"
    monitor_step = {
      request_headers = { "User-Agent" = "OneUptime-Probe/core" }
    }
    thresholds = { response_time_ms = 1500 }
  }

  on_call_schedule_layer_config = {
    rotation = { interval_type = "Week", interval_count = 1 }
  }

  status_page_defaults = {
    show_uptime_history_in_days = 60
  }

  status_page_configs = {
    "core" = {
      name        = "Core Status"
      label_names = ["platform", "core"]
      groups      = { "platform" = {}, "application" = {} }
      monitor_rules = {
        "platform"    = { group_key = "platform", label_names = ["platform"] }
        "application" = { group_key = "application", label_names = ["application"] }
      }
      domain            = { domain_name = "example.com", subdomain = "status" }
      owner_group_names = ["devops"]
    }
  }

  workflow_configs           = module.teams_notifications.workflow_configs
  workflow_variable_contents = module.teams_notifications.workflow_variable_contents
}
```

---

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | :---: |
| `application` | Name of the project or application. Also becomes a `project` label (`#1100ff`) attached to every monitor and to status pages without labels of their own. | `string` | **Required** | Yes |
| `labels_config` | `{ label_type = { label_name = hex_colour } }`. One `oneuptime_label` per label name; names are unique across types. | `map(map(string))` | `{}` | No |
| `rbac_component_mapping` | Component -> the groups that own it. Drives monitor groups, owner rules and label rules in every area. Components and groups must be label names. | `map(list(string))` | **Required** | Yes |
| `rbac_team_mapping` | Group -> member emails. Creates one `oneuptime_team` per group; members are not attached (see Security). | `map(list(string))` | **Required** | Yes |
| `monitors_component_mapping` | Component -> monitor slugs. Only mapped slugs are created; each must have a `monitor_configs` entry. | `map(list(string))` | **Required** | Yes |
| `monitor_configs` | One entry per monitor, keyed by slug. See [monitors §4](modules/monitors/README.md#4-monitor_configs-schema). | `any` | `{}` | No |
| `monitor_defaults` | Baseline for every monitor, including the thresholds the generated criteria compare against. See [monitors §2](modules/monitors/README.md#2-monitor_defaults). | `object({...})` | `{}` | No |
| `alert_grouping_rule_config` | Alert grouping per component: by alert labels and severity, 15-minute reopen window. | `object({...})` | see `variables-alerts.tf` | No |
| `incident_grouping_rule_config` | The same shape for incidents. | `object({...})` | see `variables-incidents.tf` | No |
| `on_call_policy_config` | Repeat the policy 3 times if nobody acknowledges. | `object({...})` | see `variables-oncall.tf` | No |
| `on_call_escalation_rules` | Escalate after 30 minutes, order 1. | `object({...})` | see `variables-oncall.tf` | No |
| `on_call_schedule_layer_config` | The one schedule layer per component: weekly rotation covering the whole clock. See [on-call](modules/oncall/README.md#the-schedule-layer). | `object({...})` | `{}` | No |
| `status_page_defaults` | Baseline for every status page. See [status pages §1](modules/status-pages/README.md#1-status_page_defaults). | `object({...})` | `{}` | No |
| `status_page_configs` | One entry per status page, everything optional. See [status pages §2](modules/status-pages/README.md#2-configuring-a-page). | `map(object({...}))` | `{}` | No |
| `status_page_announcements` | Announcements published across status pages. | `map(object({...}))` | `{}` | No |
| `workflow_configs` | Workflows as nodes, and their variables. See [workflows](modules/workflows/README.md). | `map(object({...}))` | `{}` | No |
| `workflow_variable_contents` | `"<workflow>.<variable>"` -> initial variable content. Write-once. | `map(string)` | `{}` | No |
| `custom_fields` | Project-level custom fields as a JSON string. Accepted but not yet applied to any resource. | `string` | `null` | No |

`workflow_variable_contents` is `sensitive`.

---

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | :---: |
| `label_ids` | Label name -> label id. | No |
| `team_ids` | Group name -> team id. | No |
| `monitor_ids` | Monitor slug -> monitor id. | No |
| `monitor_group_ids` | Component -> monitor group id. | No |
| `on_call_policy_ids` | Component -> on-call policy id. | No |
| `status_page_ids` | Status page key -> status page id. | No |
| `workflow_ids` | Workflow key -> workflow id. | No |
| `workflow_graphs` | Workflow key -> the canvas JSON sent to OneUptime. | No |

---

## Module Layout

```text
modules/oneuptime/
├── main.tf                       provider requirements and the submodule wiring
├── locals.tf                     label config, component_definitions, resolved ids
├── labels.tf, teams.tf           created here because every area needs the ids
├── outputs.tf
├── variables.tf                  application, labels_config, rbac_*
├── variables-<area>.tf           the inputs, types, defaults and validation of one area
├── tests/unit.tftest.hcl         mock-provider tests, run by make verify
├── CONVENTIONS.md                how configuration flows from a stack to a resource
└── modules/
    ├── monitors/                 monitors, monitor groups, monitor owner and label rules
    ├── alerts/                   alert owner, label and grouping rules
    ├── incidents/                incident owner, label and grouping rules
    ├── oncall/                   policies, escalation rules, schedules, layers
    ├── status-pages/             status pages and everything hanging off them
    ├── workflows/                workflows and their variables
    └── workflows-templates/      ready-made workflow_configs (teams-notification)
```

**Where to make a change:** the input lives in the `variables-<area>.tf` named after the area,
and the resources live in `modules/<area>/`. The submodules other than `workflows-templates`
are internal: call this module, not them.

[CONVENTIONS.md](CONVENTIONS.md) is the standard every area follows — the five layers a value
passes through, the two defaulting mechanisms, the precedence ladders, naming, where validation
lives, and the HCL idioms. Read it before adding an area or an input.

## How Defaults Work

`monitor_defaults` and `status_page_defaults` share one precedence, lowest to highest:

1. the `default` in the module — the shipped baseline
2. the `*_defaults` object passed to the module — the stack-wide baseline
3. the monitor's or page's own entry — the per-item override. Monitors have a narrower fourth
   level: `criteria.<preset>` overrides a threshold for one criterion only.

Every key is `optional()`, so overriding one keeps the shipped value for the others.

## Adding a Monitor

1. Add the slug to `monitors_component_mapping`, under the component that owns it. A slug
   belongs to one component.
2. Add an entry with the same slug to `monitor_configs`.
3. Give it `display_name`, `monitor_type` and whatever that type needs to reach the target
   (`target`, `port`, a `step` block). The probe step and the Offline / Degraded / Operational
   criteria are generated from the type; see
   [monitors §7](modules/monitors/README.md#7-one-example-per-monitor-family).
4. `terraform fmt -recursive && terraform validate && terraform plan`.

```hcl
locals {
  oneuptime_monitor_configs = {
    "git" = {
      display_name = "Git server"
      monitor_type = "API"
      target       = "https://git.example.com/-/health"

      thresholds = { response_time_ms = 3000 } # every criterion of this monitor

      criteria = {
        offline = {                            # just this one
          body_contains     = "OK"
          remediation_notes = "Check the web service, then the database."
        }
      }
    }
  }
}
```

A mapped slug with no `monitor_configs` entry fails validation, naming the slugs:

```text
Every monitor in monitors_component_mapping needs an entry with the same key
in monitor_configs. Missing: ci, postgres.
```

## Adding a Status Page

```hcl
status_page_configs = {
  "core" = {}
}
```

That is a valid page: named after its key, public, indexable, 90 days of uptime history and
whole-number uptime percentages. Grow it from there with the
[status pages reference](modules/status-pages/README.md).

## Known Caveats

- Monitors exist only for slugs in `monitors_component_mapping`; an unmapped
  `monitor_configs` entry is not created.
- `status_page_configs` is not `sensitive`, so a `master_password` or a private user
  `password` set there appears in plan output and in state. Prefer SSO, or set them in the
  dashboard.
- The alert and incident grouping rules do not page on-call yet (`on_call_duty_policies = []`);
  see [alerts](modules/alerts/README.md).
- Uptime bar colour bands are empty by default: the provider reads the band threshold back as
  `null` and fails the apply (last checked on 12.0.26). See
  [status pages §1](modules/status-pages/README.md#1-status_page_defaults).
