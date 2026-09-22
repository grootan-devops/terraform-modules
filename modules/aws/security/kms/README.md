# AWS KMS Module

The `kms` module provisions symmetric and asymmetric AWS Key Management Service (KMS) Customer Managed Keys (CMKs), alias namespaces, and multi-region replica keys.

## Architecture & Managed Resources

- `aws_kms_key.this`: Primary cryptographic key resource.
- `aws_kms_alias.this`: Standardized alias namespace (`alias/${application}-${environment}-${name}-key`).
- `aws_kms_key_policy.this`: Custom or default IAM administrative key policy document.
- `aws_kms_replica_key.this`: Optional cross-region replica key for multi-region active-active architectures.

### Security & Compliance Guardrails

- **Automatic Key Rotation**: Enabled by default (`enable_key_rotation = true`) with a 365-day rotation cadence.
- **Deletion Safeguards**: Enforces a 30-day deletion waiting window (`deletion_window_in_days = 30`).
- **Policy Lockout Safety Check**: Prevents policy updates that would permanently orphan administrative access.

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
module "kms" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/kms?ref=1.0.0"

  application = "core"
  environment = "prod"
  name        = "primary"
}
```

### Complete Production Example

```hcl
module "kms" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/kms?ref=1.0.0"

  providers = {
    aws         = aws
    aws.replica = aws.secondary
  }

  application = "finance"
  environment = "prod"
  name        = "ledger"

  description             = "Dedicated CMK for transactional ledger encryption"
  key_usage               = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  enable_key_rotation     = true
  rotation_period_in_days = 365
  deletion_window_in_days = 30
  multi_region             = true

  replica_key = {
    create                  = true
    region                  = "us-east-1"
    deletion_window_in_days = 30
  }

  tags = {
    ComplianceLevel = "PCI-DSS-Level-1"
  }
}
```

---

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | :---: |
| `name` | Name identifier for the KMS key | `string` | `null` | No |
| `description` | Optional custom description for the KMS key. Overrides the default computed description. | `string` | `null` | No |
| `application` | Name of the product | `string` | **Required** | Yes |
| `environment` | Deployment environment name (e.g. dev, staging, prod). | `string` | **Required** | Yes |
| `is_enabled` | Specifies whether the key is enabled. | `bool` | `true` | No |
| `key_usage` | Specifies the intended use of the key. Valid values: ENCRYPT_DECRYPT, SIGN_VERIFY, or GENERATE_VERIFY_MAC. | `string` | `"ENCRYPT_DECRYPT"` | No |
| `customer_master_key_spec` | Specifies whether the key contains a symmetric key or an asymmetric key pair and the encryption algorithms or signing algorithms that the key supports. Valid values: SYMMETRIC_DEFAULT, RSA_2048, RSA_3072, RSA_4096, HMAC_256, ECC_NIST_P256, ECC_NIST_P384, ECC_NIST_P521, or ECC_SECG_P256K1. | `string` | `"SYMMETRIC_DEFAULT"` | No |
| `deletion_window_in_days` | Duration in days after which the key is deleted after destruction of the resource. Must be between 7 and 30. | `number` | `30` | No |
| `enable_key_rotation` | Specifies whether key rotation is enabled. Defaults to true for production safety. Note: Rotation is only supported for symmetric keys. | `bool` | `true` | No |
| `rotation_period_in_days` | Custom period of time between each rotation date. Must be a number between 90 and 2560. Default is AWS default if not specified (365). | `number` | `365` | No |
| `multi_region` | Indicates whether the KMS key is a multi-Region (true) or regional (false) key. Default is false. | `bool` | `false` | No |
| `policy_json` | A valid policy JSON document. | `string` | `null` | No |
| `replica_key` | Configuration for creating a replica key in a secondary region. multi_region must be true. | `object({...})` | `{ create = false }` | No |
| `tags` | Additional tags to apply to all resources | `map(string)` | `{}` | No |

---

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | :---: |
| `key_arn` | The ARN of the KMS key | No |
| `key_id` | The globally unique identifier for the key | No |
| `replica_key_arn` | The ARN of the KMS replica key if created | No |
