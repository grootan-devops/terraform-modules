# `incidents`

The incident-side twin of [`../alerts`](../alerts/README.md). One rule per
component in `rbac_component_mapping`:

| Resource | What it does |
| --- | --- |
| `oneuptime_incident_owner_rule` | Any incident on a monitor labelled with the component is owned by the groups that own that component. |
| `oneuptime_incident_label_rule` | Adds the component label and the labels of its owning groups to those incidents. |
| `oneuptime_incident_grouping_rule` | Rolls repeated incidents into one episode, per `incident_grouping_rule_config`. |

A component owned by two groups produces **one** rule naming both teams, not one
rule per group — `component_definitions` resolves the group list into a set.

Inputs are set on the parent module (`incident_grouping_rule_config` in
[../variables-incidents.tf](../variables-incidents.tf)); this submodule
receives them already normalized, along with resolved label and team ids.

The grouping rule's `on_call_duty_policies` is still `[]`. To page the rota when
an episode opens, pass `module.oncall.on_call_policy_ids` in from
[../main.tf](../main.tf) and index it by `each.key`.
