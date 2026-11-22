# AWS KMS Module

Scope: `workload`

A customer managed key with an alias, an optional key policy extension and optional multi-Region replicas. The other
modules compose it when a caller sets `kms = { create = true }`.

## Architecture & Managed Resources

- `aws_kms_key.this`: the key; `region` places it in another Region (for example us-east-1 for Route 53 DNSSEC).
- `aws_kms_alias.this`: `alias/<application>-<environment>-<name>` plus `additional_aliases`.
- `aws_kms_replica_key.this`, `aws_kms_alias.replica`: one per `replica_regions` entry, via the `region` argument.

## Security & Compliance Guardrails

- **Rotation (KMS.4):** always on for symmetric encryption keys, every 365 days by default.
- **No public key policy (KMS.5):** an `Allow` for principal `*` without a condition is rejected.
- **Deletion window (KMS.3):** 30 days by default, 7-30 allowed.
- **IAM delegation:** the first statement lets the account's IAM policies grant access, so the key cannot lock out its
  owner; `policy_statements` follow it.
- **Lockout check:** `bypass_policy_lockout_safety_check = false`.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "kms" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/kms?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "data"
}
```

### Complete Production Example

```hcl
module "kms" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/kms?ref=<version>"

  application     = "core"
  environment     = "prod"
  name            = "data"
  multi_region    = true
  replica_regions = ["eu-central-1"]
  policy_statements = [{
    sid        = "AllowCloudWatchLogs"
    actions    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    principals = { Service = ["logs.eu-west-1.amazonaws.com"] }
    conditions = [{ test = "ArnLike", variable = "kms:EncryptionContext:aws:logs:arn", values = ["arn:aws:logs:eu-west-1:111122223333:log-group:*"] }]
  }]
  tags = { DataClassification = "confidential" }
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | **Required** | Yes |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `name` | Key name. | `string` | **Required** | Yes |
| `purpose` | Key purpose, appended to the alias. | `string` | `null` | No |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `region` | Key Region. Null: provider Region. | `string` | `null` | No |
| `description` | Key description. | `string` | `null` | No |
| `key_usage` | Key usage. | `string` | `"ENCRYPT_DECRYPT"` | No |
| `key_spec` | Key spec. | `string` | `"SYMMETRIC_DEFAULT"` | No |
| `deletion_window_in_days` | Deletion window (7-30 days). | `number` | `30` | No |
| `rotation_period_in_days` | Rotation period (90-2560 days). | `number` | `365` | No |
| `multi_region` | Multi-Region primary key. | `bool` | `false` | No |
| `replica_regions` | Replica Regions. | `list(string)` | `[]` | No |
| `additional_aliases` | Extra alias names, without alias/. | `list(string)` | `[]` | No |
| `policy_statements` | Extra key policy statements. | `list(object({...}))` | `[]` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `arn` | Key ARN. | No |
| `id` | Key ID. | No |
| `alias_name` | Alias name. | No |
| `alias_arn` | Alias ARN. | No |
| `replica_arns` | Replica ARNs by Region. | No |
| `policy_json` | Key policy JSON. | No |
