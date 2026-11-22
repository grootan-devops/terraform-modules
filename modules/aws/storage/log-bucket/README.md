# AWS S3 Log Bucket Module

Scope: `workload`

An S3 bucket for AWS log delivery, built on [`storage/s3`](../s3): SSE-S3, versioning, TLS-only policy, public access
blocked, logs expired after 365 days, plus only the bucket policy statements each log delivery service needs, one
switch per log type.

## Architecture & Managed Resources

- `module.bucket` ([`storage/s3`](../s3)): `<application>-<environment>-<name>-<account>-<region>` or `bucket_name`,
  with every `storage/s3` resource and guardrail.
- Lifecycle: `expire-logs` deletes log objects after `expiration_days` (365) with optional `transitions`;
  `expire-noncurrent-versions` deletes expired versions after `noncurrent_version_expiration_days` (30).
- Bucket policy statements, after the TLS guards:

| Switch | Principal | Access |
| --- | --- | --- |
| `s3_access_logs` (on) | `logging.s3.amazonaws.com` | `s3:PutObject` on objects; `aws:SourceAccount`, `aws:SourceArn` (`source_bucket_arns`, else any bucket of those accounts) |
| `elb_logs` | `logdelivery.elasticloadbalancing.amazonaws.com`, and the Region's ELB account where AWS documents one (Regions before August 2022) | `s3:PutObject` on `<prefix>/AWSLogs/<account>/*` |
| `vended_logs` | `delivery.logs.amazonaws.com` (CloudFront standard logging v2, VPC flow logs, WAF, NLB, other vended logs) | `s3:PutObject` with `bucket-owner-full-control`, `s3:GetBucketAcl`, `s3:ListBucket`; `aws:SourceAccount`, `aws:SourceArn` (`source_arns`, else `arn:aws:logs:*:<account>:*`) |

- CloudFront standard logging v2: [`network/cloudfront`](../../network/cloudfront) with
  `logging = { destination = "s3", s3_bucket_arn = module.logs.arn }`. The delivery is created in us-east-1 and writes
  across Regions, so the bucket can be in any Region; its `aws:SourceArn` is
  `arn:aws:logs:us-east-1:<account>:delivery-source:*`, which the default covers (add it when you set `source_arns`).
  CloudFront rejects bucket names with dots.
- WAF: [`network/waf`](../../network/waf) with `logging = { destination = "s3", s3_bucket_arn = ... }`, into a log bucket
  of its own named `aws-waf-logs-*` (`bucket_name`) in the web ACL's account.

## Security & Compliance Guardrails

- **SSE-S3 only:** S3 server access logs and ELB access logs support only SSE-S3, and vended logs reject AWS managed
  keys, so the module sets no `kms` input.
- **Confused deputy:** S3 and vended log statements carry `aws:SourceAccount` and `aws:SourceArn`; ELB statements are
  limited to the `AWSLogs/<account>/` path of each source account.
- **Accounts:** `source_account_ids` (default this account) lets a central log bucket accept other accounts.
- **No ACLs:** `BucketOwnerEnforced`. CloudFront legacy standard logging needs ACLs and is not supported; use v2
  (`vended_logs`).
- **Retention (S3.10, S3.13):** 365 days by default; versioning stays on (S3.14).
- **Its own access logs (S3.9):** `access_logs` to another bucket; a log bucket does not log to itself.

WAF delivers only to buckets named `aws-waf-logs-*`: set `bucket_name = "aws-waf-logs-..."`. No Object Lock: S3 server
access logs cannot target a bucket with a default retention.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "logs" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/storage/log-bucket?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "logs"
}
```

### Complete Production Example

```hcl
module "logs" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/storage/log-bucket?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "logs"

  s3_access_logs = { source_bucket_arns = [module.assets.arn] }
  elb_logs       = { enabled = true, prefix = "alb" }
  vended_logs    = { enabled = true }

  expiration_days = 731
  transitions     = [{ days = 90, storage_class = "GLACIER_IR" }]
  access_logs     = { enabled = true, bucket = module.audit_logs.name }
}

module "assets" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/storage/s3?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "assets"
  access_logs = { enabled = true, bucket = module.logs.name }
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
| `source_account_ids` | Accounts that deliver logs. Empty: this account. | `list(string)` | `[]` | No |
| `expiration_days` | Days before log objects expire. | `number` | `365` | No |
| `noncurrent_version_expiration_days` | Days before expired log versions are deleted. | `number` | `30` | No |
| `transitions` | Storage class transitions for log objects. | `list(object({...}))` | `[]` | No |
| `s3_access_logs` | S3 server access logs; source buckets limit the writers. | `object({...})` | `{}` | No |
| `elb_logs` | Load balancer access and connection logs under prefix. | `object({...})` | `{}` | No |
| `vended_logs` | Logs from delivery.logs.amazonaws.com (CloudFront, VPC flow logs, WAF, NLB). | `object({...})` | `{}` | No |
| `access_logs` | This bucket's own server access logs to another bucket (S3.9). | `object({...})` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `id` | Bucket ID. | No |
| `arn` | Bucket ARN. | No |
| `name` | Bucket name. | No |
| `domain_name` | Bucket domain name. | No |
