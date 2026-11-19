# AWS Systems Manager Module

Scope: `account`

A Systems Manager baseline for one account in every Region of `regions` (default: the provider Region): service
settings (block public document sharing, Automation logging, Default Host Management), Session Manager preferences
with session logs, one Quick Setup patch policy (the AWS recommended way to patch) for this account or a set of OUs,
Inventory with an optional resource data sync and central bucket, and weekly SSM Agent updates. Called in the
management account with `organization_admin`, it registers trusted access and the delegated administrator;
`quick_setup_host_management` deploys organization-wide Quick Setup host management instead of the per-account
inventory and agent update.

## Architecture & Managed Resources

Per Region of `regions`, through the resource-level `region` argument:

- `aws_ssm_service_setting.document_public_sharing`, `.automation_log_destination`, `.automation_log_group`,
  `.default_host_management` (`account_settings`).
- `module.automation_log_group`, `module.session_log_group` ([`observability/log-group`](../../observability/log-group)):
  `/aws/ssm/<application>-<environment>/automation` and `/sessions`.
- `aws_ssm_document.session_manager`: the `SSM-SessionManagerRunShell` preferences document.
- `aws_ssm_association.inventory` (`AWS-GatherSoftwareInventory`), `aws_ssm_association.agent_update`
  (`AWS-UpdateSSMAgent`), `aws_ssm_resource_data_sync.this` (opt-in).
- `module.encryption` ([`core/encryption`](../../core/encryption)): AWS managed encryption, a module key per Region
  (alias `<application>-<environment>-ssm`) or your key.

Once per call:

- `aws_ssmquicksetup_configuration_manager.patch_policy` (`AWSQuickSetupType-PatchPolicy`,
  `<application>-<environment>-patch-policy`): scan and install schedules, reboot option, targets (`*`, tags,
  resource group or instance IDs) in this account or `patching.target_organizational_units`, in every Region of
  `regions`. Baselines are the AWS defaults (`data.aws_ssm_patch_baselines`) or, with `use_default = false`,
  `aws_ssm_patch_baseline.this` in the provider Region for the operating systems in `custom`.
- `module.patch_administration_role` and `module.patch_execution_role`
  ([`security/iam-role`](../../security/iam-role)): the local deployment roles Quick Setup requires for every patch
  policy, `<application>-<environment>-ssm-patch-admin-<region>` and `<...>-ssm-patch-exec-<region>`.
- `module.dhmc_role` ([`security/iam-role`](../../security/iam-role)): `<application>-<environment>-ssm-dhmc-<region>`
  (path `/service-role/`).
- `module.bucket` ([`storage/s3`](../../storage/s3), `inventory_bucket.enabled`, provider Region): the central inventory
  bucket `<application>-<environment>-ssm-inventory-<account>-<region>`, encrypted with the provider-Region key when
  `kms` sets one, plus the Systems Manager delivery statements in its bucket policy.
- `aws_ssmquicksetup_configuration_manager.host_management`, `aws_organizations_aws_service_access.ssm`,
  `aws_organizations_delegated_administrator.ssm` (management account or Quick Setup delegated administrator).

## Security & Compliance Guardrails

- **SSM.7, SSM.4:** public sharing of SSM documents blocked in every Region.
- **SSM.6:** Automation `aws:executeScript` output logged to a 365-day log group with deletion protection.
- **SSM.1:** Default Host Management makes IMDSv2 instances managed nodes without an instance profile.
- **SSM.2, SSM.3:** the patch policy scans every node daily at 01:00 UTC (new nodes at once) and installs on Sunday
  at 02:00 UTC with `RebootIfNeeded`; custom baselines approve Critical and Important security patches after 7 days
  (Ubuntu and Debian at once); inventory and agent update associations on every node.
- **Sessions:** logged to the encrypted session log group, 20-minute idle and 60-minute total limits, run as
  `ssm-user`; session data gets KMS encryption only when `kms` sets a key (otherwise TLS only).
- **Least privilege:** the administration role is trusted only by CloudFormation for this account's
  `AWS-QuickSetup-*` stack sets and may only assume the execution role; the execution role is trusted only by the
  administration role and holds the AWS managed `AWSQuickSetupPatchPolicyDeploymentRolePolicy`. The DHMC role adds
  session log and key permissions (`session_kms_iam_policy_json`, attach it to custom instance profiles),
  `AWSQuickSetupPatchPolicyBaselineAccess` while patching is on, and S3 writes under `patching.output_logs.prefix`.
- **Inventory bucket:** SSE-S3 (SSE-KMS with a key), TLS 1.2 only, delivery limited to `ssm.amazonaws.com` with
  `aws:SourceAccount`/`aws:SourceArn` (or `aws:SourceOrgID`), never `force_destroy`.
- **One scanner:** Quick Setup host management is rejected while `inventory` or `agent_update` are on (a node accepts
  only one inventory association), and its `ScanInstances` is off while the patch policy runs, so nodes are not
  scanned twice.

