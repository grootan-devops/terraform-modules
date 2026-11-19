# AWS Backup Module

Scope: `account`

AWS Backup for one account, in every Region of `regions`: a vault whose access policy denies manual deletion of
recovery points, a plan with daily and monthly rules, an account-wide selection, the service role, an Audit Manager
framework, and optional Vault Lock, report plan, notifications and Region settings. A separate management-account call
(`organization_admin`) enables trusted access, registers the delegated administrator and writes the global settings.

## Architecture & Managed Resources

- `aws_backup_vault.this[<region>]`: `<application>-<environment>` (or `vault.name`), encrypted with the AWS managed
  `aws/backup` key, the module key of that Region or your key; `force_destroy = !deletion_protection`.
- `aws_backup_vault_policy.this[<region>]`: deny on recovery point deletion and lifecycle changes for everyone except
  `vault_admin_role_arns`; optional `backup:CopyIntoBackupVault` grants (`copy_into_vault`).
- `aws_backup_plan.this[<region>]`, `aws_backup_selection.this[<region>]` (`plan.enabled`): `rules`, recovery points
  tagged with the governance tags; the type-wide ARNs of `resource_types` plus `additional_resources`, minus
  `not_resources`, narrowed by `selection_tags`.
- `module.role` ([`security/iam-role`](../../security/iam-role)): one global role `<...>-backup-<region>`, trusted by
  AWS Backup in this account, with `AWSBackupServiceRolePolicyForBackup` and `...ForRestores` (plus the S3 pair when
  `s3` is selected).
- `module.encryption[<region>]` ([`core/encryption`](../../core/encryption)): AWS managed key, module key per Region or
  your key.
- `aws_backup_framework.this[<region>]` (`audit_framework.enabled`): six controls, plus
  `BACKUP_RESOURCES_PROTECTED_BY_BACKUP_VAULT_LOCK` when `vault_lock.enabled`.
- Optional per Region: `aws_backup_vault_lock_configuration`, `aws_backup_vault_notifications` (Regions listed in
  `vault_notifications.sns_topic_arns`), `aws_backup_report_plan`, `aws_backup_region_settings` (account-wide).
- Management call: `aws_organizations_aws_service_access.this` (this module owns `backup.amazonaws.com`),
  `aws_organizations_delegated_administrator.this`, `aws_backup_global_settings.this` (`global_settings.enabled`).

| `resource_types` | Selection pattern | Security Hub |
| --- | --- | --- |
| `dynamodb` | `arn:<partition>:dynamodb:*:*:table/*` | DynamoDB.4 |
| `ebs` | `arn:<partition>:ec2:*:*:volume/*` (attached volumes included) | EC2.28 |
| `efs` | `arn:<partition>:elasticfilesystem:*:*:file-system/*` | EFS.2 |
| `rds` | `arn:<partition>:rds:*:*:db:*` | RDS.26 |
| `ec2` (opt-in) | `arn:<partition>:ec2:*:*:instance/*`; with `ebs` it backs up volumes twice | - |
| `s3` (opt-in) | `arn:<partition>:s3:::*`; every bucket needs versioning | - |

## Security & Compliance Guardrails

- **Encryption (Backup.1):** never unencrypted. Fully managed types (EFS, DynamoDB advanced, S3) use the vault key; the
  others keep their source key.
- **No manual deletion:** the vault policy denies `DeleteRecoveryPoint`, `UpdateRecoveryPointLifecycle`,
  `PutBackupVaultAccessPolicy` and `DeleteBackupVaultAccessPolicy` to every principal, the root user included, outside
  `vault_admin_role_arns`. List the Terraform role there, or later policy changes and destroys fail.
- **Bounded retention:** `delete_after` is mandatory; cold storage needs 90 more days; continuous backup keeps at most
  35 days.
- **Vault Lock** is off by default: COMPLIANCE mode is irreversible after `changeable_for_days`. Every rule is
  validated against the lock range.
- **Confused deputy:** the role trust requires `aws:SourceAccount`; key statements allow use only through
  `backup.<region>.amazonaws.com` and deny `backup-storage` for vaults outside this account.
- **Detective:** the Audit Manager framework evaluates encryption, frequency, retention, plan coverage, the deletion
  deny and the last recovery point; it needs AWS Config recording `AWS::Backup::*` (`security/config`).
- **Tags (Backup.2-5):** vault, plan, framework, report plan, role and every recovery point carry the governance tags.

