# AWS Config Module

Scope: `account`

AWS Config for one account: a customer managed recorder, delivery channel and retention in every Region of `regions`,
plus, in the account that needs them, the delivery bucket (log archive or single account), the organization
aggregator, organization or account rules, conformance packs and remediations (delegated administrator), and trusted
access and delegated administrator registration (management account). Every group is optional.

## Architecture & Managed Resources

- `aws_config_configuration_recorder.this`, `aws_config_delivery_channel.this`,
  `aws_config_configuration_recorder_status.this`, `aws_config_retention_configuration.this`: one each per Region,
  through the resource-level `region` argument. All supported types; global IAM types only in
  `recorder.global_resource_region` (default: the provider Region).
- `aws_iam_service_linked_role.config` (`service_linked_role.enabled`): `AWSServiceRoleForConfig` where it is missing.
- `module.bucket` ([`storage/s3`](../../storage/s3), `bucket.enabled`): the delivery bucket
  `<application>-<environment>-config-<account>-<region>` with versioning, encryption, public access block,
  `BucketOwnerEnforced`, lifecycle, optional access logs and the AWS Config delivery policy. With
  `bucket.enabled = false`, `bucket.name` is the existing bucket to deliver to.
- `module.encryption` ([`core/encryption`](../../core/encryption)): AWS managed (SSE-S3), module key or your key.
- `module.aggregator_role` ([`security/iam-role`](../../security/iam-role)) and
  `aws_config_configuration_aggregator.this` (`aggregator.enabled`).
- `aws_config_organization_managed_rule.this` (`organization_rules.enabled`) or `aws_config_config_rule.this`
  (`account_rules.enabled`): the managed rule set in `rules.tf` (209 rules behind the Security Hub controls of the
  library's services, plus `additional_rules`), named `<application>-<environment>-<rule key>`.
- `aws_config_organization_conformance_pack.this`, `aws_config_remediation_configuration.this`.
- `aws_organizations_aws_service_access.this` and `aws_organizations_delegated_administrator.this`
  (`organization_admin.enabled`) for `config.amazonaws.com` and `config-multiaccountsetup.amazonaws.com`. This module
  owns that trusted access; `governance/organizations` rejects the principals.

The rule set is opt-in: use it where Security Hub CSPM is off (Security Hub already runs its own Config rules).

## Security & Compliance Guardrails

- **Recorder (Config.1):** every Region, all supported types, the service-linked role, recorder started; retention
  30-2557 days (default 2557).
- **Encryption:** no `kms` input means SSE-S3 on the bucket and on delivery; `kms.create` creates a key granting
  `config.amazonaws.com` (scoped by `aws:SourceAccount` and, with `bucket.organization_id`, `aws:SourceOrgID`);
  `kms.key_id` uses your key, which must grant the `kms_key_policy_json` statements and sit in the bucket's Region.
- **Bucket:** TLS 1.2 only, all public access blocks, ACLs disabled, SSE-C blocked, no `force_destroy`, 2557-day
  expiration. AWS Config may write only to `[<prefix>/]AWSLogs/<account>/Config/*` of this account,
  `bucket.allowed_account_ids` or the organization.
- **Aggregator role:** trusted by AWS Config in this account only, with `AWSConfigRoleForOrganizations`.
- **Rules:** shipped parameters follow the library baselines (password policy, 365-day log retention, governance tags);
  global rules run once per account; a rule is skipped where AWS does not offer it; unknown `disabled_rules` or
  `rule_parameter_overrides` references fail the plan. `account_rules` and `organization_rules` are exclusive.
- **Remediation:** manual by default; `automatic = true` needs `allow_automatic_remediation = true`.

Rule evaluations are billed per account and Region; Security Hub bills its own checks of the same conditions.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "config" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/config?ref=<version>"

  environment = "prod"
  bucket      = { enabled = true }
}
```

### Complete Production Example

```hcl
module "config_log_archive" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/config?ref=<version>"

  environment = "prod"
  regions     = ["eu-west-1", "us-east-1"]
  kms         = { create = true }
  bucket = {
    enabled         = true
    organization_id = module.organization.id
    access_logs     = { enabled = true, bucket = module.access_logs.bucket_name }
  }
}

module "config_management" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/config?ref=<version>"

  environment         = "prod"
  regions             = ["eu-west-1", "us-east-1"]
  service_linked_role = { enabled = true }
  kms                 = { key_id = module.config_log_archive.kms_key_arn }
  bucket              = { name = module.config_log_archive.bucket_name }
  organization_admin  = { enabled = true, account_id = var.audit_account_id }
}

module "config_audit" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/config?ref=<version>"

  environment = "prod"
  regions     = ["eu-west-1", "us-east-1"]
  kms         = { key_id = module.config_log_archive.kms_key_arn }
  bucket      = { name = module.config_log_archive.bucket_name }
  aggregator  = { enabled = true }
  organization_rules = {
    enabled        = true
    disabled_rules = ["s3-bucket-mfa-delete-enabled"]
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
| `kms` | Encryption: {} AWS managed key, create = true module key, key_id your key (ARN or ID). | `object({...})` | `{}` | No |
| `recorder` | Configuration recorder, delivery channel and retention in every Region. | `object({...})` | `{}` | No |
| `service_linked_role` | Create AWSServiceRoleForConfig. | `object({...})` | `{}` | No |
| `bucket` | Delivery bucket: create it (enabled) or name an existing one. | `object({...})` | `{}` | No |
| `aggregator` | Organization configuration aggregator. | `object({...})` | `{}` | No |
| `organization_rules` | Managed rule set as organization rules; its tuning also shapes account_rules. | `object({...})` | `{}` | No |
| `account_rules` | Managed rule set as account rules in this account. | `object({...})` | `{}` | No |
| `conformance_packs` | Organization conformance packs by key. | `map(object({...}))` | `{}` | No |
| `remediations` | Remediation configurations for rules in this account, by key. | `map(object({...}))` | `{}` | No |
| `allow_automatic_remediation` | Allow remediations with automatic = true. | `bool` | `false` | No |
| `organization_admin` | Management account call: trusted access and delegated administrator. | `object({...})` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `recorder_names` | Recorder name by Region. | No |
| `service_linked_role_arn` | AWSServiceRoleForConfig ARN the recorders use. | No |
| `bucket_name` | Delivery bucket name; null without a bucket. | No |
| `bucket_arn` | Delivery bucket ARN; null without a bucket. | No |
| `kms_key_arn` | Key ARN in use; null for SSE-S3. | No |
| `kms_key_policy_json` | Key policy statements a caller key needs. | No |
| `aggregator_arn` | Aggregator ARN; null when disabled. | No |
| `aggregator_role_arn` | Aggregator role ARN; null when disabled. | No |
| `organization_rule_arns` | Organization rule ARNs by region/rule key. | No |
| `account_rule_names` | Account rule names by region/rule key. | No |
| `account_rule_arns` | Account rule ARNs by region/rule key. | No |
| `conformance_pack_arns` | Conformance pack ARNs by region/pack key. | No |
| `remediation_configuration_arns` | Remediation configuration ARNs by key. | No |
