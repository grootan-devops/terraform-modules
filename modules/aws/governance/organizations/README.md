# AWS Organizations Governance Module

Scope: `organization`

Organization-wide governance from the management account: trusted access, delegated administrators, centralized root
access, an optional policy-management delegation, an optional adopted organization that owns the enabled policy types,
and a library of service control policies (SCPs), resource control policies (RCPs), declarative, tag and AI opt-out
policies. A library policy exists only while it has `targets`; nothing is created unattached.

## Architecture & Managed Resources

- `aws_organizations_policy.this` and `aws_organizations_policy_attachment.this`: one policy per library entry or
  `custom_policies` entry that has targets, named `<application>-<environment>-<key>` (underscores become hyphens).
  `root` resolves to the root ID; OU IDs and account IDs are attached as given.
- `aws_organizations_organization.this` (`organization.manage = true`): the existing organization, adopted with an
  `import` block in the root module. `enabled_policy_types` = the types of the created policies plus
  `organization.additional_policy_types`; `prevent_destroy`.
- `aws_organizations_aws_service_access.this`, `aws_organizations_delegated_administrator.this`: trusted access and
  delegated administrators for principals no service module owns (`iam.amazonaws.com` is added for root access).
- `aws_iam_organizations_features.this`: centralized root access (`RootCredentialsManagement`, `RootSessions`).
- `aws_organizations_resource_policy.this` (`policy_management_delegation.enabled`): lets one member account manage
  policies of the listed types; enabling or disabling policy types is never delegated.
- `module.naming` ([`core/naming`](../../core/naming)): names and governance tags.

Every service principal has one owner. These are rejected here and belong to the service module's
`organization_admin` input:

| Service principal | Owning module |
| --- | --- |
| `cloudtrail.amazonaws.com` | `security/cloudtrail` |
| `config.amazonaws.com`, `config-multiaccountsetup.amazonaws.com` | `security/config` |
| `securityhub.amazonaws.com` | `security/security-hub` |
| `inspector2.amazonaws.com` | `security/inspector` |
| `access-analyzer.amazonaws.com` | `security/iam-access-analyzer` |
| `guardduty.amazonaws.com` | `security/guardduty` |
| `detective.amazonaws.com` | `security/detective` |
| `backup.amazonaws.com` | `storage/backup` |
| `ssm.amazonaws.com` | `governance/systems-manager` |

Every other principal (`account.amazonaws.com`, `auditmanager.amazonaws.com`, `ram.amazonaws.com`, `sso.amazonaws.com`)
stays here. Inspector, GuardDuty, Security Hub and Backup policies are not offered: the service modules own enablement.

## Security & Compliance Guardrails

- **No lockout:** SCPs and RCPs are deny-only; `FullAWSAccess` and `RCPFullAWSAccess` are never detached and keep one
  attachment slot each (at most 9 SCPs and 4 RCPs per target from this module).
- **Management account:** SCPs and RCPs never apply to it or to service-linked roles; declarative policies do when it
  is in scope.
- **Policy type protection:** with `organization.manage = true` a precondition refuses to disable a currently enabled
  type unless `organization.allow_policy_type_disable = true`; each attachment checks its type is enabled.
- **Document checks:** per-type size limits, SCPs need a statement, RCPs must be `Deny`, `Principal "*"` and
  RCP-supported actions.
- **Exemptions:** `exempt_principal_arns` bypass every SCP; `security_admin_role_arns`, `network_admin_role_arns` and
  `restrict_iam_user_credentials.allowed_principal_arns` only the policies of their domain.
- **S3 account public access block:** locked by the `s3` declarative policy; set
  `account-baseline` `s3_account_public_access_block.enabled = false` in the accounts it covers.
- Roll out on a sandbox OU first, then widen targets. Detach in an emergency with
  `aws organizations detach-policy` (IDs from the `attachments` output), then remove the target in code.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "organization" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/governance/organizations?ref=<version>"

  environment = "prod"
}
```

### Complete Production Example

```hcl
import {
  to = module.organization.aws_organizations_organization.this[0]
  id = "o-abc123def4"
}

