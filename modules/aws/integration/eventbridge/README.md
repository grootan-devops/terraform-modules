# AWS EventBridge Module

Scope: `workload`

An EventBridge custom bus (or the default bus) with event-pattern rules and their targets, an optional EventBridge
Scheduler group with schedules, one target role shared by rules and schedules, bus logging, an optional archive, an
optional bus policy and an optional customer managed key. Targets are other modules; pass their ARNs in.

## Architecture & Managed Resources

- `aws_cloudwatch_event_bus.this`: `<application>-<environment>[-<name>]`, on by default (`bus.enabled = false` uses the
  default bus).
- `aws_cloudwatch_event_rule.this`: `<...>-<rule key>`, event pattern only, on the custom bus (the default bus when
  `bus.enabled = false`). Time-based jobs are schedules: AWS recommends EventBridge Scheduler over scheduled rules.
- `aws_cloudwatch_event_target.this`: `lambda` (alias ARN), `sqs`, `step_functions`, `batch` (job queue ARN and job
  definition), `ecs` (cluster ARN and task definition), `kinesis`, `api_destination` and `event_bus` (another bus)
  targets, each with a retry policy and a dead-letter queue. Targets are a separate input keyed by rule, so rules never
  depend on target ARNs and a target's queue or function can refer back to `rule_arns`.
- `aws_scheduler_schedule_group.this` and `aws_scheduler_schedule.this` (`scheduler.enabled = true`): one tagged group
  `<application>-<environment>[-<name>]` and schedules `<...>-<schedule key>` (`cron()`, `rate()` or `at()`, `UTC` by
  default, flexible window off unless `flexible_window_minutes` is set). A schedule's `target` has the same shape as a
  rule target, for `lambda`, `sqs`, `step_functions`, `ecs`, `kinesis` (`kinesis.partition_key`), `batch` (through the
  `aws-sdk:batch:submitJob` universal target) and `event_bus` (`event_bus.detail_type` and `source`; the ARN defaults
  to the module bus). Schedule names come from their own [`core/naming`](../../core/naming) call, so a schedule's
  target or queue may refer back to `rule_arns` without a cycle.
- `module.role` ([`security/iam-role`](../../security/iam-role)): one target role `<...>-events-<region>`, created when
  a rule target needs it or the scheduler is on. Every schedule uses it.
- `module.log_group` ([`observability/log-group`](../../observability/log-group)):
  `/aws/vendedlogs/events/event-bus/<bus>`, with `aws_cloudwatch_log_resource_policy.this` and the
  `aws_cloudwatch_log_delivery*` resources, only while bus logging is on.
- `aws_cloudwatch_event_archive.this`, `aws_cloudwatch_event_bus_policy.this`: optional.
- `module.encryption` ([`core/encryption`](../../core/encryption)): AWS owned key, module key or your key.

A schedules-only call sets `bus = { enabled = false }` and `scheduler = { enabled = true, schedules = {...} }`.

## Security & Compliance Guardrails

- **Least privilege:** the role is trusted by `events.amazonaws.com` and `scheduler.amazonaws.com` with
  `aws:SourceAccount`, and gets only the actions its targets need on their ARNs: `lambda:InvokeFunction` and
  `sqs:SendMessage` (schedules), `states:StartExecution`, `batch:SubmitJob`, `ecs:RunTask` (with `ecs:TagResource` and
  `iam:PassRole` to ECS tasks), `kinesis:PutRecord` (with `kms:GenerateDataKey` through Kinesis),
  `events:InvokeApiDestination` and `events:PutEvents`. Lambda and SQS rule targets need no role: grant the rule in the
  function's `allowed_triggers` and the queue's `allowed_publishers`.
- **Dead-letter queues:** every rule and schedule target needs `dead_letter_queue.arn` unless
  `dead_letter_queue.enabled = false`. For rules the queue must allow `events.amazonaws.com` with the rule ARN; for
  schedules the role gets `sqs:SendMessage` on the queue. Encrypted target or dead-letter queues of schedules
  (`sqs.kms_key_arn`, `dead_letter_queue.kms_key_arn`) add `kms:GenerateDataKey` and `kms:Decrypt` through SQS.
- **Logging:** bus logs at `ERROR` without event detail, 365 days; the log resource policy grants only
  `delivery.logs.amazonaws.com` on the bus log group, and exists only while bus logging is on. It is an account-level
  CloudWatch Logs resource policy (10 per Region).
- **Encryption:** the bus, archive and schedule payloads use the AWS owned key by default; with `kms.create` or
  `kms.key_id` they use that key, and the role gets `kms:Decrypt` on it for schedules. A module key grants
  `events.amazonaws.com` with `aws:SourceAccount`. Logs follow the module key.
