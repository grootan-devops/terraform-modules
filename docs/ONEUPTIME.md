# OneUptime Monitoring Architecture & Standards Guide

This document defines the architecture, secret handling, monitoring baselines, naming standards,
module catalog and consumption patterns for the OneUptime module in this repository.

The module lives under [`modules/oneuptime/`](../modules/oneuptime/) and configures monitoring
through the `oneuptime/oneuptime` provider: it provisions no cloud infrastructure. The calling
stack decides **what** is monitored and who owns it; the module decides **how** that becomes
OneUptime resources. The full input reference is in the
[module README](../modules/oneuptime/README.md), and the internal standard every area follows
is in [CONVENTIONS.md](../modules/oneuptime/CONVENTIONS.md).

---

## 1. OneUptime Module Catalog

The root module creates labels and teams, because every area needs their ids, and wires one
internal submodule per area. Call the root module, not the submodules; the
`workflows-templates` directory is the one part meant to be called directly.

| Area | Module Directory | Primary OneUptime Resources Managed | One Per |
| --- | --- | --- | --- |
| **Root** | [`modules/oneuptime`](../modules/oneuptime) | `oneuptime_label`, `oneuptime_team` | label name, `rbac_team_mapping` group |
| **Monitors** | [`modules/oneuptime/monitors`](../modules/oneuptime/monitors) | `oneuptime_monitor`, `oneuptime_monitor_group`, `oneuptime_monitor_owner_rule`, `oneuptime_monitor_label_rule` | mapped monitor slug; component |
| **Alerts** | [`modules/oneuptime/alerts`](../modules/oneuptime/alerts) | `oneuptime_alert_owner_rule`, `oneuptime_alert_label_rule`, `oneuptime_alert_grouping_rule` | component |
| **Incidents** | [`modules/oneuptime/incidents`](../modules/oneuptime/incidents) | `oneuptime_incident_owner_rule`, `oneuptime_incident_label_rule`, `oneuptime_incident_grouping_rule` | component |
| **On-call** | [`modules/oneuptime/oncall`](../modules/oneuptime/oncall) | `oneuptime_on_call_policy`, `oneuptime_escalation_rule`, `oneuptime_on_call_policy_schedule`, `oneuptime_on_call_schedule_layer` | component |
| **Status pages** | [`modules/oneuptime/status-pages`](../modules/oneuptime/status-pages) | `oneuptime_status_page` with groups, resources, monitor rules, links, domain, subscribers, announcements, owners | `status_page_configs` entry |
| **Workflows** | [`modules/oneuptime/workflows`](../modules/oneuptime/workflows) | `oneuptime_workflow`, `oneuptime_workflow_variable` | `workflow_configs` entry |
| **Templates** | [`modules/oneuptime/workflows-templates/teams-notification`](../modules/oneuptime/workflows-templates/teams-notification) | none — emits `workflow_configs` for five Microsoft Teams notifications | — |

Read-only lookups resolve the `Operational` / `Degraded` / `Offline` monitor statuses, the
incident and alert severities, and custom status page domains by name. They already exist in
every OneUptime project, so a stack declares no data sources to write a monitor.

---

## 2. Credential & Secret Handling

Nothing the module needs to authenticate or to reach a target is written into Terraform code:

1. **Caller-Owned API Key**: the module declares no `provider "oneuptime"` block. The stack's
   provider reads a project-scoped key from `ONEUPTIME_API_KEY`; the provider marks `api_key`
   sensitive. The key's project is the project every resource lands in.
2. **Project Scope Only**: everything works with a project-scoped key. Team membership needs a
   wider key, so members are added in the OneUptime dashboard, not by Terraform.
3. **Monitor Secrets**: probe credentials — mTLS keys, Synthetic Monitor logins, SQL passwords —
   are stored as OneUptime monitor secrets and referenced as `"{{monitorSecrets.<name>}}"`, so
   they never enter state.
4. **Write-Once Workflow Variables**: workflow variables are secret by default. Their content
   comes from the sensitive `workflow_variable_contents` map on create and is ignored afterwards,
   because OneUptime never returns it; rotate it in the dashboard. A variable with no content is
   created with a placeholder.
