# `modules/oncall`

One on-call setup per component in `rbac_component_mapping`:

| Resource | Name |
| --- | --- |
| `oneuptime_on_call_policy` | `<component>-oncall-policy` |
| `oneuptime_on_call_policy_owner_rule` | `<component>-oncall-policy-owner-rule` |
| `oneuptime_escalation_rule` | `<component>-oncall-policy-escalation-rule` |
| `oneuptime_on_call_policy_schedule` | `<component>-oncall-schedule` |
| `oneuptime_on_call_schedule_layer` | `<component>-oncall-schedule-layer` |
| `oneuptime_schedules_on_call_duty_escalation_rule` | binds the schedule to the escalation rule |

Timings come from `on_call_policy_config` and `on_call_escalation_rules` in
[../../variables-oncall.tf](../../variables-oncall.tf): repeat 3× if nobody
acknowledges, escalate after 30 minutes.

| Output | Contents |
| --- | --- |
| `on_call_policy_ids` | component -> on-call policy id. |
| `on_call_schedule_ids` | component -> schedule id. |

## The schedule layer

Every component gets one layer, shaped by `on_call_schedule_layer_config` in
[../../variables-oncall.tf](../../variables-oncall.tf). The shipped default is a
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
with a project-scoped API key.
