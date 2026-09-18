# AWS Secrets Manager Module

The `secrets-manager` module manages AWS Secrets Manager secrets, automatic versioning payloads, resource policies, and automated Lambda rotation schedules.

### Architecture & Managed Resources
- `aws_secretsmanager_secret.this`: Primary encrypted secret container.
- `aws_secretsmanager_secret_version.this`: Initial secret string / binary payload.
- `aws_secretsmanager_secret_policy.this`: Granular IAM resource access policy.
- `aws_secretsmanager_secret_rotation.this`: Configures Lambda rotation schedules.

### Security & Compliance Guardrails
- **Mandatory KMS CMK**: Encryption at rest strictly requires `kms_key_arn`.
- **Soft Delete Window**: Defaults to 30-day recovery window (`recovery_window_in_days = 30`).
- **Public Policy Prevention**: `block_public_policy` validation prevents accidental external sharing.

---

## Requirements & Providers

| Requirement | Version |
|---|---|
| `terraform` | `>= 1.11.0` |
| `aws` | `>= 6.64.0` |

---

## Usage Examples

### Minimal Working Example
```hcl
module "secret" {
  source = "git::https://github.com/organization/terraform-modules.git//modules/aws/security/secrets-manager"

  application = "core"
  environment = "prod"
  name        = "db-credentials"

  kms_key_arn   = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
  secret_string = jsonencode({ username = "app_user", password = "TemporaryInitialPassword123!" })
}
```

### Complete Production Example
```hcl
module "secret" {
  source = "git::https://github.com/organization/terraform-modules.git//modules/aws/security/secrets-manager"

  application = "payment"
  environment = "prod"
  name        = "stripe-keys"

  kms_key_arn             = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
  description             = "Production Stripe integration API keys"
  recovery_window_in_days = 30
  secret_string           = jsonencode({ live_key = "sk_live_12345", webhook_secret = "whsec_67890" })

  rotation_config = {
    rotation_lambda_arn = "arn:aws:lambda:us-west-2:123456789012:function:secrets-rotator"
    rotate_immediately  = false
    rotation_rules = {
      automatically_after_days = 30
    }
  }

  tags = {
    SecurityAudit = "Quarterly"
  }
}
```

---

## Inputs Specification

| Name | Description | Type | Default | Required |
|---|---|---|---|:---:|
| `application` | Application name for resource naming and tagging. | `string` | **Required** | Yes |
| `environment` | Deployment environment name (e.g. dev, staging, prod). | `string` | **Required** | Yes |
| `name` | Friendly name of the secret. Conflicts with name_prefix. | `string` | `null` | No |
| `name_prefix` | Creates a unique name beginning with the specified prefix. Conflicts with name. | `string` | `null` | No |
| `description` | Description of the secret. | `string` | `null` | No |
| `kms_key_arn` | ARN of the AWS KMS key to encrypt the secret values. Strictly required. | `string` | **Required** | Yes |
| `recovery_window_in_days` | Number of days that AWS Secrets Manager waits before it can delete the secret. (0 or 7 to 30). | `number` | `30` | No |
| `force_overwrite_replica_secret` | Accepts boolean value to specify whether to overwrite a secret with the same name in the destination Region. | `bool` | `false` | No |
| `type` | Type of secret for managed external secrets (SalesforceClientSecret, BigIDClientSecret, SnowflakeKeyPairAuthentication). | `string` | `null` | No |
| `region` | Region where this resource will be managed. | `string` | `null` | No |
| `tags` | Key-value map of user-defined tags that are attached to the secret. | `map(string)` | `{}` | No |
| `policy` | Valid JSON document representing a resource policy to attach to the secret. | `string` | `null` | No |
| `block_public_policy` | Makes an API call to validate the resource policy to prevent public access. | `bool` | `true` | No |
| `rotation_config` | Configuration block for secret rotation. | `object({...})` | `null` | No |
| `secret_string` | Text data to encrypt and store in this version of the secret. | `string` | `null` | No |
| `secret_binary` | Binary data to encrypt and store in this version of the secret (base64-encoded). | `string` | `null` | No |
| `secret_string_wo` | Write-only text data to encrypt and store in this version of the secret. | `string` | `null` | No |
| `secret_string_wo_version` | Version identifier for secret_string_wo to trigger updates. | `number` | `null` | No |
| `version_stages` | List of staging labels attached to this version of the secret. | `list(string)` | `null` | No |

---

## Outputs Specification

| Name | Description | Sensitive |
|---|---|:---:|
| `arn` | ARN of the secret. | No |
| `id` | ID of the secret. | No |
| `name` | Name of the secret. | No |
| `version_id` | Unique identifier of the version of the secret. | No |
| `policy_id` | ID of the secret policy. | No |