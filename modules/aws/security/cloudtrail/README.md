# AWS CloudTrail Module

Scope: `account`

One multi-Region CloudTrail trail (an organization trail by default) with log file validation, a KMS key, a CloudWatch
Logs log group with its delivery role and a hardened S3 log bucket. In the management account it also owns CloudTrail
trusted access and the CloudTrail delegated administrators. Trail, bucket and organization settings switch on and off
independently, so one module serves a single account, a management account and a log-archive bucket.

## Architecture & Managed Resources

- `aws_cloudtrail.this` (`trail.enabled`): `<application>-<environment>`, multi-Region, global service events, log
  file validation; read and write management events always, data events and Insights opt-in.
- `module.encryption` ([`core/encryption`](../../core/encryption)): the trail, bucket and log group key
  (`alias/<application>-<environment>-cloudtrail`, or your key).
- `module.log_group` ([`observability/log-group`](../../observability/log-group)) and `module.role`
  ([`security/iam-role`](../../security/iam-role)): `/aws/cloudtrail/<application>-<environment>` and the delivery role
  `<...>-trail-logs-<region>` (`cloudwatch_logs.enabled`).
- `module.bucket` ([`storage/s3`](../../storage/s3), `bucket.enabled`): `<...>-cloudtrail-<account>-<region>` with
  public access block, `BucketOwnerEnforced`, versioning, SSE-KMS with the trail key and a bucket key, lifecycle,
  policy, optional Object Lock and access logs. `bucket.enabled = false` writes to `bucket.name` instead.
- `aws_organizations_aws_service_access.this` and `aws_cloudtrail_organization_delegated_admin_account.this`
  (`organization_admin.enabled`): trusted access for `cloudtrail.amazonaws.com` and up to three delegated
  administrators. This module is the only owner of that principal; `governance/organizations` rejects it.

| Call | `trail` | `bucket` | `organization_admin` |
| --- | --- | --- | --- |
| Management account, all in one | on | on | `enabled = true` |
| Trail with a central bucket | on | `enabled = false`, `name` | as needed |
| Log archive bucket | `enabled = false` | `additional_trail_arns`, `organization_id` | off |
| Organization settings only | `enabled = false` | `enabled = false` | `enabled = true`, `account_ids` |

## Security & Compliance Guardrails

- **Trail integrity (CloudTrail.1, .3, .4):** multi-Region, global service events, log file validation and logging are
  fixed; excluding `kms`/`rdsdata` management events is possible but fails CloudTrail.1.
- **Encryption (CloudTrail.2, S3.17):** CloudTrail has no AWS managed key and CloudTrail.2 needs SSE-KMS, so the module
  creates its key by default; `kms = { create = false, key_id = ... }` uses yours. The key must be in the provider Region.
- **Bucket policy:** CloudTrail may read the ACL and write `AWSLogs/<account>/` and `AWSLogs/<organization>/` only with
  `aws:SourceArn` = the trail ARN(s) and `bucket-owner-full-control`; `storage/s3` adds the TLS 1.2 only denies (S3.5).
  Caller `bucket.policy_statements` come after these and default to the bucket and its objects.
- **Bucket protection (CloudTrail.6, S3.8, S3.12, S3.14):** public access blocked, ACLs disabled, versioning on, never
  `force_destroy`, SSE-C blocked; lifecycle keeps logs 2557 days and aborts incomplete uploads. MFA delete needs the
  root user and is not managed.
- **Logs (CloudTrail.5, CloudWatch.16):** 365 days, deletion protection, the module key. The delivery role may only
  create streams and put events in its log group; its trust has no `aws:SourceArn` condition, as AWS documents none
  for this role.
- **Access logs (CloudTrail.7, S3.9):** opt-in through `bucket.access_logs`, to a separate SSE-S3 bucket.
- **Disablement:** member accounts cannot stop an organization trail; use the `protect_security_services` and
  `protect_audit_buckets` SCPs of [`governance/organizations`](../../governance/organizations) for the rest.

A key passed in `kms.key_id` needs the `kms_key_policy_json` statements: `cloudtrail.amazonaws.com` (`aws:SourceArn`
and `kms:EncryptionContext:aws:cloudtrail:arn`), `logs.<region>.amazonaws.com` (`kms:EncryptionContext:aws:logs:arn`)
and `kms:Decrypt` for this account. An organization trail created from a delegated administrator is owned by the
management account: set `trail.management_account_id`.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "cloudtrail" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/cloudtrail?ref=<version>"

  environment        = "prod"
  organization_admin = { enabled = true }
}
```

### Complete Production Example

```hcl
module "cloudtrail" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/cloudtrail?ref=<version>"

  environment = "prod"

  trail = {
    data_events   = { s3_objects = { enabled = true, read_write_type = "WriteOnly" } }
    insight_types = ["ApiCallRateInsight", "ApiErrorRateInsight"]
  }

  cloudwatch_logs = { retention_in_days = 731 }
  iam_role        = { permissions_boundary_arn = module.boundary.arn }

  bucket = {
    organization_id = module.organizations.organization_id
    key_prefix      = "cloudtrail"
    object_lock     = { enabled = true, mode = "GOVERNANCE", days = 365 }
    access_logs     = { enabled = true, bucket = module.access_logs_bucket.name }
    policy_statements = [{
      sid        = "AuditorsRead"
      actions    = ["s3:ListBucket"]
      principals = { AWS = [module.auditor_role.arn] }
    }]
  }

  organization_admin = {
    enabled     = true
    account_ids = [module.security_account.id]
  }

  tags = { DataClassification = "audit" }
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | `"platform"` | No |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `kms` | Encryption: {} module key, or key_id your key (ARN or ID) with create = false. | `object({...})` | `{}` | No |
| `trail` | Multi-Region trail: organization scope, data events and Insights. | `object({...})` | `{}` | No |
| `cloudwatch_logs` | CloudWatch log group for trail events. | `object({...})` | `{}` | No |
| `iam_role` | Log delivery role: extend it or bring your own. | `object({...})` | `{}` | No |
| `bucket` | Log bucket: create one or name an existing one. | `object({...})` | `{}` | No |
| `organization_admin` | Management account call: trusted access and delegated administrators. | `object({...})` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `arn` | Trail ARN. | No |
| `name` | Trail name. | No |
| `bucket_name` | Log bucket name. | No |
| `bucket_arn` | Log bucket ARN. | No |
| `log_group_name` | Log group name. | No |
| `log_group_arn` | Log group ARN. | No |
| `role_arn` | Log delivery role ARN. | No |
| `role_name` | Log delivery role name; null for a role brought by the caller. | No |
| `kms_key_arn` | Key ARN in use. | No |
| `kms_key_policy_json` | Key policy statements a caller key needs. | No |