- **Bus policy (EventBridge.3):** `policy_statements` default to the bus; an `Allow` for `*` needs a condition.
- **Tags (EventBridge.2):** governance tags on the bus, rules and schedule group (schedules take no tags).

A key passed in `kms.key_id` must allow `events.amazonaws.com` (`kms:Decrypt`, `kms:GenerateDataKey`) and, for logs,
`logs.<region>.amazonaws.com` (encryption context `aws:logs:arn = <log group ARN>`). With schedules, the deploying
principal needs `kms:DescribeKey`, `kms:GenerateDataKey` and `kms:Decrypt` on the key.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "events" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/integration/eventbridge?ref=<version>"

  application = "core"
  environment = "prod"
}
```

### Complete Production Example

```hcl
module "events" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/integration/eventbridge?ref=<version>"

  application = "core"
  environment = "prod"
  kms         = { create = true }
  archive     = { enabled = true, retention_days = 90 }

  rules = {
    orders = { event_pattern = jsonencode({ source = ["core.orders"] }) }
  }

  targets = {
    orders = {
      flow  = { type = "step_functions", arn = module.order_flow.arn, dead_letter_queue = { arn = module.events_dlq.arn } }
      queue = { type = "sqs", arn = module.orders_queue.arn, dead_letter_queue = { arn = module.events_dlq.arn } }
    }
  }

  scheduler = {
    enabled = true
    schedules = {
      report = {
        expression = "cron(0 2 * * ? *)"
        timezone   = "Europe/Dublin"
        target = {
          type              = "lambda"
          arn               = module.report.alias_arn
          dead_letter_queue = { arn = module.events_dlq.arn, kms_key_arn = module.events_dlq.kms_key_arn }
        }
      }
      sync = {
        expression              = "rate(1 hour)"
        flexible_window_minutes = 15
        target = {
          type              = "ecs"
          arn               = module.ecs.arn
          dead_letter_queue = { arn = module.events_dlq.arn, kms_key_arn = module.events_dlq.kms_key_arn }
          ecs = {
            task_definition_arn = module.ecs.task_definition_arns["sync"]
            pass_role_arns      = [module.ecs.task_role_arns["sync"], module.ecs.execution_role_arn]
            subnet_ids          = module.vpc.private_subnet_ids
            security_group_ids  = [module.ecs.security_group_id]
          }
        }
      }
    }
  }
}

module "events_dlq" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/integration/sqs?ref=<version>"

  application       = "core"
  environment       = "prod"
  name              = "events-dlq"
  kms               = { create = true }
  dead_letter_queue = { enabled = false }
  allowed_publishers = {
    orders = { principal = "events.amazonaws.com", source_arn = module.events.rule_arns["orders"] }
  }
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | **Required** | Yes |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `name` | Instance name. | `string` | `null` | No |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `bus` | Custom event bus; disabled: the default bus. | `object({...})` | `{}` | No |
| `kms` | Bus, archive and schedule encryption: {} AWS owned key, create = true module key, key_id your key (ARN or ID). | `object({...})` | `{}` | No |
| `cloudwatch_logs` | Bus logs to CloudWatch (custom bus only): level and log group. | `object({...})` | `{}` | No |
| `archive` | Event archive on the bus. | `object({...})` | `{}` | No |
| `rules` | Event pattern rules by key. | `map(object({...}))` | `{}` | No |
| `targets` | Targets by rule key, then target key. | `map(map(object({...})))` | `{}` | No |
| `scheduler` | EventBridge Scheduler: schedule group and schedules by key. | `object({...})` | `{}` | No |
| `iam_role` | Target role: extend it or bring your own. | `object({...})` | `{}` | No |
| `policy_statements` | Bus policy statements; resources default to the bus. | `list(object({...}))` | `[]` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `bus_arn` | Event bus ARN (the default bus when disabled). | No |
| `bus_name` | Event bus name. | No |
| `rule_arns` | Rule ARNs by key. | No |
| `rule_names` | Rule names by key. | No |
| `rule_bus_names` | Rule bus names by key (EventBusName dimension). | No |
| `schedule_group_name` | Schedule group name; null when the scheduler is off. | No |
| `schedule_group_arn` | Schedule group ARN; null when the scheduler is off. | No |
| `schedule_arns` | Schedule ARNs by key. | No |
| `role_arn` | Target role ARN; null when no target needs one. | No |
| `role_name` | Target role name; null when not created. | No |
| `log_group_name` | Bus log group name; null when bus logging is off. | No |
| `log_group_arn` | Bus log group ARN; null when bus logging is off. | No |
| `kms_key_arn` | Key ARN in use; null for the AWS owned key. | No |
