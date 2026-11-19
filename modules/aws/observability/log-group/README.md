# AWS CloudWatch Log Group Module

Scope: `workload`

A CloudWatch Logs log group with retention, encryption, class and deletion protection. Every module that writes logs
composes it.

## Architecture & Managed Resources

- `aws_cloudwatch_log_group.this`: the exact `log_group_name` the writing service needs, in `region` if set.

## Security & Compliance Guardrails

- **Retention (CloudWatch.16, PCI DSS 10.5.1):** 365 days by default.
- **Encryption:** service encryption by default; `kms_key_arn` for a customer managed key.
- **Deletion protection:** on by default.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "logs" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/observability/log-group?ref=<version>"

  application    = "core"
  environment    = "prod"
  log_group_name = "/app/core-prod/audit"
}
```

### Complete Production Example

```hcl
module "logs" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/observability/log-group?ref=<version>"

  application       = "core"
  environment       = "prod"
  name              = "audit"
  log_group_name    = "/app/core-prod/audit"
  retention_in_days = 731
  kms_key_arn       = "arn:aws:kms:eu-west-1:111122223333:key/12345678-1234-1234-1234-123456789012"
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | **Required** | Yes |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `name` | Instance name (tags). | `string` | `null` | No |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `log_group_name` | Log group name, as the writing service requires it. | `string` | **Required** | Yes |
| `region` | Log group Region. Null: provider Region. | `string` | `null` | No |
| `retention_in_days` | Retention in days. | `number` | `365` | No |
| `kms_key_arn` | KMS key ARN. Null: CloudWatch Logs service encryption. | `string` | `null` | No |
| `log_group_class` | STANDARD, INFREQUENT_ACCESS or DELIVERY. | `string` | `"STANDARD"` | No |
| `deletion_protection_enabled` | Block deletion of the log group. | `bool` | `true` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `name` | Log group name. | No |
| `arn` | Log group ARN. | No |
| `retention_in_days` | Retention in days. | No |
| `kms_key_arn` | Key ARN; null for service encryption. | No |
