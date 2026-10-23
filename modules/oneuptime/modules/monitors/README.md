# `modules/monitors`

Creates one `oneuptime_monitor` per entry in `monitor_configs`, plus the
`oneuptime_monitor_group`, `oneuptime_monitor_owner_rule` and
`oneuptime_monitor_label_rule` for each component in `rbac_component_mapping`.

Inputs are set on the **parent module** (`modules/oneuptime`), not here — this
submodule receives them already normalized, along with resolved label and team
ids. See [../../README.md](../../README.md) for how to call the module; this
file is the reference for everything monitor-shaped you can put in it.

The module requires provider `oneuptime/oneuptime` `>= 13.0.6, < 14.0.0`; the
allowed values below were collected against 12.0.24. Values outside the listed
sets are rejected client-side by the provider, or are accepted by the API but not
selectable in the OneUptime dashboard afterwards.

| Output | Contents |
| --- | --- |
| `monitor_ids` | monitor key -> monitor id. Consumed by `modules/status-pages`. |
| `monitor_group_ids` | component -> monitor group id. |
| `monitor_status_ids` | `operational` / `degraded` / `offline` -> monitor status id. Consumed by `modules/workflows`. |

---

## 1. The short form

A monitor declares the minimum its type needs. The probe step and the criteria
are derived:

```hcl
"argocd" = {
  display_name = "Argo CD"
  description  = "Continuous delivery for core workloads"
  monitor_type = "API"
  target       = "http://argocd-server.argo-d.svc.cluster.local/healthz"
}
```

That is a complete monitor. From `monitor_type` and `target` the module builds:

