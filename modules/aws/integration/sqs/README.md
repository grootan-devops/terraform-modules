# AWS SQS Module

Scope: `workload`

An SQS queue with its dead-letter queue, redrive, TLS-only queue policies, publisher grants for EventBridge, SNS and S3,
and an optional customer managed key. Producers and consumers are other modules; give them the queue ARN.

## Architecture & Managed Resources

- `aws_sqs_queue.this`: `<application>-<environment>-<name>` (`.fifo` appended for FIFO queues).
- `aws_sqs_queue.dlq`: `<...>-dlq` (`<...>-dlq.fifo`), 14 days retention, on by default.
- `aws_sqs_queue_redrive_policy.this`, `aws_sqs_queue_redrive_allow_policy.this`: the queue redrives to its DLQ after
  `max_receive_count` receives; only this queue may use the DLQ.
- `aws_sqs_queue_policy.this`, `aws_sqs_queue_policy.dlq`: rendered by
  [`core/policy-document`](../../core/policy-document).
- `module.encryption` ([`core/encryption`](../../core/encryption)): SSE-SQS, module key or your key.
- `module.alarms` ([`observability/cloudwatch-alarms`](../../observability/cloudwatch-alarms)): built-in alarms, on by
  default; see [Built-in Alarms](#built-in-alarms).

## Security & Compliance Guardrails

- **Encryption at rest (SQS.1):** SSE-SQS by default (`sqs_managed_sse_enabled = true`); `kms` switches both queues to
  a KMS key, never both settings at once.
- **TLS only:** both policies start with `DenyInsecureTransport` (`aws:SecureTransport = false`).
- **No public access (SQS.3):** `allowed_publishers` grants only `sqs:SendMessage` to `events`, `sns` or `s3`, each
  limited to one `aws:SourceArn`; `policy_statements` come after the guard and default to the queue as resource.
- **Dead-letter queue:** on by default so poison messages are kept, not retried forever. When an EventBridge rule
  target or an SNS subscription uses it as its own dead-letter queue, list that rule or topic in
  `dead_letter_queue.allowed_publishers`; otherwise its policy admits nothing and failed events are dropped.
- **Tags (SQS.2):** governance tags on both queues.

A key created with `kms.create` grants `kms:GenerateDataKey` and `kms:Decrypt` to each publisher service, limited by
`aws:SourceAccount` (the queue policy keeps the `aws:SourceArn` limit). A key passed in `kms.key_id` must grant the same
to every publisher service.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "orders_queue" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/integration/sqs?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "orders"
}
```

### Complete Production Example

```hcl
module "orders_queue" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/integration/sqs?ref=<version>"

  application                = "core"
  environment                = "prod"
  name                       = "orders"
  visibility_timeout_seconds = 180
  receive_wait_time_seconds  = 20
  kms                        = { create = true }
  dead_letter_queue          = { max_receive_count = 5 }

  allowed_publishers = {
    nightly = { principal = "events.amazonaws.com", source_arn = module.events.rule_arns["nightly"] }
    orders  = { principal = "sns.amazonaws.com", source_arn = module.orders_topic.arn }
  }
}

module "worker" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/compute/lambda?ref=<version>"

  application   = "core"
  environment   = "prod"
  name          = "orders-worker"
  timeout       = 30
  event_sources = { orders = { type = "sqs", arn = module.orders_queue.arn, batch_size = 10 } }
}
```

### Built-in Alarms

The `sqs_queues` preset of [`observability/cloudwatch-alarms`](../../observability/cloudwatch-alarms) is on by default:
`sqs-queue-dlq-messages-visible` (critical, any message in the dead-letter queue) while `dead_letter_queue.enabled`.
`sqs-queue-age-of-oldest-message` is on once `age_of_oldest_message.threshold` is set (seconds); `messages_visible` is
opt-in and needs a threshold. Without `topic_arns` the alarms have no actions; `alarms = { enabled = false }` creates
none.

```hcl
module "alarm_routing" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/observability/alarm-routing?ref=<version>"

  environment = "prod"
}

module "sqs" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/integration/sqs?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "orders"

  alarms = {
    topic_arns = module.alarm_routing.topic_arns["eu-west-1"]
    overrides = {
      age_of_oldest_message = { threshold = 900 }
      dlq_messages_visible  = { enabled = false }
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
| `name` | Queue name. | `string` | **Required** | Yes |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `fifo` | FIFO queues: deduplication and high throughput. | `object({...})` | `{}` | No |
| `visibility_timeout_seconds` | Visibility timeout in seconds (0-43200). | `number` | `30` | No |
| `message_retention_seconds` | Message retention in seconds (60-1209600). | `number` | `345600` | No |
| `max_message_size` | Maximum message size in bytes (1024-1048576). | `number` | `262144` | No |
| `delay_seconds` | Delivery delay in seconds (0-900). | `number` | `0` | No |
| `receive_wait_time_seconds` | Long polling wait in seconds (0-20). | `number` | `0` | No |
| `kms` | Encryption: {} SSE-SQS, create = true module key, key_id your key (ARN or ID). | `object({...})` | `{}` | No |
| `kms_data_key_reuse_period_seconds` | KMS data key reuse in seconds (60-86400). | `number` | `300` | No |
| `dead_letter_queue` | Dead-letter queue and redrive. | `object({...})` | `{}` | No |
| `allowed_publishers` | Services allowed to send, by key: principal and source ARN. | `map(object({...}))` | `{}` | No |
| `policy_statements` | Extra queue policy statements; resources default to the queue. | `list(object({...}))` | `[]` | No |
| `alarms` | Built-in CloudWatch alarms: switch, topics by severity, per-alarm overrides. | `object({...})` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `id` | Queue URL. | No |
| `arn` | Queue ARN. | No |
| `name` | Queue name. | No |
| `url` | Queue URL. | No |
| `dlq_arn` | Dead-letter queue ARN; null when disabled. | No |
| `dlq_url` | Dead-letter queue URL; null when disabled. | No |
| `dlq_name` | Dead-letter queue name; null when disabled. | No |
| `kms_key_arn` | Key ARN in use; null for SSE-SQS. | No |
| `alarm_arns` | Alarm ARN by key. | No |
| `alarm_names` | Alarm name by key. | No |
