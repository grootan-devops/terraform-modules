# `modules/workflows`

Creates `oneuptime_workflow` and its `oneuptime_workflow_variable`s from
`workflow_configs`. A workflow is described as **nodes**; the module generates
the canvas JSON — node and edge ids, edges, layout — so there is no JSON to
write and no UUID to invent.

Inputs are set on the **parent module** (`modules/oneuptime`), not here. Types and
validation live in [../../variables-workflows.tf](../../variables-workflows.tf).

| Output | Contents |
| --- | --- |
| `workflow_ids` | workflow key -> workflow id. |
| `workflow_variable_ids` | `"<workflow key>.<variable name>"` -> variable id. |
| `workflow_graphs` | workflow key -> the canvas JSON that is sent. Handy to inspect with `terraform console`. |

## `workflow_configs`

| Key | Type | Required | Notes |
| --- | --- | --- | --- |
| `name` | `string` | yes | Display name in the console. |
| `description` | `string` | no | |
| `is_enabled` | `bool` | no, `true` | |
| `nodes` | `list(object)` | yes, or `graph` | See below. In flow order. |
| `graph` | `string` | no | Escape hatch: the canvas as raw JSON instead of `nodes`. Pass `file()`. |
| `variables` | `map(object)` | no | Keyed by variable name; nodes read `{{local.variables.<name>}}`. Each has `description` and `is_secret` (default `true`). |

### A node

| Key | Type | Notes |
| --- | --- | --- |
| `key` | `string` | Names the node. Later nodes read its output as `{{local.components.<key>.returnValues...}}`. Unique per workflow. |
| `type` | `string` | The OneUptime component, e.g. `alert-on-create`, `microsoft-teams-send-message-to-channel`, `javascript`, `if-else`, `log`. |
| `trigger` | `bool` | `true` on the node the workflow starts from. Exactly one per workflow. |
| `arguments` | `map(string)` | The component's arguments. Structured ones (a trigger's `select`, a `query`) go through `jsonencode()`. |
| `next` | `map(string)` | Output handle -> node key, e.g. `{ success = "notify", error = "log" }`. Omit it and the node hands over, on `success`, to the node listed after it. A branching node (`if-else` uses `yes` / `no`) sets it. `{}` ends the flow. |
| `x`, `y` | `number` | Canvas position. Defaults to one node per row. |

Ids are derived from the workflow and node keys (`uuidv5`), so they are stable
between plans. **Renaming a node key changes its id.**

### Ids that differ per project

Put these in an argument and the module substitutes the project's own value, so
the same workflow works in every project:

| Token | Replaced with |
| --- | --- |
| `@@project_id@@` | the OneUptime project id, e.g. in a dashboard link |
| `@@monitor_status.operational@@`, `.degraded@@`, `.offline@@` | the project's monitor status ids |

### Example

```hcl
workflow_configs = {
  "alert-created" = {
    name        = "Core — Teams — Alert created"
    description = "Posts to Microsoft Teams whenever an alert is created."

    nodes = [
      {
        key     = "alert-on-create-1"
        type    = "alert-on-create"
        trigger = true
        arguments = {
          select = jsonencode({ _id = true, title = true, alertSeverity = { name = true } })
        }
      },
      {
        key  = "teams-1"
        type = "microsoft-teams-send-message-to-channel"
        arguments = {
          text        = "ALERT: {{local.components.alert-on-create-1.returnValues.model.title}}"
          "webhook-url" = "{{local.variables.teamsWebhookUrl}}"
        }
      },
    ]

    variables = { "teamsWebhookUrl" = { description = "Teams webhook URL" } }
  }
}
```

That is a complete workflow: the trigger hands over to the Teams node, and the
module generates the two nodes, the edge and their ids. Component names and
argument names are the ones the console uses — build the workflow once in the
console, or copy a similar one from
[`teams-notification`](../workflows-templates/teams-notification/locals.tf).

## Variable content is write-once

OneUptime never returns the content of a secret variable. It is applied when the
variable is created (from `workflow_variable_contents["<workflow>.<variable>"]`,
a sensitive map, else a placeholder) and `ignore_changes` keeps it out of every
later plan. Rotate it in the console.

## Adopting a workflow built in the console

Import it, then describe it as `nodes` and compare. `terraform console` prints
the generated canvas (`module.<name>.workflow_graphs["<key>"]`) next to the
workflow's `graph` in `terraform state show`.

```sh
terraform import 'module.<name>.module.workflows.oneuptime_workflow.this["<key>"]' <workflow id>
terraform import 'module.<name>.module.workflows.oneuptime_workflow_variable.this["<key>.<variable>"]' <variable id>
```

A generated canvas has its own ids and layout, so the first plan after adopting
shows a `graph` update even when the workflow is identical; check the nodes,
arguments and edges, not the ids.

Labels and owner rules are not managed here: workflows carry no labels today, and
adding them would change existing workflows.