5. **Sensitive Webhooks**: the Teams template takes `teams_webhook_url` as a sensitive input and
   emits it only through the sensitive `workflow_variable_contents` output.

`status_page_configs` is not sensitive: a status page `master_password` or private user
`password` set there appears in plan output and in state. Prefer SSO for private pages, or set
the password in the dashboard.

---

## 3. Monitoring Baselines

Every value below is a module default. A stack overrides it once in `monitor_defaults` or
`status_page_defaults`, and an item overrides it again on its own entry.

1. **Probe Cadence**:
   - Monitors probe every minute (`* * * * *`), one probe is enough to change status, requests
     time out after 5000 ms and retry 3 times.
   - Redirects are followed and self-signed certificates are rejected.
2. **Generated Criteria**, evaluated first match wins for 15 monitor types:
   - **Offline** opens a **critical** incident: not online, the wrong status code, a timeout, an
     expired certificate, or a missed heartbeat.
   - **Degraded** raises a **low** alert: response time over 5000 ms averaged across 15 minutes,
     over 10% packet loss or 50 ms jitter, a certificate within 21 days of expiry, a domain within
     30 days, or a server over 90% CPU or memory, 85% disk or 50% swap.
   - **Operational** returns the monitor to green on its own.
   - Generated incidents and alerts auto-resolve, are not private, and incidents show on status
     pages.
3. **Noise Control**: alerts and incidents are grouped per component by labels and severity, with
   a 15-minute reopen window.
4. **On-Call**:
   - Each component's policy repeats 3 times if nobody acknowledges, and escalates after
     30 minutes.
   - The one schedule layer rotates weekly and covers the whole clock. Restricting it to business
     hours is opt-in, because it leaves the rest of the day uncovered.
5. **Status Pages**:
   - Pages are public and indexable, show 90 days of uptime history as whole-number percentages,
     and show incidents (30 days), announcements and scheduled maintenance (14 days each).
   - Internal labels are hidden, and the MCP server, the master password, SSO and every subscriber
     channel are off until a page turns them on.
6. **Fail-Fast Validation**: an unknown `monitor_type`, a probe monitor with no `target`, a `Port`
   monitor with no `port`, a mapped slug with no configuration, and a status page, announcement
   or workflow that references something undeclared each fail at plan time, naming the
   offenders.

---

## 4. Resource Naming & Labelling Standards

The module has no `environment` input and no tags. Labels take the place of tags, and each
environment is its own OneUptime project (§6).

### Labels

| Label | Source | Attached To |
| --- | --- | --- |
| `<application>` (`#1100ff`, type `project`) | `var.application` | every monitor, and every status page without `label_names` |
| `<component>` | `labels_config` | the component's monitors, monitor group, on-call policy and episodes; its alerts and incidents through the label rules |
| `<group>` | `labels_config` | wherever its components' label is, directly or through the label rules |

Every component and group in `rbac_component_mapping` must be a label name in `labels_config`.
Labels are never written on a monitor: they are derived from `monitors_component_mapping`, so the
owner and label rules always match.

### Resource Names

| Resource | Name |
| --- | --- |
| Monitor | `display_name`, else the slug |
| Monitor group, owner, label and grouping rules | `<component>` |
| Alert and incident episodes | `<component> - Alert Episode`, `<component> - Incident Episode` |
| On-call policy, owner rule, escalation rule | `<component>-oncall-policy`, `-oncall-policy-owner-rule`, `-oncall-policy-escalation-rule` |
| On-call schedule and layer | `<component>-oncall-schedule`, `<component>-oncall-schedule-layer` |
| Status page, status page group | `name`, else the map key |
| Status page resource | `display_name`, else the monitor's `display_name`, else the map key |
| Teams template workflows | `<project_name> — Teams — <event>` |

---

## 5. End-to-End Native Terraform Composition

The following complete configuration monitors a production stack, publishes a status page and
posts every alert and incident to Microsoft Teams:

