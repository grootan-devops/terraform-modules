# `workflows-templates/teams-notification`

The standard Microsoft Teams notifications for a OneUptime project, so a project
does not repeat them. It creates **no resources**: it builds `workflow_configs`
for the `oneuptime` module, which creates the workflows. State addresses are
therefore the same as for workflows written by hand.

| Workflow key | Posts when |
| --- | --- |
| `alert-created` | an alert is created |
| `alert-state-changed` | an alert changes state (raised, acknowledged, resolved) |
| `incident-created` | an incident is created |
| `incident-state-changed` | an incident changes state |
| `monitor-status-changed` | a monitor changes status — Operational<->Degraded, Operational<->Offline, Degraded->Offline, with the previous status |

## Inputs

| Name | Required | Default | Notes |
| --- | --- | --- | --- |
| `project_name` | yes | | Shown as `PROJECT: <name>` and used to name the workflows. |
| `teams_webhook_url` | no | `null` | Sensitive. Used when a workflow variable is created; never read back, so changing it later has no effect on an existing variable. `null` leaves a placeholder to set in the console. |
| `dashboard_url` | no | `https://oneuptime.com` | Base of the "open in OneUptime" links. Set it for a self-hosted instance. |
| `enabled` | no | all five | Which notifications to build. |

## Outputs

| Name | Contents | Sensitive |
| --- | --- | :---: |
| `workflow_configs` | Pass to the `oneuptime` module's `workflow_configs`. | No |
| `workflow_variable_contents` | Pass to the `oneuptime` module's `workflow_variable_contents`. Empty when no webhook URL was given. | Yes |

## Use

```hcl
module "teams_notifications" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/oneuptime/modules/workflows-templates/teams-notification?ref=<version>"

  project_name      = "Core"
  dashboard_url     = "https://oneuptime.example.com"
  teams_webhook_url = var.teams_webhook_url
}

module "oneuptime" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/oneuptime?ref=<version>"
  # ...
  workflow_configs           = module.teams_notifications.workflow_configs
  workflow_variable_contents = module.teams_notifications.workflow_variable_contents
}
```

A workflow of the stack's own goes next to them:

```hcl
workflow_configs = merge(module.teams_notifications.workflow_configs, local.custom_workflows)
```

`local.custom_workflows` follows the schema in
[../../workflows/README.md](../../workflows/README.md).
Keys must not clash with the five above.
