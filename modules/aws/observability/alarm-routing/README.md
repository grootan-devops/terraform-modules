# AWS Alarm Routing Module

Scope: `account`

The notification side of CloudWatch alarms for one account: one KMS-encrypted SNS topic per severity (`critical`,
`warning`, `info`) in every Region of `regions`, a topic policy that lets only this account's alarms (and named AWS
services) publish, and email and HTTPS subscriptions. Its `topic_arns` output feeds `notifications.topic_arns` of
[`cloudwatch-alarms`](../cloudwatch-alarms).

## Architecture & Managed Resources

- `aws_sns_topic.this["<region>/<severity>"]`: `<application>-<environment>-<severity>`, SSE-KMS, `SignatureVersion` 2.
- `aws_sns_topic_policy.this`: CloudWatch publish from this account's alarms in the topic Region, optional extra
  publishers (AWS Budgets and Cost Anomaly Detection with their own statements), deny without TLS, deny `http`
  subscriptions.
- `aws_sns_topic_subscription.email` / `.https`: per address or endpoint, in every Region, with the optional HTTPS
  retry policy and per-Region SQS dead-letter queue.
- `module.encryption` ([`core/encryption`](../../core/encryption)): one key per Region (`alias/<application>-<environment>-sns`).

Every alarm routes to the topic in its own Region; CloudFront metrics live in `us-east-1`, so list it in `regions` when
CloudFront or CLOUDFRONT-scope WAF alarms route here.

## Security & Compliance Guardrails

- **Customer managed key (SNS.1):** `kms` defaults to `create = true`; CloudWatch alarms cannot publish to topics
  encrypted with `aws/sns`, so the AWS managed key is rejected.
- **Key policy:** grants `cloudwatch.amazonaws.com` (and extra publishers) `kms:Decrypt` and `kms:GenerateDataKey*`
  with `aws:SourceAccount`; EventBridge gets the statement without conditions because SNS does not support them for it.
- **Cost alerts:** `budgets.amazonaws.com` and `costalerts.amazonaws.com` in `additional_publisher_service_principals`
  get topic and key statements with `aws:SourceAccount` and `aws:SourceArn` (`arn:<partition>:budgets::<account>:*`,
  `arn:<partition>:ce::<account>:*`), so [`cost-guardrails`](../../governance/cost-guardrails) can publish budget and
  anomaly alerts.
- **No public access (SNS.4):** no Allow for principal `*`; publishers are service principals of this account.
- **In transit:** TLS required to publish, `http` subscriptions denied, `https_subscriptions` URLs must be `https://`.
- **Webhook secrets:** `https_subscriptions` is sensitive and URLs are never output; state still holds them in clear text.
- **Tags (SNS.3):** governance tags on every topic.

A key passed in `kms.key_id` must allow `cloudwatch.amazonaws.com` (and every extra publisher) `kms:Decrypt` and
`kms:GenerateDataKey*`, with the conditions above for AWS Budgets and Cost Anomaly Detection. With several Regions
pass a multi-Region key ID (`mrk-...`); it resolves to the replica in each Region.

Email and HTTPS subscriptions stay pending until confirmed (SNS deletes them after 48 hours); Terraform cannot confirm
them. A OneUptime Incoming Request monitor (`https://oneuptime.com/heartbeat/<secret key>`) does not confirm on its
own: confirm it from the monitor summary after the apply, and keep `endpoint_auto_confirms = false`.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "alarm_routing" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/observability/alarm-routing?ref=<version>"

  environment         = "prod"
  email_subscriptions = { critical = ["oncall@example.com"] }
}
```

### Complete Production Example

```hcl
module "alarm_routing" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/observability/alarm-routing?ref=<version>"

  environment = "prod"
  regions     = ["eu-west-1", "us-east-1"]
  kms         = { create = true }

  email_subscriptions = {
    critical = ["oncall@example.com"]
    warning  = ["platform-team@example.com"]
  }
  https_subscriptions   = { critical = [{ url = var.oneuptime_critical_url, raw_message_delivery = true }] }
  https_delivery_policy = { enabled = true, header_content_type = "application/json" }
  dead_letter_queue_arns = {
    "eu-west-1" = module.alerts_dlq_eu.arn
    "us-east-1" = module.alerts_dlq_us.arn
  }
  additional_publisher_service_principals = ["backup.amazonaws.com", "budgets.amazonaws.com", "costalerts.amazonaws.com"]
}

module "alarms" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/observability/cloudwatch-alarms?ref=<version>"

  application   = "core"
  environment   = "prod"
  notifications = { enabled = true, topic_arns = module.alarm_routing.topic_arns }
}

module "cost_guardrails" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/governance/cost-guardrails?ref=<version>"

  environment   = "prod"
  notifications = { sns = { enabled = true, topic_arn = module.alarm_routing.topic_arns["us-east-1"]["warning"] } }
  budgets       = { account = { amount = 5000 } }
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | `"platform"` | No |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `regions` | Regions with topics. Empty: provider Region. | `list(string)` | `[]` | No |
| `severities` | Severity levels; one topic each per Region. | `list(string)` | `["critical", "warning", "info"]` | No |
| `kms` | Encryption: create = true module key (default) or key_id your key (ARN or ID). | `object({...})` | `{ create = true }` | No |
| `email_subscriptions` | Email addresses by severity. | `map(list(string))` | `{}` | No |
| `https_subscriptions` | HTTPS endpoints by severity. | `map(list(object({...})))` | `{}` | No |
| `https_delivery_policy` | Retry policy for HTTPS subscriptions. | `object({...})` | `{}` | No |
| `dead_letter_queue_arns` | SQS dead-letter queue ARN by Region. | `map(string)` | `{}` | No |
| `additional_publisher_service_principals` | Extra service principals that may publish. | `list(string)` | `[]` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `topic_arns` | Topic ARN by Region, then severity. | No |
| `email_subscription_arns` | Email subscription ARN by region/severity/address. | No |
| `https_subscription_arns` | HTTPS subscription ARN by region/severity/index. | No |
| `kms_key_arns` | Topic key ARN by Region. | No |
