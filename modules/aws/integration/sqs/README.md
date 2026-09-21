# AWS SQS Queue Module

The `sqs` module manages Amazon Simple Queue Service (SQS) standard and FIFO queues with Customer Managed KMS Key encryption, dead-letter queue (DLQ) redrive automation, and EventBridge publishing policies.

## Architecture & Managed Resources

- `aws_sqs_queue.this`: Primary SQS queue.
- `aws_sqs_queue.dlq`: Automatically provisioned Dead Letter Queue.
- `aws_sqs_queue_redrive_policy.this`: Attaches redrive threshold policy.
- `aws_sqs_queue_redrive_allow_policy.this`: Authorizes primary queue to send to DLQ.
- `aws_sqs_queue_policy.this`: Access policy granting publish permissions to EventBridge.

### Security & Compliance Guardrails

- **Mandatory KMS CMK**: Enforces encryption with `kms_master_key_id = var.kms_key_arn`.
- **SSE-SQS Prohibited**: `sqs_managed_sse_enabled = false` ensures AWS-managed default encryption cannot be substituted.
- **Automated DLQ**: Defaults to `create_dlq = true` with a 14-day retention window on dead letters.

---

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.5.0` |
| `aws` | `>= 6.0.0, < 7.0.0` |

---

## Usage Examples

### Minimal Working Example

```hcl
module "sqs" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/integration/sqs?ref=1.0.0"

  application = "core"
  environment = "prod"
  name        = "events"
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
}
```

### Complete Production Example

```hcl
module "sqs" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/integration/sqs?ref=1.0.0"

  application = "notifications"
  environment = "prod"
  name        = "dispatch-queue"

  kms_key_arn                       = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
  kms_data_key_reuse_period_seconds = 300
  visibility_timeout_seconds        = 60
  message_retention_seconds         = 345600 # 4 days
  delay_seconds                     = 0
  receive_wait_time_seconds         = 20     # Long polling enabled

  create_dlq        = true
  max_receive_count = 5
  allow_eventbridge = true

  tags = {
    Service = "MessageBroker"
  }
}
```

---

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | :---: |
| `application` | The name of the application. | `string` | **Required** | Yes |
| `environment` | Deployment environment name (e.g. dev, staging, prod). | `string` | **Required** | Yes |
| `name` | The name suffix for SQS resources. | `string` | **Required** | Yes |
| `visibility_timeout_seconds` | The visibility timeout for the queue in seconds. | `number` | `30` | No |
| `message_retention_seconds` | The number of seconds Amazon SQS retains a message. | `number` | `345600 # 4 days` | No |
| `max_message_size` | The limit of how many bytes a message can contain before Amazon SQS rejects it. | `number` | `262144 # 256 KiB` | No |
| `delay_seconds` | The time in seconds that the delivery of all messages in the queue will be delayed. | `number` | `0` | No |
| `receive_wait_time_seconds` | The time for which a ReceiveMessage call will wait for a message to arrive before returning. | `number` | `0` | No |
| `policy` | The JSON policy document to apply to the queue. | `string` | `null` | No |
| `allow_eventbridge` | Whether to allow EventBridge to send messages to this SQS queue. | `bool` | `false` | No |
| `redrive_policy` | The JSON policy to set up the Dead Letter Queue redrive. | `string` | `null` | No |
| `redrive_allow_policy` | The JSON policy to set up the Dead Letter Queue redrive allow. | `string` | `null` | No |
| `fifo_queue` | Boolean designating a FIFO queue. | `bool` | `false` | No |
| `content_based_deduplication` | Enables content-based deduplication for FIFO queues. | `bool` | `false` | No |
| `kms_key_arn` | The ARN of a KMS customer managed key (CMK) for Amazon SQS encryption at rest. | `string` | **Required** | Yes |
| `kms_data_key_reuse_period_seconds` | The length of time, in seconds, for which Amazon SQS can reuse a data key to encrypt or decrypt messages before calling AWS KMS again. | `number` | `300` | No |
| `tags` | A map of tags to assign to the SQS queue. | `map(string)` | `{}` | No |
| `create_dlq` | Controls whether to create a Dead Letter Queue (DLQ) for this SQS queue. | `bool` | `true` | No |
| `max_receive_count` | The number of times a message is delivered to the source queue before being moved to the dead-letter queue. | `number` | `3` | No |

---

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | :---: |
| `queue_arn` | The ARN of the SQS queue. | No |
| `queue_url` | The URL for the created Amazon SQS queue. | No |
