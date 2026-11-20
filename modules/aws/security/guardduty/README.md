# AWS GuardDuty Module

Scope: `account`

Amazon GuardDuty for an organization: the management account call enables trusted access and designates the delegated
administrator; the delegated administrator call runs the detector, every protection plan, the organization
auto-enable configuration, suppression rules and an optional findings export, in every Region of `regions`.

## Architecture & Managed Resources

- `aws_organizations_aws_service_access.this`, `aws_guardduty_organization_admin_account.this`
  (`organization_admin.enabled`): trusted access for `guardduty.amazonaws.com` (this module owns it;
  `governance/organizations` rejects it) and the same administrator in every Region.
- `aws_guardduty_detector.this` (`detector.enabled`): one detector per Region, tagged `<application>-<environment>`.
- `aws_guardduty_detector_feature.this`, `aws_guardduty_organization_configuration.this`,
  `aws_guardduty_organization_configuration_feature.this`: every plan per Region; a plan turned off in `features` is
  set `DISABLED`/`NONE`, never left unmanaged.
- `aws_guardduty_filter.this`: suppression rules `<application>-<environment>-<key>` (64 characters max) per Region.
- `aws_guardduty_publishing_destination.this` (`publishing_destination.enabled`): findings export to your S3 bucket,
  encrypted with `module.encryption` ([`core/encryption`](../../core/encryption)).

Run the management account call first (`detector.enabled = false`), then the delegated administrator call. The
designation enables GuardDuty in the administrator account, so import its detectors (`id = "<detector-id>@<region>"`).
[Amazon Detective](../detective) needs GuardDuty enabled first.

## Security & Compliance Guardrails

- **Detection (GuardDuty.1, .5-.13):** detector enabled in every Region; S3, EKS audit logs, EBS malware, RDS login
  and data risk, Lambda network, Runtime Monitoring with automated agents (EKS add-on, ECS Fargate, EC2) and AI
  Protection on by default, auto-enabled for `ALL` members.
- **Findings export:** GuardDuty needs a customer managed key in the bucket's Region: `kms.create` (key policy grants
  only `kms:GenerateDataKey` to GuardDuty) or `kms.key_id`. `destination_policy_json` and `kms_key_policy_json` hold the
  statements your bucket and key need: GuardDuty scoped by `aws:SourceAccount` and `aws:SourceArn` (this account's
  detectors; Regional principals for opt-in Regions), SSE-KMS with this key only, TLS 1.2. `policies_only = true`
  outputs them before the export exists.
- **Suppression rules:** every filter needs at least one criterion with an operator, so no rule archives everything.
- **Tags (GuardDuty.2, .4):** caller tags first, governance tags last.

Each plan is billed per account and Region; `ALL` and every extra Region multiply the cost.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "guardduty" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/guardduty?ref=<version>"

  environment = "prod"
}
```

### Complete Production Example

```hcl
module "guardduty_management" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/guardduty?ref=<version>"

  environment        = "prod"
  regions            = ["eu-west-1", "us-east-1"]
  detector           = { enabled = false }
  organization_admin = { enabled = true, account_id = module.organization.account_ids["security"] }
}

module "guardduty" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/guardduty?ref=<version>"

  environment            = "prod"
  regions                = ["eu-west-1", "us-east-1"]
  kms                    = { create = true }
  publishing_destination = { enabled = true, bucket_arn = module.findings_bucket.arn, prefix = "guardduty" }
  filters = {
    scanner = { criteria = { type = { equals = ["Recon:EC2/Portscan"] }, "resource.instanceDetails.imageId" = { equals = ["ami-0123456789abcdef0"] } } }
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
| `kms` | Export key: create = true module key, key_id your key (ARN or ID). | `object({...})` | `{}` | No |
| `detector` | Detector; off for the management account call. | `object({...})` | `{}` | No |
| `auto_enable_organization_members` | Organization auto-enable: ALL, NEW or NONE. | `string` | `"ALL"` | No |
| `features` | Protection plans; all on. | `object({...})` | `{}` | No |
| `publishing_destination` | Findings export to S3; policies_only skips the export. | `object({...})` | `{}` | No |
| `filters` | Suppression rules and saved filters by key. | `map(object({...}))` | `{}` | No |
| `organization_admin` | Management account call: trusted access and delegated administrator. | `object({...})` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `detector_ids` | Detector ID by Region. | No |
| `detector_arns` | Detector ARN by Region. | No |
| `publishing_destination_ids` | Findings export ID by Region. | No |
| `kms_key_arn` | Findings export key ARN; null without an export. | No |
| `destination_policy_json` | Bucket policy statements for the findings export; null without one. | No |
| `kms_key_policy_json` | Key policy statement for the findings export; null without one. | No |