A key in `kms.key_id` must grant what `kms_key_policy_json` lists. A single-Region key serves one Region only: with
several `regions`, use `kms.create` (one key per Region) or a bare `mrk-` multi-Region key ID. The report bucket must
allow `report_bucket_policy_json`; each Region's report plan delivers to it. The managed policies are attached rather
than copied because they span every supported service and AWS updates them with new features.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "backup" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/storage/backup?ref=<version>"

  environment           = "prod"
  vault_admin_role_arns = ["arn:aws:iam::111111111111:role/terraform-deployer"]
}
```

### Complete Production Example

```hcl
module "backup_admin" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/storage/backup?ref=<version>"

  environment        = "prod"
  vault              = { enabled = false }
  organization_admin = { enabled = true, account_id = "222222222222", global_settings = { enabled = true } }
}

module "backup" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/storage/backup?ref=<version>"

  environment           = "prod"
  regions               = ["eu-west-1", "eu-central-1"]
  kms                   = { create = true }
  vault_admin_role_arns = [module.deployer_role.arn, module.break_glass_role.arn]
  vault_lock            = { enabled = true, max_retention_days = 3650 }
  resource_types        = ["dynamodb", "ebs", "efs", "rds", "s3"]

  rules = {
    daily = { schedule = "cron(0 5 ? * * *)", delete_after = 35 }
    monthly = {
      schedule           = "cron(0 5 1 * ? *)"
      delete_after       = 400
      cold_storage_after = 30
      copy_to            = [{ destination_vault_arn = module.central_backup.vault_arns["eu-west-1"] }]
    }
  }

  report_plan = { enabled = true, s3_bucket_name = module.reports_bucket.name, s3_key_prefix = "audit" }
  vault_notifications = {
    enabled        = true
    sns_topic_arns = {
      "eu-west-1"    = module.alarms_eu_west_1.topic_arn
      "eu-central-1" = module.alarms_eu_central_1.topic_arn
    }
  }
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | `"platform"` | No |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `regions` | Regions to manage. Empty: provider Region. | `list(string)` | `[]` | No |
| `vault` | Backup vault, role and audit resources; name sets an exact vault name. | `object({...})` | `{}` | No |
| `deletion_protection` | Keep recovery points when the vault is destroyed. | `bool` | `true` | No |
| `kms` | Encryption: {} AWS managed key, create = true module key per Region, key_id your key (ARN or ID). | `object({...})` | `{}` | No |
| `vault_admin_role_arns` | Principal ARNs exempt from the recovery point deletion deny. | `list(string)` | `[]` | No |
| `copy_into_vault` | Accounts or organization allowed to copy recovery points in. | `object({...})` | `{}` | No |
| `vault_lock` | Vault Lock: GOVERNANCE or COMPLIANCE (irreversible), retention range in days. | `object({...})` | `{}` | No |
| `vault_notifications` | Vault events to an SNS topic per Region. | `object({...})` | `{}` | No |
| `plan` | Backup plan and selection; off when an organization backup policy plans. | `object({...})` | `{}` | No |
| `rules` | Plan rules by name: cron schedule, retention, cold storage, continuous backup, copies. | `map(object({...}))` | `{...}` | No |
| `resource_types` | Types selected account-wide: dynamodb, ebs, ec2, efs, rds, s3. | `list(string)` | `["dynamodb", "ebs", "efs", "rds"]` | No |
| `additional_resources` | Extra resource ARNs or wildcard patterns to select. | `list(string)` | `[]` | No |
| `not_resources` | Resource ARNs or wildcard patterns to exclude. | `list(string)` | `[]` | No |
| `selection_tags` | Tag conditions (AND) that narrow the selection. | `list(object({...}))` | `[]` | No |
| `iam_role` | Backup service role: extend it or bring your own. | `object({...})` | `{}` | No |
| `region_settings` | Account-wide Region settings: service opt-in and full management. | `object({...})` | `{}` | No |
| `audit_framework` | Backup Audit Manager framework and control parameters. | `object({...})` | `{}` | No |
| `report_plan` | Audit Manager report plan to a caller bucket. | `object({...})` | `{}` | No |
| `organization_admin` | Management account call: trusted access, delegated administrator, global settings. | `object({...})` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `vault_arns` | Vault ARN by Region. | No |
| `vault_name` | Vault name; null without a vault. | No |
| `plan_ids` | Backup plan ID by Region. | No |
| `plan_arns` | Backup plan ARN by Region. | No |
| `selection_ids` | Backup selection ID by Region. | No |
| `role_arn` | Backup service role ARN; null without a vault. | No |
| `role_name` | Backup service role name; null for a role brought by the caller. | No |
| `framework_arns` | Audit framework ARN by Region. | No |
| `report_plan_arns` | Report plan ARN by Region. | No |
| `kms_key_arns` | Vault key ARN by Region; null for the AWS managed key. | No |
| `kms_key_policy_json` | Key policy statements a caller key needs; null without a vault. | No |
| `report_bucket_policy_json` | Report bucket policy statement; null without a report plan. | No |
