# AWS Cost Guardrails Module

Scope: `account`

Cost controls for one account, applied once per account: AWS Budgets with actual and forecasted alerts, Cost Anomaly
Detection (the AWS services monitor, optional customer managed monitors and alert subscriptions) and optional
activation of user-defined cost allocation tags. Alerts go to one SNS topic (for example from
[`alarm-routing`](../../observability/alarm-routing)) and to email addresses.

## Architecture & Managed Resources

- `aws_budgets_budget.this["<key>"]`: `<application>-<environment>-<key>`, a `MONTHLY` `COST` budget in `USD` by
  default. `filter` becomes `filter_expression`: services, linked accounts and one tag expression per tag key, joined
  with AND; `metric` (default `UnblendedCost`) applies only to filtered budgets because the provider pairs `metrics`
  with `filter_expression`. Default notifications: actual > 80 %, actual > 100 %, forecasted > 100 %.
- `aws_ce_anomaly_monitor.services`: the AWS managed `SERVICE` monitor, `<application>-<environment>-services`.
- `aws_ce_anomaly_monitor.custom["<key>"]`: customer managed monitors, `<application>-<environment>-<key>`, on linked
  accounts, tag values or one cost category value.
- `aws_ce_anomaly_subscription.this["immediate"]` (SNS) and `["daily"]` (email):
  `<application>-<environment>-anomalies-<frequency>`, on every monitor, threshold on the anomaly's total impact.
- `aws_ce_cost_allocation_tag.this["<key>"]`: tag keys set to `Active`.
- `module.naming` ([`core/naming`](../../core/naming)): names and governance tags.

Budgets and Cost Explorer are global to the account (no Region), so there is no `regions` input. Names use
`uniqueness = "region"`, which adds no suffix: the module runs once per account and budget names only need to be
unique in the account, so `<application>-<environment>-<key>` is enough, and two environments sharing an account differ
by `environment`. `account` would append the provider Region to a name that has none and rename the resources when the
provider Region changes.

## Security & Compliance Guardrails

- **Subscribers required:** with budgets or anomaly detection on, `notifications` needs an SNS topic or emails (at
  most 10, the AWS limit per budget alert and per subscription). Resources are gated on `sns.enabled` and the number
  of emails, never on whether the topic ARN is known.
- **SNS topic:** AWS Budgets needs a topic in this account (a precondition checks it). The topic policy must allow
  `budgets.amazonaws.com` and `costalerts.amazonaws.com`, and an encrypted topic's key must allow them
  `kms:GenerateDataKey*` and `kms:Decrypt`: list both in `alarm-routing`'s `additional_publisher_service_principals`.
- **Anomaly alerts:** AWS sends `IMMEDIATE` alerts only to SNS and `DAILY` summaries only to email, so the module
  creates one subscription per channel. The threshold uses `ANOMALY_TOTAL_IMPACT_ABSOLUTE` and/or
  `ANOMALY_TOTAL_IMPACT_PERCENTAGE` with `GREATER_THAN_OR_EQUAL`, joined with OR; the default is an impact of 100 USD,
  and setting `threshold` replaces it.
- **One AWS services monitor per account:** accounts that enabled Cost Explorer after 27 March 2023 already have one
  (with a daily email subscription). Use it with `service_monitor = { create = false, arn = "<monitor ARN>" }`, or
  import it (it is renamed and tagged in place):

  ```hcl
  import {
    to = module.cost_guardrails.aws_ce_anomaly_monitor.services[0]
    id = "arn:aws:ce::123456789012:anomalymonitor/abcdef12-1234-4ea0-84cc-918a97d736ef"
  }
  ```

- **Management account only:** customer managed monitors and cost allocation tag activation work only in the
  management account of an organization or a standalone account. Up to 10 linked accounts or tag values per custom
  monitor; one cost category value.
- **Cost allocation tags:** a key appears in billing data up to 24 hours after a resource carries it; activating a key
  that is not there yet fails the apply. Activation takes up to 24 hours; removing a key sets it `Inactive`. Budget
  and monitor tag filters only see activated keys.
- **Forecasts and auto-adjust:** forecasted alerts need about five weeks of cost data. `auto_adjust` sets the amount to
  the average of the last `lookback_periods` periods (at most 60 daily, 12 monthly, 4 quarterly, 1 annual) and
  requires `amount = null`.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "cost_guardrails" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/governance/cost-guardrails?ref=<version>"

  environment   = "prod"
  notifications = { emails = ["finops@example.com"] }
  budgets       = { account = { amount = 5000 } }
}
```

### Complete Production Example

Management account, alerts through `alarm-routing`:

```hcl
module "alarm_routing" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/observability/alarm-routing?ref=<version>"

  environment                             = "prod"
  regions                                 = ["us-east-1"]
  additional_publisher_service_principals = ["budgets.amazonaws.com", "costalerts.amazonaws.com"]
}

module "cost_guardrails" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/governance/cost-guardrails?ref=<version>"

  environment = "prod"
  notifications = {
    sns    = { enabled = true, topic_arn = module.alarm_routing.topic_arns["us-east-1"]["warning"] }
    emails = ["finops@example.com"]
  }

  budgets = {
    account = { amount = 20000 }
    core    = { amount = 4000, filter = { tags = { Application = ["core"] } } }
    data    = { amount = 2500, filter = { services = ["Amazon Relational Database Service"], linked_accounts = ["111122223333"] } }
    trend   = { auto_adjust = { enabled = true, lookback_periods = 6 }, notifications = [{ type = "FORECASTED", threshold = 110 }] }
  }

  anomaly_detection = {
    service_monitor = { create = false, arn = "arn:aws:ce::123456789012:anomalymonitor/abcdef12-1234-4ea0-84cc-918a97d736ef" }
    custom_monitors = {
      core     = { tag = { key = "Application", values = ["core"] } }
      workload = { linked_accounts = ["111122223333", "444455556666"] }
    }
    threshold = { absolute = 200, percentage = 25 }
  }

  cost_allocation_tags = { enabled = true, keys = ["Application", "Environment", "ManagedBy", "CostCenter"] }
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | `"platform"` | No |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `notifications` | Subscribers for budget and anomaly alerts. | `object({...})` | `{}` | No |
| `budgets` | Budgets by key. | `map(object({...}))` | `{}` | No |
| `anomaly_detection` | Cost Anomaly Detection monitors and alert subscriptions. | `object({...})` | `{}` | No |
| `cost_allocation_tags` | User-defined cost allocation tags to activate. | `object({...})` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `budget_names` | Budget name by key. | No |
| `budget_arns` | Budget ARN by key. | No |
| `anomaly_monitor_arns` | Anomaly monitor ARN by key; services is the AWS services monitor. | No |
| `anomaly_subscription_arns` | Anomaly subscription ARN by frequency (immediate, daily). | No |
| `cost_allocation_tag_keys` | Activated cost allocation tag keys. | No |