Patch policy prerequisites:

- The Terraform principal needs `iam:PassRole` on the administration role for `ssm-quicksetup.amazonaws.com` and
  `cloudformation.amazonaws.com`, and the patch policy runs only in the Regions Quick Setup supports for patch
  policies.
- With `target_organizational_units`, call the module in the management account (AWS does not allow a delegated
  administrator) after Quick Setup onboarding; `organization_admin` may share that call.
- Nodes with their own instance profile need `attach_instance_policies = true`, or
  `AWSQuickSetupPatchPolicyBaselineAccess` and the `QSConfigId-<id>` tag on their role. VPC endpoint policies for S3
  must allow the `aws-quicksetup-patchpolicy-*` buckets. With `output_logs`, nodes in other accounts need write access
  to the bucket.

A key passed in `kms.key_id` must allow `logs.<region>.amazonaws.com` (encryption context
`aws:logs:arn` = the two log group ARNs) and `ssm.amazonaws.com` `kms:GenerateDataKey` (`aws:SourceAccount`,
`aws:SourceArn` = `arn:aws:ssm:*:<account>:resource-data-sync/*`). With several Regions pass an `mrk-` key ID.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "systems_manager" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/governance/systems-manager?ref=<version>"

  environment = "prod"
}
```

### Complete Production Example

```hcl
module "systems_manager" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/governance/systems-manager?ref=<version>"

  environment              = "prod"
  regions                  = ["eu-west-1", "eu-central-1"]
  kms                      = { key_id = module.ssm_key.id }
  permissions_boundary_arn = aws_iam_policy.boundary.arn

  session_manager = {
    s3_logs = { enabled = true, bucket = module.session_logs.name, prefix = "sessions" }
  }

  patching = {
    target      = { type = "Tags", tag_key = "Patch", tag_value = "prod" }
    output_logs = { enabled = true, bucket = module.patch_logs.name, prefix = "patching" }
    baselines = {
      use_default = false
      custom = {
        amazon-linux-2023 = { operating_system = "AMAZON_LINUX_2023" }
        windows           = { operating_system = "WINDOWS" }
      }
    }
  }

  inventory = {
    resource_data_sync = { enabled = true, organization = true }
  }

  inventory_bucket = {
    enabled         = true
    organization_id = module.organization.organization_id
    access_logs     = { enabled = true, bucket = module.access_logs.name }
  }
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | `"platform"` | No |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `regions` | Regions to baseline. Empty: provider Region. | `list(string)` | `[]` | No |
| `kms` | Encryption: {} AWS managed key, create = true module key, key_id your key (ARN or ID). | `object({...})` | `{}` | No |
| `permissions_boundary_arn` | Permissions boundary ARN for the module roles. | `string` | `null` | No |
| `cloudwatch_logs` | Automation and session log groups. | `object({...})` | `{}` | No |
| `account_settings` | Service settings: block public document sharing, Automation logging, Default Host Management. | `object({...})` | `{}` | No |
| `session_manager` | Session Manager preferences and session logs. | `object({...})` | `{}` | No |
| `patching` | Quick Setup patch policy. | `object({...})` | `{}` | No |
| `inventory` | Inventory association and resource data sync. | `object({...})` | `{}` | No |
| `inventory_bucket` | Central inventory bucket for resource data syncs. | `object({...})` | `{}` | No |
| `agent_update` | SSM Agent update association. | `object({...})` | `{}` | No |
| `quick_setup_host_management` | Organization-wide Quick Setup host management. | `object({...})` | `{}` | No |
| `organization_admin` | Trusted access and delegated administrator for Systems Manager. | `object({...})` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `kms_key_arns` | Key ARN by Region; null for AWS managed encryption. | No |
| `automation_log_group_names` | Automation log group name by Region. | No |
| `automation_log_group_arns` | Automation log group ARN by Region. | No |
| `session_log_group_names` | Session log group name by Region. | No |
| `session_log_group_arns` | Session log group ARN by Region. | No |
| `session_document_arns` | Session preferences document ARN by Region. | No |
| `session_kms_iam_policy_json` | IAM policy managed nodes need for sessions; null when disabled. | No |
| `default_host_management_role_arn` | Default Host Management role ARN. | No |
| `default_host_management_role_name` | Default Host Management role name. | No |
| `patch_policy_manager_arn` | Patch policy configuration manager ARN. | No |
| `patch_policy_administration_role_arn` | Patch policy local administration role ARN. | No |
| `patch_policy_execution_role_arn` | Patch policy local execution role ARN. | No |
| `patch_baseline_ids` | Custom patch baseline ID by key. | No |
| `association_ids` | Inventory and agent update association IDs by Region. | No |
| `resource_data_sync_name` | Resource data sync name; null when disabled. | No |
| `inventory_bucket_name` | Inventory bucket name. | No |
| `inventory_bucket_arn` | Inventory bucket ARN. | No |
| `quick_setup_manager_arn` | Host management configuration manager ARN. | No |