module "organization" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/governance/organizations?ref=<version>"

  environment = "prod"

  organization = {
    manage                  = true
    additional_policy_types = ["SERVICE_CONTROL_POLICY", "RESOURCE_CONTROL_POLICY"]
  }

  trusted_access_service_principals = ["account.amazonaws.com"]
  delegated_administrators = {
    iam = { account_id = "222222222222", service_principal = "iam.amazonaws.com" }
  }

  exempt_principal_arns    = ["arn:aws:iam::*:role/break-glass-admin"]
  security_admin_role_arns = ["arn:aws:iam::*:role/security-admin"]

  service_control_policies = {
    deny_leave_organization   = { targets = ["root"] }
    root_user_restriction     = { targets = ["ou-ab12-sandbox1"] }
    protect_security_services = { targets = ["ou-ab12-sandbox1"] }
    protect_audit_buckets     = { targets = ["333333333333"], bucket_arns = [module.cloudtrail.bucket_arn] }
    region_restriction        = { targets = ["ou-ab12-sandbox1"], allowed_regions = ["eu-west-1", "eu-central-1"] }
  }

  resource_control_policies = {
    transport_security = { targets = ["ou-ab12-sandbox1"] }
  }

  declarative_policies = {
    ec2        = { targets = ["ou-ab12-sandbox1"] }
    s3         = { targets = ["root"] }
    tag_policy = { targets = ["root"] }
  }
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | `"platform"` | No |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `organization` | Adopted organization: manage enabled policy types. | `object({...})` | `{}` | No |
| `trusted_access_service_principals` | Service principals to enable trusted access for. | `set(string)` | `[]` | No |
| `delegated_administrators` | Delegated administrators by label: account and service principal. | `map(object({...}))` | `{}` | No |
| `policy_management_delegation` | Delegate policy management of policy_types to one member account. | `object({...})` | `{}` | No |
| `root_access_management` | Centralized root access for member accounts. | `object({...})` | `{}` | No |
| `exempt_principal_arns` | Role or user ARN patterns exempt from every SCP. | `list(string)` | `[]` | No |
| `security_admin_role_arns` | Role ARN patterns exempt from the security SCPs. | `list(string)` | `[]` | No |
| `network_admin_role_arns` | Role ARN patterns exempt from network_guardrails. | `list(string)` | `[]` | No |
| `service_control_policies` | SCP library; a policy exists only while it has targets. | `object({...})` | `{}` | No |
| `resource_control_policies` | RCP library; a policy exists only while it has targets. | `object({...})` | `{}` | No |
| `declarative_policies` | Declarative, tag and AI opt-out policies; each exists only while it has targets. | `object({...})` | `{}` | No |
| `custom_policies` | Extra policies by key: type, description, content, targets. | `map(object({...}))` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `organization_id` | Organization ID. | No |
| `root_id` | Root ID the root target resolves to. | No |
| `enabled_policy_types` | Policy types enabled on the root. | No |
| `policies` | Policies by key: id, arn, name, type. | No |
| `attachments` | Attachments by policy key and target: policy_id, target_id. | No |

## Policy Catalog

| Key | Type | What it does |
| --- | --- | --- |
| `deny_leave_organization` | SCP | Denies `organizations:LeaveOrganization` (Account.2). |
| `region_restriction` | SCP | Denies requests outside `allowed_regions` except global services. |
| `root_user_restriction` | SCP | Denies member root users without `aws:AssumedRoot` (IAM.4, IAM.20). |
| `protect_security_services` | SCP | Denies disabling CloudTrail, Config, GuardDuty, Inspector, Security Hub, Access Analyzer, Macie. |
| `protect_security_kms_keys` | SCP | Denies deletion, disablement and policy or tag changes on keys tagged `SecurityProtection = true` (KMS.3). |
| `protect_audit_buckets` | SCP | Denies deletion and configuration changes on `bucket_arns`. |
| `ec2_guardrails` | SCP | Denies launches without IMDSv2, unencrypted volumes and disabling EBS encryption by default (EC2.3, EC2.7, EC2.8); opt-in public IP and instance type limits. |
| `network_guardrails` | SCP | Limits gateways, peering, transit gateway attachments and VPC endpoints to network admins. |
| `restrict_iam_user_credentials` | SCP | Denies new IAM users, console passwords and access keys outside approved automation. |
| `transport_security` | RCP | Denies non-TLS requests and S3 below TLS 1.2. |
| `identity_perimeter` | RCP | Denies principals and service requests from outside the organization. |
| `ec2` | EC2 declarative | IMDSv2 with hop limit 2, snapshot and AMI block public access, serial console off; opt-in VPC block public access and allowed images (EC2.1, EC2.8, EC2.172, EC2.182). |
| `s3` | S3 declarative | All four S3 Block Public Access settings at account level (S3.1). |
| `tag_policy` | Tag | Governance tag keys and `ManagedBy = Terraform`; `enforced_for` blocks non-compliant tagging. |
| `ai_services_opt_out` | AI opt-out | Opts out of AI service content use by default. |

## Adopting an Existing Organization

Add the `import` block above, set `organization.manage = true` and list in `additional_policy_types` every type that
is enabled today but has no policy here. The plan must show only additions to `enabled_policy_types`, no replacement
and no `feature_set` change. To stop managing the organization, add a `removed` block with `destroy = false` in the
root module and set `manage = false`.
