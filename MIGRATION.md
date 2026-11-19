# Migration Guide

This document records the required consumer actions when upgrading between releases of this
library. It is the source of truth for upgrade behaviour: if a release is not described
here, upgrading to it requires no action beyond changing the `?ref=` tag.

To upgrade, apply every section after your pinned version up to the target, oldest first.
Newer sections are split into **Required** (the upgrade breaks or misbehaves without it),
**Recommended** (aligns an existing stack with the current standards) and **Verify**.

## 3.0.0

3.0.0 rebuilds every AWS module on one standard ([module contract](docs/module-contract.md)). No stack used the 2.x
AWS modules, so there is no upgrade path: no `moved` blocks, no deprecated inputs. Start each caller from the module
README.

### Requirements

- Terraform `>= 1.17.0` and `hashicorp/aws` `>= 6.73.0` for every AWS module; `hashicorp/archive >= 2.8.1` for
  `compute/lambda`; no upper bounds, no provider aliases.
- Modules compose each other with relative paths, so a caller pins the whole repository tag
  (`git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/<category>/<name>?ref=3.0.0`).

### What changed for a caller

- **Names** include the Region on IAM roles and the account ID and Region on S3 buckets; `name` is required on
  modules that are usually deployed more than once per environment.
- **Encryption** is one `kms` input everywhere: nothing set uses the AWS managed key, `create = true` creates a key
  for the module, `key_id` uses yours.
- **Networking, IAM and logs** use the same `security_group`, `iam_role` and `cloudwatch_logs` inputs in every module.
- **Account and organization modules** (`Scope: account`/`organization` in their README) are called once per account
  or organization and take no `name`.
- **Alarms are built in:** 18 service modules create their CloudWatch alarms by default, without actions. Route them
  with `alarms = { topic_arns = module.alarm_routing.topic_arns["<region>"] }` (us-east-1 for CloudFront and
  `CLOUDFRONT`-scope WAF), tune one with `alarms.overrides`, or turn them off with `alarms = { enabled = false }`.
  Drop any hand-wired `cloudwatch-alarms` preset entry for a module that now builds it in, or the alarms exist twice.
- **Exclusive roles, security groups and permission sets:** module roles keep only the policies given through
  `iam_role`, module security groups only their module rules, Identity Center permission sets only their listed
  policies. Anything attached outside Terraform is removed on the next apply.

### Existing AWS settings

Some modules manage settings that may already exist in an account or organization: the AWS Organizations
organization, trusted access, delegated administrators, the IAM password policy, account public access blocks and
Region settings. Adopt them with `import` blocks before the first apply; each module README shows the import IDs.

## 2.4.0

### Required

- **Remove `on_call_schedules_enabled`.** The input is gone; Terraform fails on an unknown argument.
- **Schedules are now off by default.** A stack that relied on the 2.1.0 or 2.2.0 default of one schedule
  per component sets `schedule_enabled = true` for each component that keeps one:

  ```hcl
  on_call_overrides = {
    "databases" = { schedule_enabled = true }
  }
  ```

### Verify

- A stack that had `on_call_schedules_enabled = false`: `terraform plan` shows no changes.
- A stack on the old default: the plan destroys the schedule, layer and binding of every component without
  `schedule_enabled = true`, and changes nothing else.

## 2.2.0

No required action: change `?ref=` to `2.2.0`. Schedules stay on by default.

### Recommended

- A stack that pages whole teams and keeps nobody in the schedules sets
  `on_call_schedules_enabled = false`, so OneUptime stops flagging the empty schedules.

### Verify

- With `on_call_schedules_enabled = false`, `terraform plan` destroys one `oneuptime_on_call_policy_schedule`,
  one `oneuptime_on_call_schedule_layer` and one `oneuptime_schedules_on_call_duty_escalation_rule` per
  component, and changes nothing else.

## 2.1.0

### Required

- **Incidents now page people.** With the defaults, every incident runs its component's on-call
  policy, which notifies the owning teams' members every 10 minutes, up to 10 times, until someone
  acknowledges it or it resolves. A stack that should not page sets `on_call_routing = { incidents = false }`.
  To keep the 2.0.x timings, set `on_call_escalation_rules = { escalate_after_in_minutes = 30 }` and
  `on_call_policy_config = { repeat_policy_if_no_one_acknowledges_no_of_times = 3 }`.

### Verify

- `terraform plan` adds one `oneuptime_incident_on_call_rule` per component and one
  `oneuptime_team_on_call_duty_escalation_rule` per component and owning group, and updates each
  on-call policy and escalation rule in place to the new timings unless the stack sets its own.
- Members of each owning team have notification rules in OneUptime; a team with no members, or members
  without rules, is paged without anyone hearing it.

## 2.0.1

No required action: change `?ref=` to `2.0.1`.

### Recommended

