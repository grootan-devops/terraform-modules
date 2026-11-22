# AWS S3 Bucket Module

Scope: `workload`

A private S3 bucket with encryption, versioning, a TLS-only bucket policy and lifecycle rules, plus optional server
access logs, event notifications, Object Lock and replication with its own role. Log buckets, queues, topics and
functions are other modules; pass their names or ARNs in.

## Architecture & Managed Resources

- `aws_s3_bucket.this`: `<application>-<environment>-<name>-<account>-<region>` (63 characters, hash-truncated), or
  `bucket_name`. Never `force_destroy`.
- `aws_s3_bucket_public_access_block.this`, `aws_s3_bucket_ownership_controls.this` (`BucketOwnerEnforced`),
  `aws_s3_bucket_versioning.this` (always `Enabled`), `aws_s3_bucket_server_side_encryption_configuration.this`.
- `aws_s3_bucket_policy.this` via `module.policy` ([`core/policy-document`](../../core/policy-document)).
- `aws_s3_bucket_lifecycle_configuration.this`: `abort-incomplete-multipart-uploads`, optional
  `expire-noncurrent-versions`, then `lifecycle_rules`.
- `module.encryption` ([`core/encryption`](../../core/encryption)): SSE-S3, module key or your key.
- Optional: `aws_s3_bucket_logging.this`, `aws_s3_bucket_notification.this`, `aws_s3_bucket_cors_configuration.this`,
  `aws_s3_bucket_object_lock_configuration.this`, `aws_s3_bucket_replication_configuration.this` and
  `module.replication_role` ([`security/iam-role`](../../security/iam-role), `<...>-replication-<region>`).

## Security & Compliance Guardrails

- **No public access (S3.1, S3.2, S3.3, S3.8):** all four public access block settings on; a caller `Allow` for
  principal `*` needs a condition.
- **ACLs disabled (S3.12):** `BucketOwnerEnforced`, no ACL input.
- **TLS (S3.5):** the policy denies requests without TLS and below TLS 1.2. These guard statements come first;
  `policy_statements` without `resources` apply to the bucket and its objects, and a caller `Resource` is never changed.
- **Encryption (S3.17):** SSE-S3 by default; with a key, SSE-KMS with a bucket key. SSE-C uploads are blocked.
- **Versioning and lifecycle (S3.10, S3.13, S3.14):** versioning always on; incomplete uploads aborted after 7 days;
  `noncurrent_version_expiration` deletes old versions (deleted versions cannot be recovered).
- **Access logs (S3.9):** `access_logs` writes to a separate SSE-S3 bucket such as
  [`storage/log-bucket`](../log-bucket); server access logs cannot target an SSE-KMS bucket, so they are opt-in (Trivy
  suppression `AVD-AWS-0089`).
- **Event notifications (S3.11):** EventBridge or SNS, SQS and Lambda targets. The target's own policy must allow
  `s3.amazonaws.com` (SNS/SQS) or a Lambda permission for this bucket.
- **Object Lock (S3.15):** only at creation (`object_lock.enabled`); it cannot be turned off.
- **Replication (S3.7):** the role trusts S3 for this bucket only (`aws:SourceAccount`, `aws:SourceArn`), reads this
  bucket, writes to the listed destinations and decrypts the source key through S3 only. With a KMS key every rule
  needs `replica_kms_key_arn`. The destination bucket needs versioning and a policy for the role.

A key passed in `kms.key_id` must allow the principals that read and write the bucket (`kms:Decrypt`,
`kms:GenerateDataKey`) and, with replication, the replication role.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "assets" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/storage/s3?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "assets"
}
```

### Complete Production Example

```hcl
module "assets" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/storage/s3?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "assets"
  kms         = { create = true }

  access_logs                   = { enabled = true, bucket = module.logs.name }
  noncurrent_version_expiration = { enabled = true, days = 90 }
  lifecycle_rules = [
    { id = "archive", prefix = "exports/", transitions = [{ days = 30, storage_class = "GLACIER_IR" }] }
  ]

  policy_statements = [{
    sid        = "ReadAssets"
    actions    = ["s3:GetObject"]
    principals = { AWS = [module.api.role_arn] }
  }]

  notifications = {
    eventbridge = true
    queues      = { uploads = { arn = module.uploads_queue.arn, events = ["s3:ObjectCreated:*"], filter_prefix = "uploads/" } }
  }

  replication = {
    enabled = true
    rules   = [{ id = "dr", destination_bucket_arn = module.assets_dr.arn, replica_kms_key_arn = module.assets_dr.kms_key_arn }]
  }
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | **Required** | Yes |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `name` | Bucket name. | `string` | **Required** | Yes |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `bucket_name` | Exact bucket name. Null: derived. | `string` | `null` | No |
| `kms` | Encryption: {} SSE-S3, create = true module key, key_id your key (ARN or ID). | `object({...})` | `{}` | No |
| `policy_statements` | Extra bucket policy statements; resources default to the bucket and its objects. | `list(object({...}))` | `[]` | No |
| `lifecycle_rules` | Lifecycle rules by id; filter by prefix and tags. | `list(object({...}))` | `[]` | No |
| `abort_incomplete_multipart_upload_days` | Days before incomplete multipart uploads are aborted. | `number` | `7` | No |
| `noncurrent_version_expiration` | Delete noncurrent versions after days. | `object({...})` | `{}` | No |
| `cors_rules` | CORS rules. | `list(object({...}))` | `[]` | No |
| `access_logs` | Server access logs to a log bucket (S3.9). | `object({...})` | `{}` | No |
| `notifications` | Event notifications (S3.11): EventBridge, SNS, SQS, Lambda. | `object({...})` | `{}` | No |
| `object_lock` | Object Lock (set at creation) and default retention. | `object({...})` | `{}` | No |
| `replication` | Replication rules and role. | `object({...})` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `id` | Bucket ID. | No |
| `arn` | Bucket ARN. | No |
| `name` | Bucket name. | No |
| `domain_name` | Bucket domain name. | No |
| `regional_domain_name` | Regional domain name for CloudFront origins. | No |
| `kms_key_arn` | Key ARN in use; null for SSE-S3. | No |
| `replication_role_arn` | Replication role ARN; null without replication. | No |
| `policy_json` | Bucket policy JSON. | No |
