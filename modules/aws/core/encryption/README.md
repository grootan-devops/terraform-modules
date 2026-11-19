# Encryption Helper

Scope: `helper`

Turns the standard `kms` input into the key ARN a module uses: the AWS managed key (null), a key it creates through
[`security/kms`](../../security/kms), or the caller's key.

## Architecture & Managed Resources

- `module.key` (`security/kms`) when `kms.create = true`.

## Security & Compliance Guardrails

- Never plaintext: no input means the service's AWS managed key.
- A created key grants only the calling module's `service_statements`, then the caller's `policy_statements`.
- `kms.key_id` must be a key ARN or key ID; a bare ID becomes the ARN in the provider's account and Region.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "encryption" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/core/encryption?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "orders"
  purpose     = "sqs"
}
```

### Complete Production Example

```hcl
module "encryption" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/core/encryption?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "orders"
  purpose     = "lambda"
  kms         = { create = true }
  service_statements = [{
    sid        = "AllowCloudWatchLogs"
    actions    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    principals = { Service = ["logs.eu-west-1.amazonaws.com"] }
    conditions = [{ test = "ArnLike", variable = "kms:EncryptionContext:aws:logs:arn", values = ["arn:aws:logs:eu-west-1:111122223333:log-group:/aws/lambda/core-prod-orders"] }]
  }]
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | **Required** | Yes |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `name` | Instance name. | `string` | `null` | No |
| `purpose` | Service the key is for (rds, sqs, lambda...); part of the key alias. | `string` | **Required** | Yes |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `region` | Key Region. Null: provider Region. | `string` | `null` | No |
| `kms` | Encryption: {} AWS managed key, create = true module key, key_id your key (ARN or ID). | `object({...})` | `{}` | No |
| `service_statements` | Key policy statements the calling module's services need (used with create = true). | `list(object({...}))` | `[]` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `key_arn` | Key ARN in use; null for the AWS managed key. | No |
| `created` | Whether the module created the key. | No |
