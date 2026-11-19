# AWS Step Functions Module

Scope: `workload`

A Step Functions state machine with its execution role, execution log group and optional customer managed key. The
functions it calls are other modules; pass their ARNs in `lambda_function_arns`.

## Architecture & Managed Resources

- `aws_sfn_state_machine.this`: `<application>-<environment>-<name>`, `STANDARD` or `EXPRESS`.
- `module.role` ([`security/iam-role`](../../security/iam-role)): execution role `<...>-exec-<region>`, trusted by
  Step Functions for this state machine in this account only.
- `module.log_group` ([`observability/log-group`](../../observability/log-group)): `/aws/vendedlogs/states/<name>`
  (the `/aws/vendedlogs/` prefix keeps the CloudWatch Logs resource policy small).
- `module.encryption` ([`core/encryption`](../../core/encryption)): AWS owned key, module key or your key.
- `module.alarms` ([`observability/cloudwatch-alarms`](../../observability/cloudwatch-alarms)): built-in alarms, on by
  default; see [Built-in Alarms](#built-in-alarms).

## Security & Compliance Guardrails

- **Logging (StepFunctions.1):** always on; `cloudwatch_logs.level` is `ALL`, `ERROR` (default) or `FATAL`;
  `include_execution_data = false` keeps payloads out of the logs.
- **Least privilege:** `lambda:InvokeFunction` only on `lambda_function_arns` and their versions and aliases; log
  delivery actions on `*` (they have no resource-level permissions); X-Ray actions only when `tracing.enabled`.
- **Encryption:** execution history uses the AWS owned key by default; with a key the role may use it only for this
  state machine's encryption context and for log delivery. Logs follow the module key.
- **Tracing:** X-Ray on by default.

A key passed in `kms.key_id` must allow the execution role (`kms:Decrypt`, `kms:GenerateDataKey`),
`delivery.logs.amazonaws.com` (`kms:Decrypt`) and, for logs, `logs.<region>.amazonaws.com` (encryption context
`aws:logs:arn = <log group ARN>`).

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "order_flow" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/integration/step-functions?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "order-flow"
  definition = jsonencode({
    StartAt = "Done"
    States  = { Done = { Type = "Pass", End = true } }
  })
}
```

### Complete Production Example

```hcl
module "order_flow" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/integration/step-functions?ref=<version>"

  application          = "core"
  environment          = "prod"
  name                 = "order-flow"
  kms                  = { create = true }
  lambda_function_arns = [module.validate.arn, module.charge.arn]
  cloudwatch_logs      = { level = "ALL" }

  definition = jsonencode({
    StartAt = "Validate"
    States = {
      Validate = { Type = "Task", Resource = "arn:aws:states:::lambda:invoke", Parameters = { FunctionName = module.validate.alias_arn, "Payload.$" = "$" }, Next = "Charge" }
      Charge   = { Type = "Task", Resource = "arn:aws:states:::lambda:invoke", Parameters = { FunctionName = module.charge.alias_arn, "Payload.$" = "$" }, End = true }
    }
  })

  iam_role = {
    policy_statements = [{ sid = "PublishEvents", actions = ["events:PutEvents"], resources = [module.events.bus_arn] }]
  }
}
```

### Built-in Alarms

The `step_functions` preset of [`observability/cloudwatch-alarms`](../../observability/cloudwatch-alarms) is on by
default, on the state machine ARN: `sfn-state-machine-executions-failed` and `sfn-state-machine-executions-timed-out`
(critical), `sfn-state-machine-executions-aborted` and `sfn-state-machine-execution-throttled` (warning), each on a
single occurrence in a minute. None is opt-in. Without `topic_arns` the alarms have no actions;
`alarms = { enabled = false }` creates none.

```hcl
module "alarm_routing" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/observability/alarm-routing?ref=<version>"

  environment = "prod"
}

module "order_flow" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/integration/step-functions?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "order-flow"
  definition  = jsonencode({ StartAt = "Done", States = { Done = { Type = "Pass", End = true } } })

  alarms = {
    topic_arns = module.alarm_routing.topic_arns["eu-west-1"]
    overrides = {
      executions_failed   = { threshold = 2 }
      execution_throttled = { enabled = false }
    }
  }
}
```

`overrides` takes the preset's alarm keys and fields (`enabled`, `threshold`, `evaluation_periods`,
`datapoints_to_alarm`, `period`, `severity`); a field left out keeps the preset default.

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | **Required** | Yes |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `name` | State machine name. | `string` | **Required** | Yes |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `definition` | Amazon States Language definition (JSON). | `string` | **Required** | Yes |
| `type` | STANDARD or EXPRESS. | `string` | `"STANDARD"` | No |
| `lambda_function_arns` | Function ARNs the state machine may invoke (with versions and aliases). | `list(string)` | `[]` | No |
| `kms` | Encryption: {} AWS owned key, create = true module key, key_id your key (ARN or ID). | `object({...})` | `{}` | No |
| `iam_role` | Execution role: extend it or bring your own. | `object({...})` | `{}` | No |
| `cloudwatch_logs` | CloudWatch log group and execution log level. | `object({...})` | `{}` | No |
| `tracing` | X-Ray tracing. | `object({...})` | `{}` | No |
| `alarms` | Built-in CloudWatch alarms: switch, topics by severity, per-alarm overrides. | `object({...})` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `arn` | State machine ARN. | No |
| `name` | State machine name. | No |
| `role_arn` | Execution role ARN. | No |
| `role_name` | Execution role name; null for a role brought by the caller. | No |
| `log_group_name` | Log group name. | No |
| `log_group_arn` | Log group ARN. | No |
| `kms_key_arn` | Key ARN in use; null for the AWS owned key. | No |
| `alarm_arns` | Alarm ARN by key. | No |
| `alarm_names` | Alarm name by key. | No |