```hcl
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    oneuptime = {
      source  = "oneuptime/oneuptime"
      version = ">= 13.0.6, < 14.0.0"
    }
  }
}

# api_key is read from ONEUPTIME_API_KEY: the prod project's key.
provider "oneuptime" {
  oneuptime_url = "https://oneuptime.example.com"
}

# 1. Standard Teams notifications (Templates)
module "teams_notifications" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/oneuptime/workflows-templates/teams-notification?ref=<version>"

  project_name      = "Core"
  dashboard_url     = "https://oneuptime.example.com"
  teams_webhook_url = var.teams_webhook_url
}

# 2. Monitors, rules, on-call, status page and workflows (Root)
module "oneuptime" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/oneuptime?ref=<version>"

  application = "core"

  labels_config = {
    "component" = {
      "platform"       = "#614C3F"
      "application"    = "#F52750"
      "infrastructure" = "#CED431"
    }
    "group" = {
      "devops"     = "#CED431"
      "developers" = "#1F6FEB"
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
    "application"    = ["api", "web"]
    "platform"       = ["nightly-backup"]
    "infrastructure" = ["postgres", "web-tls"]
  }

  monitor_configs = {
    "api" = {
      display_name = "Core API"
      monitor_type = "API"
      target       = "https://api.example.com/health"
      criteria     = { offline = { body_contains = "ok" } }
    }
    "web" = {
      display_name = "Website"
      monitor_type = "Website"
      target       = "https://www.example.com"
      step         = { request_timeout_in_ms = 30000 }
    }
    "postgres" = {
      display_name = "PostgreSQL primary"
      monitor_type = "Port"
      target       = "postgres.internal.example.com"
      port         = 5432
    }
    "web-tls" = {
      display_name        = "Website TLS certificate"
      monitor_type        = "SSL Certificate"
      target              = "https://www.example.com"
      monitoring_interval = "0 0 * * *"
    }
    "nightly-backup" = {
      display_name = "Nightly backup job"
      monitor_type = "Incoming Request"
      thresholds   = { heartbeat_timeout_minutes = 1500 }
    }
  }

  status_page_configs = {
    "core" = {
      name        = "Core Status"
      label_names = ["application", "core"]
      groups      = { "services" = {} }
      monitor_rules = {
        "services" = { group_key = "services", label_names = ["application"] }
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

## 6. Terragrunt OneUptime Architecture

The same Terragrunt pattern as the AWS stacks applies: one canonical composition in
**`resources/`**, a **`root.hcl`** for state and the provider, and thin **`dev/`** and
**`prod/`** directories. What differs per environment is the **OneUptime project**: each
environment's API key points at its own project, so dev and prod never share a monitor, a rule
or a status page.

```text
OneUptime project "oneuptime-dev"   <- DEV_ONEUPTIME_API_KEY
OneUptime project "oneuptime-prod"  <- PROD_ONEUPTIME_API_KEY
```

```text
infra-live/
├── root.hcl                          # Remote state and the oneuptime provider generator
├── resources/                        # Single canonical Terraform composition layer
│   ├── monitors.tf                   # monitor_configs, targets built from var.base_domain
│   ├── oneuptime.tf                  # Calls modules/oneuptime and the Teams template
│   ├── variables.tf                  # Parameterized environment variables
│   └── outputs.tf                    # Stack outputs
├── dev/
│   └── terragrunt.hcl                # Dev project key and dev inputs
└── prod/
    └── terragrunt.hcl                # Prod project key and prod inputs
```

### 6.1. Master Root Configuration: `root.hcl`

```hcl
# root.hcl
remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket         = "company-tf-state-storage-prod"
    key            = "oneuptime/${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-2"
    encrypt        = true
    kms_key_id     = "arn:aws:kms:us-east-2:123456789012:key/company-global-state-key"
    dynamodb_table = "company-tf-locks"
  }
}

generate "provider" {
  path      = "provider_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    oneuptime = {
      source  = "oneuptime/oneuptime"
      version = ">= 13.0.6, < 14.0.0"
    }
  }
}

