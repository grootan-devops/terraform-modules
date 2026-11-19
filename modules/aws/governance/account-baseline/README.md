# AWS Account Baseline Module

Scope: `account`

Account-wide security settings, applied once per account: the IAM password policy, the AWS Support role, alternate
contacts and the account S3 public access block, plus per-Region settings in every Region of `regions` through the
resource-level `region` argument: EBS encryption by default, EC2 instance metadata defaults, EBS snapshot and AMI
block public access, EC2 serial console access off, optional VPC block public access, the API Gateway CloudWatch Logs
role, ECR registry scanning and optional ECR replication and pull through cache rules.

## Architecture & Managed Resources

- `aws_iam_account_password_policy.this`, `aws_s3_account_public_access_block.this`,
  `aws_account_alternate_contact.this` (SECURITY required; BILLING, OPERATIONS optional).
- `module.support_role` ([`security/iam-role`](../../security/iam-role)): `<application>-<environment>-support-<region>`
  with `AWSSupportAccess`, trusted by `support_role.trusted_principal_arns`.
- Per Region: `aws_ebs_encryption_by_default.this`, `aws_ebs_default_kms_key.this` (only Regions in
  `ebs_default_encryption.kms_key_arns`), `aws_ec2_instance_metadata_defaults.this`,
  `aws_ebs_snapshot_block_public_access.this`, `aws_ec2_image_block_public_access.this`,
  `aws_ec2_serial_console_access.this`, `aws_vpc_block_public_access_options.this`, `aws_api_gateway_account.this`,
  `aws_ecr_registry_scanning_configuration.this`, `aws_ecr_replication_configuration.this`,
  `aws_ecr_pull_through_cache_rule.this`.
- `module.api_gateway_role` ([`security/iam-role`](../../security/iam-role)):
  `<application>-<environment>-apigw-logs-<region>` with `AmazonAPIGatewayPushToCloudWatchLogs`; one role for every
  Region. API Gateway execution logging (`network/api-gateway`) needs it.
- `module.naming` ([`core/naming`](../../core/naming)): names and governance tags.

## Security & Compliance Guardrails

- **Password policy (IAM.7, IAM.10-IAM.17):** 14+ characters, all character classes, 24 remembered, 90-day expiry.
- **Support role (IAM.18)** and **security contact (Account.1)** on by default.
- **EBS (EC2.7, EC2.182):** encryption by default with `aws/ebs` or the Region's key; snapshots `block-all-sharing`.
- **EC2 (EC2.8):** IMDSv2 required with hop limit 2 for new instances; AMI public sharing blocked; serial console off.
- **VPC block public access (EC2.172):** off by default; `enabled = true` sets `mode` (`block-ingress` default).
- **ECR (ECR.1):** enhanced continuous scanning of every repository; billed through Amazon Inspector.
- **S3 (S3.1):** the account public access block is on; set `s3_account_public_access_block.enabled = false` where
  the organization `s3` declarative policy is attached, because it locks the account setting.
- Accounts covered by the organization `ec2` declarative policy reject account-level changes to the same EC2
  settings; turn those switches off there.
- `alternate_contacts.account_id` sets a member account's contacts from the management account; every other switch
  must be off in that call.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "account_baseline" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/governance/account-baseline?ref=<version>"

  environment  = "prod"
  support_role = { trusted_principal_arns = ["arn:aws:iam::123456789012:role/incident-response"] }
  alternate_contacts = {
    security = { name = "Security Team", title = "Security", email_address = "security@example.com", phone_number = "+1 555 0100" }
  }
}
```

### Complete Production Example

```hcl
module "account_baseline" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/governance/account-baseline?ref=<version>"

  environment = "prod"
  regions     = ["eu-west-1", "eu-central-1"]

  support_role = { trusted_principal_arns = [module.incident_role.arn], require_mfa = true }
  alternate_contacts = {
    security   = { name = "Security Team", title = "Security", email_address = "security@example.com", phone_number = "+1 555 0100" }
    operations = { name = "Operations", title = "On-call", email_address = "ops@example.com", phone_number = "+1 555 0102" }
  }

  ebs_default_encryption = {
    kms_key_arns = { "eu-west-1" = module.ebs_key_eu_west_1.arn, "eu-central-1" = module.ebs_key_eu_central_1.arn }
  }
  vpc_block_public_access        = { enabled = true }
  s3_account_public_access_block = { enabled = false }

  ecr_replication = {
    enabled = true
    rules   = [{ destinations = [{ region = "eu-central-1" }], repository_prefixes = ["prod"] }]
  }
  ecr_pull_through_cache_rules = {
    ecr-public = { upstream_registry_url = "public.ecr.aws" }
  }
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | `"platform"` | No |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `regions` | Regions for per-Region settings. Empty: provider Region. | `list(string)` | `[]` | No |
| `permissions_boundary_arn` | Permissions boundary for the module roles. | `string` | `null` | No |
| `password_policy` | IAM account password policy. | `object({...})` | `{}` | No |
| `support_role` | AWS Support role (IAM.18) and who may assume it (empty: this account). | `object({...})` | `{}` | No |
| `alternate_contacts` | Alternate contacts; security is required (Account.1). | `object({...})` | `{}` | No |
| `ebs_default_encryption` | EBS encryption by default; kms_key_arns sets a default key per Region. | `object({...})` | `{}` | No |
| `s3_account_public_access_block` | Account S3 Block Public Access (S3.1). | `object({...})` | `{}` | No |
| `instance_metadata_defaults` | EC2 instance metadata defaults: IMDSv2 required (EC2.8). | `object({...})` | `{}` | No |
| `ebs_snapshot_block_public_access` | EBS snapshot block public access (EC2.182). | `object({...})` | `{}` | No |
| `ami_block_public_access` | AMI block public access. | `object({...})` | `{}` | No |
| `serial_console_access_block` | Keep EC2 serial console access off. | `object({...})` | `{}` | No |
| `vpc_block_public_access` | VPC block public access (EC2.172). | `object({...})` | `{}` | No |
| `api_gateway_logging` | API Gateway account CloudWatch Logs role. | `object({...})` | `{}` | No |
| `ecr_registry_scanning` | ECR registry scanning (ECR.1); ENHANCED uses Amazon Inspector. | `object({...})` | `{}` | No |
| `ecr_replication` | ECR replication rules, applied from every Region. | `object({...})` | `{}` | No |
| `ecr_pull_through_cache_rules` | ECR pull through cache rules by repository prefix. | `map(object({...}))` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `support_role_arn` | AWS Support role ARN; null when disabled. | No |
| `support_role_name` | AWS Support role name; null when disabled. | No |
| `api_gateway_role_arn` | API Gateway CloudWatch Logs role ARN; null when disabled. | No |
| `api_gateway_role_name` | API Gateway CloudWatch Logs role name; null when disabled. | No |
