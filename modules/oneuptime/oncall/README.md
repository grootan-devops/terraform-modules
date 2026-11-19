# `oncall`

One on-call setup per component in `rbac_component_mapping`:

| Resource | Name |
| --- | --- |
| `oneuptime_on_call_policy` | `<component>-oncall-policy` |
| `oneuptime_on_call_policy_owner_rule` | `<component>-oncall-policy-owner-rule` |
| `oneuptime_escalation_rule` | `<component>-oncall-policy-escalation-rule` |
| `oneuptime_on_call_policy_schedule` | `<component>-oncall-schedule`; only with `schedule_enabled` |
| `oneuptime_on_call_schedule_layer` | `<component>-oncall-schedule-layer`; only with `schedule_enabled` |
| `oneuptime_schedules_on_call_duty_escalation_rule` | binds the schedule to the escalation rule; only with `schedule_enabled` |
| `oneuptime_team_on_call_duty_escalation_rule` | one per owning group: the escalation rule pages the group's team |

Timings come from `on_call_policy_config` and `on_call_escalation_rules` in
[../variables-oncall.tf](../variables-oncall.tf): page the owning teams again
every 10 minutes and repeat up to 10 times while nobody acknowledges. Paging stops
when someone acknowledges the incident or it resolves. `on_call_overrides` gives one
component its own timings and leaves the rest on the stack-wide ones:

```hcl
on_call_overrides = {
  "security" = { escalate_after_in_minutes = 5 }
}
``` `on_call_routing` decides
which records start the policy (incidents by default; see
[incidents](../incidents/README.md) and [alerts](../alerts/README.md)).

| Output | Contents |
| --- | --- |
| `on_call_policy_ids` | component -> on-call policy id. |
| `on_call_schedule_ids` | component -> schedule id, for components with `schedule_enabled`. |

## The schedule layer

A component with `schedule_enabled` gets one layer, shaped by `on_call_schedule_layer_config` in
[../variables-oncall.tf](../variables-oncall.tf). The shipped default is a
weekly rotation covering the whole clock:

```hcl
on_call_schedule_layer_config = {
  rotation    = { interval_type = "Week", interval_count = 1 }
  restriction = { type = "None" }
}
```

`restriction.type` is `None`, `Daily` or `Weekly`. Restricting a layer leaves
the hours outside the window uncovered, so it is opt-in:

```hcl
restriction = {
  type = "Weekly"
  weekly = [{
    start_day  = "Monday"
    end_day    = "Friday"
    start_time = "2026-01-01T09:00:00.000Z"
    end_time   = "2026-01-01T17:00:00.000Z"
  }]
}
```

`starts_at`, `hand_off_time` and the restriction times are ISO 8601 instants -
OneUptime types them as date-times and rejects a bare number. They are fixed
literals rather than `timestamp()` so a plan does not diff on every run.

[locals.tf](locals.tf) converts this into the tagged `_type`/`value` JSON that
OneUptime expects; `main.tf` only assigns it.

Rota *membership* is still set in the OneUptime dashboard - it cannot be managed
with a project-scoped API key, so schedules are off by default: the escalation rule
pages only the owning teams, and OneUptime has no empty schedule to flag. A component
that should have a rotation asks for one, and its people are added in the dashboard:

```hcl
on_call_overrides = {
  "databases" = { schedule_enabled = true }
}
```