# api_key is read from ONEUPTIME_API_KEY, set per environment.
provider "oneuptime" {
  oneuptime_url = var.oneuptime_url
}
EOF
}
```

---

### 6.2. The Canonical Composition Layer: `resources/`

#### `resources/variables.tf`

```hcl
variable "application" {
  type = string
}

variable "oneuptime_url" {
  type = string
}

variable "base_domain" {
  description = "Domain the monitored services answer on, e.g. dev.example.com"
  type        = string
}

variable "monitoring_interval" {
  type = string
}

variable "publish_status_page" {
  type = bool
}

variable "teams_webhook_url" {
  type      = string
  sensitive = true
}
```

#### `resources/monitors.tf`

```hcl
locals {
  monitor_configs = {
    "api" = {
      display_name = "Core API"
      monitor_type = "API"
      target       = "https://api.${var.base_domain}/health"
    }
    "web-tls" = {
      display_name        = "Website TLS certificate"
      monitor_type        = "SSL Certificate"
      target              = "https://www.${var.base_domain}"
      monitoring_interval = "0 0 * * *"
    }
  }

  status_pages = {
    "core" = {
      name          = "Core Status"
      groups        = { "services" = {} }
      monitor_rules = { "services" = { group_key = "services", label_names = ["application"] } }
    }
  }
}
```

#### `resources/oneuptime.tf`

```hcl
module "teams_notifications" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/oneuptime/workflows-templates/teams-notification?ref=<version>"

  project_name      = var.application
  dashboard_url     = var.oneuptime_url
  teams_webhook_url = var.teams_webhook_url
}

module "oneuptime" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/oneuptime?ref=<version>"

  application = var.application

  labels_config = {
    "component" = { "application" = "#F52750", "infrastructure" = "#CED431" }
    "group"     = { "devops" = "#614C3F" }
  }

  rbac_component_mapping = {
    "application"    = ["devops"]
    "infrastructure" = ["devops"]
  }

  rbac_team_mapping = { "devops" = ["devops@example.com"] }

  monitors_component_mapping = {
    "application"    = ["api"]
    "infrastructure" = ["web-tls"]
  }

  monitor_configs  = local.monitor_configs
  monitor_defaults = { monitoring_interval = var.monitoring_interval }

  # A conditional over two different objects does not unify; filter instead.
  status_page_configs = { for key, page in local.status_pages : key => page if var.publish_status_page }

  workflow_configs           = module.teams_notifications.workflow_configs
  workflow_variable_contents = module.teams_notifications.workflow_variable_contents
}
```

---

### 6.3. Environment Invocations: `dev/`, `prod/`

The API key is handed to Terraform as an environment variable for the commands that call the
API, so it is never written to a generated file or to state.

#### `dev/terragrunt.hcl`

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "git::https://github.com/contoso-corporation/infra-live.git//resources?ref=1.0.0"

  extra_arguments "oneuptime_api_key" {
    commands = get_terraform_commands_that_need_vars()
    env_vars = {
      ONEUPTIME_API_KEY = get_env("DEV_ONEUPTIME_API_KEY")
    }
  }
}

inputs = {
  application         = "core"
  oneuptime_url       = "https://oneuptime.example.com"
  base_domain         = "dev.example.com"
  monitoring_interval = "*/5 * * * *"
  publish_status_page = false
  teams_webhook_url   = get_env("DEV_TEAMS_WEBHOOK_URL")
}
```

#### `prod/terragrunt.hcl`

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "git::https://github.com/contoso-corporation/infra-live.git//resources?ref=1.0.0"

  extra_arguments "oneuptime_api_key" {
    commands = get_terraform_commands_that_need_vars()
    env_vars = {
      ONEUPTIME_API_KEY = get_env("PROD_ONEUPTIME_API_KEY")
    }
  }
}

inputs = {
  application         = "core"
  oneuptime_url       = "https://oneuptime.example.com"
  base_domain         = "example.com"
  monitoring_interval = "* * * * *"
  publish_status_page = true
  teams_webhook_url   = get_env("PROD_TEAMS_WEBHOOK_URL")
}
```

[Documentation index](../README.md#documentation)
