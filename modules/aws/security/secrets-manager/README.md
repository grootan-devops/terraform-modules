# AWS Secrets Manager Module

Scope: `workload`

A Secrets Manager secret with an optional write-only value, Lambda rotation, a resource policy and replicas in other
Regions. Rotation functions and the roles that read the secret are other modules; pass their ARNs in.

## Architecture & Managed Resources

- `aws_secretsmanager_secret.this`: `<application>-<environment>-<name>`, 30-day recovery window, replicas from
  `replica_regions`.
- `aws_secretsmanager_secret_version.this`: when `secret_string_wo_version` is set.
- `aws_secretsmanager_secret_rotation.this`: when `rotation.enabled`.
- `aws_secretsmanager_secret_policy.this` via `module.policy` ([`core/policy-document`](../../core/policy-document)):
  when `policy_statements` is set.
- `module.encryption` ([`core/encryption`](../../core/encryption)): `aws/secretsmanager`, module key or your key.
- `module.key` ([`security/kms`](../kms)): with `kms.create` and replicas, a multi-Region module key replicated to every
  replica Region.

## Security & Compliance Guardrails

- **Value out of state:** only `secret_string_wo` (ephemeral, write-only) with `secret_string_wo_version`; increment
  the version to write a new value. No plain `secret_string` or `secret_binary` input.
- **Encryption:** `aws/secretsmanager` by default; replicas use the module key's replica, a `kms_key_arn` per Region,
  or `aws/secretsmanager` there. With `kms.key_id` every replica needs its own `kms_key_arn`.
- **Rotation (SecretsManager.1, SecretsManager.4):** every 30 days by default, at most 90, or a
  `schedule_expression`. The function needs an invoke permission for `secretsmanager.amazonaws.com`
  ([`compute/lambda`](../../compute/lambda) `allowed_triggers`) and access to the secret and its key.
- **Resource policy:** `block_public_policy` is always on; statements without `resources` apply to the secret, and an
  `Allow` for principal `*` needs a condition.
- **Recovery:** deletion waits 30 days by default (7-30); `0` deletes at once and is meant for disposable secrets.
- **Tags (SecretsManager.5):** caller tags first, governance tags last.

SecretsManager.2 and SecretsManager.3 (rotation succeeds, unused secrets removed) are runtime checks.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "db_secret" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/secrets-manager?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "db"
}
```

### Complete Production Example

```hcl
module "db_secret" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/secrets-manager?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "db"
  kms         = { create = true }

  secret_string_wo         = ephemeral.random_password.db.result
  secret_string_wo_version = 1

  rotation        = { enabled = true, lambda_arn = module.rotation_fn.alias_arn }
  replica_regions = { eu-central-1 = {} }

  policy_statements = [{
    sid        = "ReadFromApi"
    actions    = ["secretsmanager:GetSecretValue"]
    principals = { AWS = [module.api.role_arn] }
  }]
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | **Required** | Yes |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `name` | Secret name. | `string` | **Required** | Yes |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `description` | Secret description. | `string` | `null` | No |
| `kms` | Encryption: {} aws/secretsmanager, create = true module key, key_id your key (ARN or ID). | `object({...})` | `{}` | No |
| `recovery_window_in_days` | Recovery window: 0 or 7-30 days. | `number` | `30` | No |
| `secret_string_wo` | Secret value, write-only. | `string` | `null` | No |
| `secret_string_wo_version` | Value version; increment to write a new value. | `number` | `null` | No |
| `rotation` | Rotation by a Lambda function on a schedule (SecretsManager.1, SecretsManager.4). | `object({...})` | `{}` | No |
| `replica_regions` | Replica Regions and optional key ARNs. | `map(object({...}))` | `{}` | No |
| `policy_statements` | Resource policy statements; resources default to the secret. | `list(object({...}))` | `[]` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `arn` | Secret ARN. | No |
| `name` | Secret name. | No |
| `version_id` | Version ID of the written value; null without one. | No |
| `kms_key_arn` | Key ARN in use; null for aws/secretsmanager. | No |
