# AWS EventBridge Module

The `eventbridge` module provisions custom Amazon EventBridge event buses with KMS encryption, event routing rules, dead-letter queue (DLQ) integration, and cross-service invocation targets.

### Architecture & Managed Resources
- `aws_cloudwatch_event_bus.this`: Primary custom event bus.
- `aws_cloudwatch_event_rule.this`: Pattern-matching and scheduled event rules.
- `aws_cloudwatch_event_target.this`: Invocation targets (Lambda, SQS, Batch, Step Functions).
- `aws_cloudwatch_event_bus_policy.this`: IAM bus permission policies.

### Security & Compliance Guardrails
- **Mandatory KMS CMK**: Custom event bus encryption at rest is strictly required (`kms_key_arn`).
- **Dead-Letter Resiliency**: Supports dead-letter queue routing for unprocessed events.

---

## Requirements & Providers

| Requirement | Version |
|---|---|
| `terraform` | `>= 1.5.0` |
| `aws` | `>= 6.0.0, < 7.0.0` |

---

## Usage Examples

### Minimal Working Example
```hcl
module "eventbridge" {
  source = "git::https://github.com/organization/terraform-modules.git//modules/aws/integration/eventbridge"

  application = "core"
  environment = "prod"
  name        = "bus"
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
}
```

### Complete Production Example
```hcl
module "eventbridge" {
  source = "git::https://github.com/organization/terraform-modules.git//modules/aws/integration/eventbridge"

  application = "orders"
  environment = "prod"
  name        = "events"
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
  create_bus  = true

  rules = {
    order_created = {
      description   = "Route newly created order events"
      event_pattern = jsonencode({
        "source"      = ["app.orders"]
        "detail-type" = ["OrderCreated"]
      })
    }
  }

  targets = {
    dispatch_queue = {
      rule_name       = "order_created"
      arn             = "arn:aws:sqs:us-west-2:123456789012:order-queue"
      dead_letter_arn = "arn:aws:sqs:us-west-2:123456789012:order-dlq"
      retry_policy = {
        maximum_event_age_in_seconds = 86400
        maximum_retry_attempts       = 5
      }
    }
  }

  tags = {
    Messaging = "EnterpriseBus"
  }
}
```

---

## Inputs Specification

| Name | Description | Type | Default | Required |
|---|---|---|---|:---:|
| `application` | The name of the application. | `string` | **Required** | Yes |
| `environment` | Deployment environment name (e.g. dev, staging, prod). | `string` | **Required** | Yes |
| `name` | The name suffix for EventBridge resources. | `string` | `""` | No |
| `create_bus` | Controls whether to create a custom event bus. If false, the default bus or an existing bus name passed via rules will be used. | `bool` | `true` | No |
| `bus_name` | The name of the event bus to create (required if create_bus is true). | `string` | `""` | No |
| `kms_key_arn` | The KMS Key ARN used to encrypt the EventBridge bus. Strictly required. | `string` | **Required** | Yes |
| `bus_tags` | A map of tags to assign to the event bus. | `map(string)` | `{}` | No |
| `rules` | Map of EventBridge rules to create. The key is the rule name. | `map(object({...}))` | `{}` | No |
| `targets` | Map of targets to associate with the EventBridge rules. | `map(object({...}))` | `{}` | No |
| `bus_policy` | The JSON policy document to apply to the event bus. | `string` | `null` | No |
| `tags` | Common tags to apply to all resources. | `map(string)` | `{}` | No |
| `cloudwatch_logs` | CloudWatch logs configuration for EventBridge. | `object({...})` | `null` | No |


---

## Outputs Specification

| Name | Description | Sensitive |
|---|---|:---:|
| `event_rules` | Map of created EventBridge rules containing their ARNs. | No |
| `bus_arn` | The ARN of the EventBridge bus. | No |
| `bus_name` | The name of the EventBridge bus. | No |

