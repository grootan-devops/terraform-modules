# AWS S3 Bucket Module

The `s3` module provisions secure, compliant AWS Simple Storage Service (S3) buckets tailored for enterprise workloads. It enforces strict public access blocking, mandatory customer-managed KMS key encryption, automated TLS 1.2+ transport policies, and lifecycle management to optimize storage costs over time.

## Architecture & Managed Resources

- `aws_s3_bucket.this`: Primary S3 storage bucket.
- `aws_s3_bucket_public_access_block.this`: Hardcoded boundary blocking all public ACLs and bucket policies.
- `aws_s3_bucket_ownership_controls.this`: Enforces bucket-owner object ownership (`BucketOwnerEnforced`).
- `aws_s3_bucket_server_side_encryption_configuration.this`: Enforces SSE-KMS with S3 Bucket Keys (`bucket_key_enabled = true`).
- `aws_s3_bucket_policy.this`: Automatically denies non-HTTPS requests and requests below TLS 1.2.
- `aws_s3_bucket_versioning.this`: Manages object versioning state.
- `aws_s3_bucket_lifecycle_configuration.this`: Applies transition and retention policies.
- `aws_s3_bucket_replication_configuration.this`: Optional cross-region replication setup with dedicated IAM role.

### Security & Compliance Guardrails

- **Mandatory KMS CMK**: Requires `kms_key_arn`. S3 Bucket Keys are enabled to reduce KMS API costs by up to 99%.
- **Hardcoded Public Access Block**: `block_public_acls`, `block_public_policy`, `ignore_public_acls`, and `restrict_public_buckets` are hardcoded to `true`.
- **TLS 1.2+ Enforcement**: Injects explicit `Deny` statements for `aws:SecureTransport = false` and `s3:TlsVersion < 1.2`.
- **Versioning by Default**: `enable_versioning` defaults to `true` to protect against accidental object deletion or ransomware.

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
module "s3_bucket" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/storage/s3?ref=1.0.0"

  application = "core"
  environment = "prod"
  name        = "assets"
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
}
```

### Complete Production Example

```hcl
module "s3_bucket" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/storage/s3?ref=1.0.0"

  application          = "analytics"
  environment          = "prod"
  name                 = "data-lake"
  bucket_name_override = "company-analytics-data-lake-prod-us-west-2"

  kms_key_arn       = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
  enable_versioning = true
  object_ownership  = "BucketOwnerEnforced"

  lifecycle_rules = [
    {
      id     = "cleanup-multipart"
      status = "Enabled"
      abort_incomplete_multipart_upload = {
        days_after_initiation = 7
      }
    },
    {
      id     = "transition-cold-storage"
      status = "Enabled"
      transition = {
        days          = 30
        storage_class = "STANDARD_IA"
      }
      noncurrent_version_expiration = {
        noncurrent_days = 90
      }
      expiration = {
        days = 365
      }
    }
  ]

  cors_rules = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["GET", "HEAD", "PUT"]
      allowed_origins = ["https://analytics.company.com"]
      expose_headers  = ["ETag"]
      max_age_seconds = 3600
    }
  ]

  custom_policy_statements = [
    {
      Sid       = "AllowSpecificWorkerRole"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::123456789012:role/AnalyticsIngestionWorker" }
      Action    = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
    }
  ]

  tags = {
    DataClassification = "Confidential"
    GovernanceReview   = "Approved"
  }
}
```

---

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | :---: |
| `name` | The name of the S3 bucket | `string` | `null` | No |
| `bucket_name_override` | Override the default S3 bucket name format with this exact string | `string` | `null` | No |
| `application` | Name of the product | `string` | **Required** | Yes |
| `environment` | Deployment environment name (e.g. dev, staging, prod). | `string` | **Required** | Yes |
| `kms_key_arn` | The ARN of the KMS key to use for bucket encryption. This must be a customer-managed AWS KMS Key. | `string` | **Required** | Yes |
| `enable_versioning` | If true, bucket versioning is enabled. If false, it is suspended. | `bool` | `true` | No |
| `replication_configuration` | Replication configuration object | `object({...})` | `null` | No |
| `object_ownership` | Object ownership. Valid values: BucketOwnerEnforced, BucketOwnerPreferred, ObjectWriter. | `string` | `"BucketOwnerEnforced"` | No |
| `access_control_policy` | Access Control Policy to apply to the S3 bucket. | `object({...})` | `null` | No |
| `lifecycle_rules` | List of lifecycle rules to configure on the S3 bucket. | `list(object({...}))` | `[...]` | No |
| `public_access_block` | Public access block configuration. | `object({...})` | `{...}` | No |
| `custom_policy_statements` | A list of custom bucket policy statements. The `Resource` block is automatically injected into each statement for this bucket. | `list(any)` | `[]` | No |
| `tags` | Additional tags to apply to all resources | `map(string)` | `{}` | No |
| `cors_rules` | List of CORS rules to configure for the bucket | `list(object({...}))` | `[]` | No |

---

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | :---: |
| `bucket_arn` | The ARN of the bucket | No |
| `bucket_name` | The name of the bucket | No |