* **the step** — `monitor_destination_type = "URL"`, `request_type = "GET"`,
  timeout, retry count and the stack-wide `request_headers`
  ([§2](#2-monitor_defaults));
* **three criteria**, in evaluation order, each flipping the monitor status:

  | Criterion | Filters (`Any`/`All`) | Status | Side effect |
  | --- | --- | --- | --- |
  | `Offline` | not online, **or** status code ≠ 200, **or** request timed out | Offline | opens a **Critical Incident** |
  | `Degraded` | status code = 200 **and** response time > 5000ms averaged over 15min | Degraded | raises a **Low alert** |
  | `Operational` | online **and** status code = 200 | Operational | — |

Labels are never written in `monitor_configs`: `monitors_component_mapping`
derives the component, group and project labels, so labelling stays consistent.

Only what differs from that baseline is written per monitor. Three levels of
override, lowest to highest:

1. the defaults in [`../../variables-monitors.tf`](../../variables-monitors.tf)
2. `monitor_defaults` passed to the module — the stack-wide baseline
3. the monitor's own entry — `thresholds` for the whole monitor,
   `criteria.<preset>` for one criterion

```hcl
"gitlab" = {
  display_name = "GitLab"
  monitor_type = "API"
  target       = "http://gitlab-webservice-default.gitlab:8181/-/health"

  step = {
    request_headers = { "Accept" = "text/plain" }   # merged over the stack's
  }

  criteria = {
    offline = {
      body_contains        = "GitLab OK"            # adds a Response Body filter
      incident_description = "The GitLab health endpoint is failing."
      remediation_notes    = "Check gitlab-webservice-default, then Gitaly and PostgreSQL."
    }
    degraded = {
      response_time_ms = 3000                       # this monitor is slower
    }
  }
}
```

**`criteria` carries values, never membership.** Naming one preset there does
not drop the others — use `criteria_presets` to narrow or reorder the set:

```hcl
criteria_presets = ["offline", "operational"]   # no Degraded criterion
```

## 2. `monitor_defaults`

The stack-wide baseline. Every key is `optional()`, so overriding one keeps
the shipped value for the rest:

```hcl
module "oneuptime" {
  # ...
  monitor_defaults = {
    monitoring_interval = "*/2 * * * *"
    monitor_step = {
      request_headers = { "User-Agent" = "OneUptime-Probe/core" }
    }
    thresholds = {
      response_time_ms = 1500
    }
  }
}
```

### Envelope and step

| Key | Default | Applied to |
| --- | --- | --- |
| `monitoring_interval` | `"* * * * *"` | the monitor |
| `disable_active_monitoring` | `false` | the monitor |
| `minimum_probe_agreement` | `1` | the monitor |
| `monitor_step.request_timeout_in_ms` | `5000` | every step |
| `monitor_step.retry_count` | `3` | every step |
| `monitor_step.do_not_follow_redirects` | `false` | every step |
| `monitor_step.allow_self_signed_certificates` | `false` | every step |
| `monitor_step.request_headers` | `{}` | every step of an **API / Website** monitor |
| `criteria.filter_condition` | `"All"` | every criterion |
| `criteria.is_enabled` | `true` | every criterion |

`request_headers` is the one key that **deep-merges**: a monitor adding `Accept`
keeps the stack-wide `User-Agent`. Everything else is replaced wholesale. It
is only applied to the types that actually issue a request, so a Server or
heartbeat monitor is left untouched.

### `thresholds` — what the generated criteria compare against

Overridable for a whole monitor (`thresholds = {...}`) or for one criterion
(`criteria.<preset>.<key>`).

| Key | Default | Used by |
| --- | --- | --- |
| `expected_status_code` | `200` | API, Website |
| `response_time_ms` | `5000` | API, Website, Ping, IP, Port |
| `evaluate_over_time_minutes` | `15` | API, Website — `2\|3\|5\|10\|15\|20\|30\|45\|60` |
| `evaluate_over_time_type` | `"Average"` | API, Website |
| `evaluate_over_time_no_data_policy` | `"Ignore"` | API, Website |
| `packet_loss_percent` | `10` | Ping, IP |
| `jitter_ms` | `50` | Ping, IP |
| `certificate_expiry_days` | `21` | SSL Certificate |
| `domain_expiry_days` | `30` | Domain |
| `dnssec_expiry_days` | `7` | DNSSEC |
| `heartbeat_timeout_minutes` | `60` | Incoming Request, Incoming Email |
| `execution_time_ms` | `10000` | Custom JavaScript Code, Synthetic Monitor |
| `query_time_ms` | `5000` | SQL Query |
| `dns_response_time_ms` | `500` | DNS |
| `cpu_percent` / `memory_percent` / `disk_percent` / `swap_percent` | `90` / `90` / `85` / `50` | Server |
| `disk_path` | `"/"` | Server |

### `severities`

| Key | Default | Allowed |
| --- | --- | --- |
| `severities.incident` | `"critical"` | `critical` \| `major` \| `minor` |
| `severities.alert` | `"low"` | `high` \| `low` |

The module resolves these names to ids itself
([`data.tf`](data.tf)) — a stack does not declare severity or monitor status
data sources to write a monitor.

## 3. The criteria presets

Three presets, identical in shape for every monitor type. Only the filters
differ, so only the filters are in the catalogue
([`criteria.tf`](criteria.tf)); the name, description, status flip and the
incident or alert are generated once, generically.

| Preset | Order | Condition | Status | Creates |
| --- | --- | --- | --- | --- |
| `offline` | 1st | `Any` | Offline | incident, at `severities.incident` |
| `degraded` | 2nd | `All` | Degraded | alert, at `severities.alert` |
| `operational` | last | `All` | Operational | — |

Order is fixed by the preset, not by the order they are listed — criteria are
evaluated first-match-wins, so the worst case has to come first.

### Filters per monitor type

| `monitor_type` | `offline` | `degraded` | `operational` |
| --- | --- | --- | --- |
| `API`, `Website` | not online / code ≠ `expected_status_code` / timed out / body missing `body_contains` | code = expected **and** response time > `response_time_ms` over `evaluate_over_time_minutes` | online **and** code = expected |
| `Ping`, `IP` | not online / timed out | packet loss > `packet_loss_percent` / jitter > `jitter_ms` / response time > `response_time_ms` | online |
| `Port` | not online / timed out | response time > `response_time_ms` | online |
| `SSL Certificate` | expired / not valid / self-signed | expires in < `certificate_expiry_days` | valid certificate |
| `Server` | not online | CPU / memory / swap / disk over their percent thresholds, disk at `disk_path` | online |
| `Custom JavaScript Code`, `Synthetic Monitor` | `Error` is not empty | execution time > `execution_time_ms` | `Error` is empty |
| `DNS` | DNS not online / record missing | DNS response time > `dns_response_time_ms` | DNS online |
| `DNSSEC` | chain invalid / DNSKEY missing / DS missing at parent / no resolver consensus | signature expires in < `dnssec_expiry_days` | chain valid |
| `Domain` | domain expired | expires in < `domain_expiry_days` | not expired |
| `SQL Query` | SQL not online / query error | execution time > `query_time_ms` | SQL online |
| `Incoming Request` | nothing received in `heartbeat_timeout_minutes` | *(no preset)* | received within the window |
| `Incoming Email` | no mail in `heartbeat_timeout_minutes` | *(no preset)* | mail received within the window |
| `Manual` | *(none — no steps at all)* | | |

Every other `monitor_type` has no presets and must write `monitor_steps` out in
full ([§6](#6-escape-hatches)); the module validates this rather than producing
a monitor that checks nothing.

## 4. `monitor_configs` schema

The key is the monitor slug used in `monitors_component_mapping`. Only mapped
slugs are created; an entry whose slug is not mapped is ignored.

### Top level

| Field | Notes |
| --- | --- |
| `display_name` | **required**. Also the subject of every generated name and incident title |
| `monitor_type` | **required**, see [§5](#5-allowed-values) |
| `description` | |
| `target` | destination to probe. **Required** for API, Website, Ping, IP, Port, SSL Certificate |
| `target_type` | `URL` \| `IP` \| `Hostname`. Defaults per type — `URL` for API/Website/SSL, `Hostname` for Ping/Port, `IP` for IP |
| `port` | **required** for Port monitors |
| `step` | anything else the generated step needs, passed through verbatim — see [§6](#6-escape-hatches) |
| `thresholds` | threshold overrides for every criterion of this monitor |
| `criteria` | `preset -> values`, see below |
| `criteria_presets` | which presets to generate. Defaults to all the ones the type supports |
| `extra_criteria` | fully-formed criteria, evaluated after `degraded` and before `operational` |
| `monitor_steps` | full escape hatch. Opts the monitor out of step generation entirely |
| `monitoring_interval` | cron string, see [§5](#5-allowed-values) |
| `disable_active_monitoring` | `true` pauses checks |
| `minimum_probe_agreement` | `null` = all probes must agree |
| `depends_on_monitors` | set of monitor ids, e.g. `[oneuptime_monitor.this["k8s-cluster"].id]` |
| `suppress_alerts_when_parent_monitor_statuses` | only read when `depends_on_monitors` is non-empty |
| `monitor_template_id` | provision from a template instead of steps |
| `custom_fields` | `jsonencode({...})` |

Entries are **heterogeneous objects** — an API monitor carries `target`, a Port
monitor carries `port`, a Manual monitor carries neither. `var.monitor_configs`
is `type = any` so this is allowed.

### `criteria.<preset>`

Every threshold from [§2](#2-monitor_defaults) is valid here, plus:

| Field | Default | Notes |
| --- | --- | --- |
| `name` | the preset's name | `Offline` / `Degraded` / `Operational` |
| `description` | `"<display_name> is …"` | |
| `filter_condition` | the preset's | `All` \| `Any` |
| `is_enabled` | `true` | |
| `body_contains` | — | API / Website only: adds a `Response Body` filter to `offline` |
| `incident_severity` | `severities.incident` | `critical` \| `major` \| `minor` |
| `incident_title` | `"<display_name> is offline"` | |
| `incident_description` | `"<display_name> failed its <type> check."` | |
| `create_incidents` | `true` on `offline` | |
| `alert_severity` | `severities.alert` | `high` \| `low` |
| `alert_title` | `"<display_name> is degraded"` | |
| `alert_description` | `"<display_name> responded outside its expected thresholds."` | |
| `create_alerts` | `true` on `degraded` | |
| `remediation_notes` | — | attached to whichever of the two the criterion creates |
| `overrides` | `{}` | merged **over** the finished criterion — raw provider fields, last word |

The generated incident and alert are always `auto_resolve = true`,
`is_private = false`, and the incident shows on the status page. Anything else
goes through `overrides`.

## 5. Allowed values

### `monitor_type`

```text
Manual | Website | API | Ping | IP | Port | Server | SSL Certificate
Incoming Request | Incoming Email | Synthetic Monitor
Custom JavaScript Code | SQL Query | DNS | DNSSEC | Domain
External Status Page | Network Device | Logs | Metrics | Traces
Exceptions | Profiles | Security Events | Kubernetes | Docker
Docker Swarm | Podman | Proxmox | Ceph | Host | IoT Device
```

### `monitoring_interval`

Cron expressions. These are the values the OneUptime dashboard offers — anything
else is applied but is not selectable in the UI afterwards.

| Cron | Meaning |
| --- | --- |
| `* * * * *` | every minute |
| `*/2 * * * *` | every 2 minutes |
| `*/5 * * * *` | every 5 minutes |
| `*/10 * * * *` | every 10 minutes |
| `*/15 * * * *` | every 15 minutes |
| `*/30 * * * *` | every 30 minutes |
| `0 * * * *` | every hour |
| `0 0 * * *` | every day |
| `0 0 * * 0` | every week |

### `filter_type`

Only needed when writing criteria by hand.

```text
Equal To | Not Equal To | Greater Than | Less Than
Greater Than Or Equal To | Less Than Or Equal To
Contains | Not Contains | Starts With | Ends With
Is Empty | Is Not Empty | True | False
Not Recieved In Minutes | Recieved In Minutes      <- misspelling is upstream
Evaluates To True | Is Executing | Is Not Executing
Anomalously High | Anomalously Low | Anomalous     <- Metrics monitors only
```

### `check_on`, by monitor type

| Monitor type | `check_on` values |
| --- | --- |
| Any probe monitor | `Is Online`, `Is Request Timeout`, `Response Time (in ms)` |
| Ping / IP | `Packet Loss (in %)`, `Jitter (in ms)` |
| API / Website | `Response Status Code`, `Response Header`, `Response Header Value`, `Response Body`, `Request Body`, `Request Header`, `Request Header Value`, `JavaScript Expression` |
| Server | `Disk Usage (in %)`, `CPU Usage (in %)`, `Memory Usage (in %)`, `Swap Usage (in %)`, `CPU IO Wait (in %)`, `Load Average (1 minute)`, `Load Average (5 minute)`, `Load Average (15 minute)`, `Server Process Name`, `Server Process Command`, `Server Process PID` |
| SSL Certificate | `Expires In Hours`, `Expires In Days`, `Is Self Signed Certificate`, `Is Expired Certificate`, `Is Valid Certificate`, `Is Not A Valid Certificate` |
| Incoming Request | `Incoming Request`, `Request Body`, `Request Header`, `Request Header Value` |
| Incoming Email | `Email Subject`, `Email Body`, `Email From Address`, `Email To Address`, `Email Received` |
| Custom JS / Synthetic | `Result Value`, `Error`, `Execution Time (in ms)` |
| Synthetic Monitor | `Screen Size`, `Browser Type` |
| Logs | `Log Count` |
| Traces | `Span Count` |
| Exceptions | `Exception Count` |
| Profiles | `Profile Count` |
| Metrics | `Metric Value` |
| DNS | `DNS Is Online`, `DNS Response Time (in ms)`, `DNS Record Value`, `DNS Record Exists`, `DNSSEC Is Valid` |
| DNSSEC | `DNSSEC Chain Is Valid`, `DNSSEC DNSKEY Record Exists`, `DNSSEC DS Record Exists At Parent`, `DNSSEC Signature Expires In Days`, `DNSSEC Resolver Consensus (AD Flag)`, `DNSSEC Nameservers Are Consistent` |
| Domain | `Domain Expires In Days`, `Domain Registrar`, `Domain Name Server`, `Domain Status Code`, `Domain Is Expired` |
| SQL Query | `SQL Is Online`, `SQL Query Row Count`, `SQL Query Scalar Value`, `SQL Query Execution Time (in ms)`, `SQL Query Error` |
| External Status Page | `External Status Page Is Online`, `External Status Page Overall Status`, `External Status Page Component Status`, `External Status Page Active Incidents`, `External Status Page Response Time (in ms)` |
| Network Device | `SNMP Device Is Online`, `SNMP OID Value`, `SNMP OID Exists`, `SNMP Response Time (in ms)`, `SNMP Interface Is Down`, `SNMP Trap Received (Trap OID)`, `SNMP Interface Utilization (in %)`, `SNMP Interface Errors (per second)` |

## 6. Escape hatches

Four of them, reached for in this order.

### `step` — extra fields on the generated step

Merged over the generated step, so the criteria stay generated. This is where
everything the type needs beyond a destination goes.

| Field | Type | Applies to |
| --- | --- | --- |
| `request_type` | string | API — `GET` \| `POST` \| `PUT` \| `DELETE` \| `HEAD` \| `PATCH` |
| `request_headers` | map | API / Website — deep-merged with the stack's |
| `request_body` | string | API (POST/PUT/PATCH only) |
| `do_not_follow_redirects` | bool | API / Website |
| `allow_self_signed_certificates` | bool | API / Website |
| `tls_client_certificate` | string | mTLS — PEM or `"{{monitorSecrets.<name>}}"` |
| `tls_client_key` | string | mTLS |
| `tls_client_key_passphrase` | string | mTLS |
| `request_timeout_in_ms` | number | capped at `60000` server-side |
| `retry_count` | number | capped at `3` server-side |
| `custom_code` | string | JS (Custom JavaScript Code) or Playwright (Synthetic Monitor) |
| `screen_size_types` | list | Synthetic — `Mobile` \| `Tablet` \| `Desktop` |
| `browser_types` | list | Synthetic — `Chromium` \| `Firefox` |
| `retry_count_on_error` | number | Synthetic |

Plus the per-type JSON sub-configs, each written with `jsonencode()`:
`dns_monitor`, `domain_monitor`, `dnssec_monitor`, `sql_monitor`,
`external_status_page_monitor`, `network_device_monitor`, `log_monitor`,
`trace_monitor`, `metric_monitor`, `exception_monitor`, `profile_monitor`,
`kubernetes_monitor`, `docker_monitor`, `docker_swarm_monitor`, `podman_monitor`,
`proxmox_monitor`, `ceph_monitor`, `host_monitor`, `iot_monitor`.

### `criteria.<preset>.overrides` — raw fields on a generated criterion

Merged over the finished criterion, after everything else.

```hcl
criteria = {
  offline = {
    overrides = {
      incident_grouping = jsonencode({          # Incoming Request monitors only
        groupByJSONPath      = "$.cluster"
        resolvedWhenJSONPath = "$.status"
        resolvedWhenValue    = "ok"
      })
    }
  }
}
```

### `extra_criteria` — a check no preset covers

Fully-formed criteria, appended after `degraded` and before `operational`, in
the order listed.

```hcl
extra_criteria = [
  {
    name             = "Rate limited"
    filter_condition = "All"
    filters          = [{ check_on = "Response Status Code", filter_type = "Equal To", value = "429" }]
    change_monitor_status = true
    monitor_status_id     = data.oneuptime_monitor_status.degraded.id
  },
]
```

Raw criteria reference status and severity ids directly, so a stack that uses
them declares the data sources it needs in its own configuration:

```hcl
data "oneuptime_monitor_status" "degraded" { name = "Degraded" }
```

### `monitor_steps` — the whole thing by hand

Opts the monitor out of step generation. Needed for multi-step monitors and for
the types with no preset catalogue. A step that omits `criteria` still picks up
the generated ones.

```hcl
"multi-region" = {
  display_name = "Checkout API"
  monitor_type = "API"
  monitor_steps = [
    { monitor_destination = "https://eu.api.example.com/health", monitor_destination_type = "URL", request_type = "GET" },
    { monitor_destination = "https://us.api.example.com/health", monitor_destination_type = "URL", request_type = "GET" },
  ]
}
```

Each criterion written by hand takes: `name` (**required**), `description`,
`filter_condition`, `filters` (**required**), `is_enabled`,
`change_monitor_status`, `monitor_status_id`, `create_incidents`, `incidents`,
`create_alerts`, `alerts`, `incident_grouping`. Each filter takes: `check_on`
(**required**), `filter_type`, `value` (**always a string**),
`evaluate_over_time`, `evaluate_over_time_minutes`, `evaluate_over_time_type`,
`evaluate_over_time_no_data_policy`, `disk_path`, `metric_monitor_options`,
`snmp_monitor_options`.

`incidents[*]`: `title`, `description`, `incident_severity_id`,
`auto_resolve_incident`, `show_incident_on_status_page`, `is_private`,
`remediation_notes`, `on_call_policy_ids`, `label_ids`, `owner_team_ids`,
`owner_user_ids`. `alerts[*]`: `title`, `description`, `alert_severity_id`,
`auto_resolve_alert`, `is_private`, `remediation_notes`, `on_call_policy_ids`,
`label_ids`, `owner_team_ids`, `owner_user_ids`.

## 7. One example per monitor family

### API / Website

```hcl
"argocd" = {
  display_name = "Argo CD"
  monitor_type = "API"                  # "Website" renders the page instead
  target       = "http://argocd-server.argo-d.svc.cluster.local/healthz"
}
```

### Ping / IP — ICMP reachability

```hcl
"edge-gateway" = {
  display_name        = "Edge gateway"
  monitor_type        = "Ping"          # or "IP"
  target              = "10.0.0.1"
  target_type         = "IP"
  monitoring_interval = "* * * * *"
  thresholds          = { packet_loss_percent = 5 }
}
```

### Port — TCP connect

```hcl
"postgres-primary" = {
  display_name = "PostgreSQL primary"
  monitor_type = "Port"
  target       = "postgres.database.svc.cluster.local"
  port         = 5432
}
```

### SSL Certificate

```hcl
"git-tls" = {
  display_name        = "Git server TLS certificate"
  monitor_type        = "SSL Certificate"
  target              = "https://git.example.com"
  monitoring_interval = "0 0 * * *"
  thresholds          = { certificate_expiry_days = 30 }
}
```

### Server — agent-reported host metrics

No destination; the agent posts in using the monitor's
`server_monitor_secret_key`.

```hcl
"build-runner-01" = {
  display_name = "Build runner 01"
  monitor_type = "Server"
  thresholds   = { disk_path = "/var", disk_percent = 80 }
}
```

### Incoming Request — heartbeat / dead-man's switch

The job pings the monitor URL; `heartbeat_timeout_minutes` is the window, and it
belongs on the monitor rather than one criterion because both the offline and
the operational criterion read it.

```hcl
"nightly-backup" = {
  display_name = "Nightly backup job"
  monitor_type = "Incoming Request"     # or "Incoming Email"
  thresholds   = { heartbeat_timeout_minutes = 1500 }
  criteria = {
    offline = {
      incident_severity = "major"
      remediation_notes = "Check the backup CronJob in the ops namespace."
    }
  }
}
```

### Custom JavaScript Code / Synthetic Monitor

```hcl
"gitlab-login-flow" = {
  display_name        = "GitLab login flow"
  monitor_type        = "Synthetic Monitor"
  monitoring_interval = "*/30 * * * *"
  step = {
    browser_types     = ["Chromium", "Firefox"]
    screen_size_types = ["Desktop", "Mobile"]
    custom_code       = <<-JS
      await page.goto('https://git.example.com/users/sign_in');
      await page.fill('#user_login', '{{monitorSecrets.gitlab_user}}');
      await page.fill('#user_password', '{{monitorSecrets.gitlab_password}}');
      await page.click('input[type=submit]');
      await page.waitForSelector('[data-testid=user-menu]');
      return { data: 'ok' };
    JS
  }
}
```

### DNS / DNSSEC / Domain / SQL Query

The type's JSON sub-config is the only thing these need beyond the type itself.

```hcl
"gitlab-dns" = {
  display_name        = "GitLab DNS record"
  monitor_type        = "DNS"
  monitoring_interval = "*/15 * * * *"
  step = {
    # recordType: A | AAAA | CNAME | MX | NS | TXT | SOA | PTR | SRV | CAA
    dns_monitor = jsonencode({
      queryName  = "git.example.com"
      recordType = "A"
      hostname   = "1.1.1.1"   # resolver; "" = probe default
      port       = 53
      timeout    = 5000
      retries    = 3
    })
  }
}
```

```hcl
"example-domain" = {
  display_name        = "example.com domain registration"
  monitor_type        = "Domain"
  monitoring_interval = "0 0 * * *"
  step = {
    domain_monitor = jsonencode({
      domainName   = "example.com"
      lookupMethod = "Auto"    # Auto | RDAP | WHOIS
      timeout      = 10000
      retries      = 3
    })
  }
}
```

### Manual — no probing at all

Status is driven by humans or workflows.

```hcl
"planned-migration" = {
  display_name = "Datacenter migration"
  description  = "Tracked by hand during the migration window"
  monitor_type = "Manual"
}
```

### Types with no preset catalogue

`Logs`, `Metrics`, `Traces`, `Exceptions`, `Profiles`, `Kubernetes`, `Docker`,
`Network Device`, `External Status Page` and the rest have no presets: their
criteria depend entirely on the telemetry being queried. They write
`monitor_steps` in full ([§6](#6-escape-hatches)), and the module fails
validation if they do not.

## 8. Adding a monitor

1. Add the slug to `monitors_component_mapping` under the right component.
2. Add an entry with the same slug to `monitor_configs`, in the stack's
   `locals.tf` — `display_name`, `monitor_type` and whatever [§7](#7-one-example-per-monitor-family)
   shows for that family.
3. Set only what differs from the baseline.
4. `terraform fmt -recursive && terraform validate && terraform plan`.

## 9. Gotchas

* `value` in a hand-written filter is **always a string**, even for numbers and
  durations. Generated criteria handle this themselves.
* Criteria are evaluated **top to bottom, first match wins**. Presets are
  ordered for you; `extra_criteria` land between `degraded` and `operational`.
* `Not Recieved In Minutes` / `Recieved In Minutes` are misspelled upstream. The
  misspelling is required.
* Omit `incidents` / `alerts` entirely rather than passing `[]`.
* `request_timeout_in_ms` is capped at `60000` and `retry_count` at `3`
  server-side — larger values silently clamp.
* The `*_monitor` JSON blobs are normalized by the server. Send the full
  documented shape or every plan will show drift.
* Never inline PEM or passwords. Store them as monitor secrets and reference
  `"{{monitorSecrets.<name>}}"`, so they stay out of state.
* Setting `monitor_steps` opts the monitor out of step generation completely;
  `target`, `port` and `step` are then ignored.
* Any slug in `monitor_configs` that is missing from
  `monitors_component_mapping` is not created. The reverse is a validation
  error naming the missing slugs.
* Run `terraform fmt -recursive` before raising a pull request.