- Against OneUptime 14, give a status page's custom domain as `domain_id` (Project Settings,
  Domains) instead of `domain_name`: the name lookup fails there with "Invalid column on Domain -
  name". Nothing changes for a stack whose `domain_name` lookup already works.

### Verify

- `terraform plan` updates every `oneuptime_alert_grouping_rule` and
  `oneuptime_incident_grouping_rule` in place, once, from priority `1` (or whatever OneUptime moved
  it to) to its component's number: 10, 20, 30 and so on in component name order. A grouping rule
  created by hand in the same project that already holds one of those numbers moves one place.
- A status page given component `label_names` may show its owning groups' labels being added.
  OneUptime normally adds them already through the status page label rule, in which case the
  plan shows nothing.
- A status page that lists a group in `owner_group_names` which also owns one of its component
  labels shows that `oneuptime_status_page_team_owner` being destroyed: the status page owner rule
  keeps the group an owner. After the apply, check the page's owners in OneUptime and add the team
  again if an older server had not applied the rule to the page.
- A grouping rule or status page left tainted by a failed 2.0.0 apply against OneUptime 14 is
  replaced once; the next plan is clean.

## 2.0.0

### Required

- **The Teams template moved.** A stack that calls it changes the source from
  `//modules/oneuptime/modules/workflows-templates/teams-notification` to
  `//modules/oneuptime/workflows-templates/teams-notification` when it moves `?ref=` to `2.0.0`.

No state migration. The root module's calls keep their names (`module.monitors`,
`module.alerts`, …), so every resource address is unchanged, and the template creates no
resources. A stack that calls only `//modules/oneuptime` changes nothing but the tag.

### Recommended

- Update links into the OneUptime documentation: `modules/oneuptime/modules/<area>` is
  `modules/oneuptime/<area>`.
- Update links into the README's numbered sections: each is a page under `docs/` now, listed in
  the README's documentation table.
- Copy an example's `?ref=<version>` with the release your stack pins in place of `<version>`.

### Verify

- `terraform init -upgrade` installs the new release, and `terraform plan` shows no changes.

## 1.5.0

### Required

Every module now requires Terraform `>= 1.9.0`; `secrets-manager` keeps `>= 1.11.0`. Upgrade
Terraform in every pipeline and workstation that runs these stacks before changing the `?ref=`
tag: on 1.5–1.8, `terraform init` stops with "Unsupported Terraform Core version".

No state migration required. AWS module interfaces, resource addresses and runtime behaviour are
unchanged. This release adds `modules/oneuptime`.

### Recommended

- A stack running a local copy of the OneUptime module can point its module blocks at
  `git::https://github.com/grootan-devops/terraform-modules.git//modules/oneuptime?ref=1.5.0`
  and run `terraform init -upgrade`. Resource addresses do not change while the module block
  keeps its name.
- The published OneUptime module needs `oneuptime/oneuptime` `>= 13.0.6, < 14.0.0`. Keep the
  stack's own provider pin inside that range.
- The Teams notification template's `dashboard_url` now defaults to `https://oneuptime.com`.
  Set it explicitly for a self-hosted instance.
- Generated monitor criteria now create only what their preset promises: Offline opens an
  incident, Degraded raises an alert, Operational creates neither. A stack moved from a local
  copy sees an in-place `monitor_steps` update on every generated monitor. To keep an alert on
  Offline or an incident on Degraded, set `criteria.offline.create_alerts = true` or
  `criteria.degraded.create_incidents = true` on that monitor.

### Verify

- `terraform version` reports 1.9.0 or later wherever these stacks run.
- A plan for each environment shows no changes after the `?ref=` change.
- A stack moved from a local copy shows only the `monitor_steps` criteria updates above once
  `dashboard_url` is set to its instance.

## 1.4.0

No migration is required. This release only updates dependencies.

## 1.3.0

### Required

No state migration required. Module interfaces, resource addresses and runtime behaviour are
unchanged; change the `?ref=` tag only. This release adds the documentation index and the
consumption, provider-schema, state-migration, testing and other-provider guides.

### Recommended

None.

### Verify

- A plan for each environment shows no changes after the `?ref=` change.

## 1.2.0

No state migration required. Terraform module interfaces and runtime behavior remain unchanged. CI verification container is upgraded to `grootantech/toolkit:1.1.0` and reusable workflows are pinned to `github-ci-library` `@1.3.1`. The S3 `public_access_block` input remains accepted but has always been ignored; remove caller overrides that assume it can disable public access blocking.

KMS, Batch, EKS cluster, and RDS/Postgres no longer declare six unused context data sources. No managed resource address changes; consumers with existing state should review their next plan for data-source entry removal.

## 1.1.1

No migration is required. Only the PR verification container reference changes.

## 1.1.0

No migration is required. Terraform module interfaces remain unchanged.

## 1.0.0

No migration is required for the initial release.
