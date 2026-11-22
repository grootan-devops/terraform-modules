# AWS Organizations governance

This is the operator runbook for the organization-level security baseline. It covers the account
model, the policy types, who owns trusted access and delegated administration, how to check the live
organization read-only, and the order in which to roll everything out. The policy catalog and inputs
are in the [`governance/organizations` README](../modules/aws/governance/organizations/README.md).

Nothing in this repository applies anything. An authorized operator runs every step below from a
pipeline or workstation with the right account credentials.

## Account model

| Role | Runs | Owns |
| --- | --- | --- |
| Management account | `governance/organizations`; the `organization_admin` input of `security/cloudtrail`, `security/config`, `security/security-hub`, `security/inspector`, `security/iam-access-analyzer`; the organization trail | The organization, policies and attachments, trusted access, delegated administrator registration, centralized root access |
| Security tooling (delegated administrator) account | `security/security-hub`, `security/inspector`, `security/iam-access-analyzer`, the aggregator and organization rules of `security/config` | Organization-wide service configuration and findings |
| Log archive account | `security/cloudtrail` and `security/config` in bucket-only mode | CloudTrail and AWS Config delivery buckets |
| Every workload account | `security/config` recorder mode (per account, all Regions in use) and the workload modules | Resources and their Config recording |

SCPs and RCPs never apply to the management account; keep workloads out of it. Declarative policies
attached to the root do apply to it.

## Policy types

The supplied snapshot (unverified; check with the commands below) has `SERVICE_CONTROL_POLICY` and
`RESOURCE_CONTROL_POLICY` enabled and everything else disabled.

| Policy type | Snapshot | Target with module defaults | Why |
| --- | --- | --- | --- |
| `SERVICE_CONTROL_POLICY` | Enabled | Enabled | Account protection, region and root restrictions, security service protection, EC2 and network guardrails |
| `RESOURCE_CONTROL_POLICY` | Enabled | Enabled | Transport security and the optional identity perimeter on S3, SQS, KMS, Secrets Manager and STS |
| `DECLARATIVE_POLICY_EC2` | Disabled | Enabled | IMDSv2 defaults, snapshot and AMI block public access, serial console off |
| `S3_POLICY` | Disabled | Enabled | Account-level S3 Block Public Access that member accounts cannot turn off |
| `TAG_POLICY` | Disabled | Enabled | Capitalization of `Application`, `Environment`, `Name`, `ManagedBy` (reporting; enforcement opt-in) |
| `INSPECTOR_POLICY`, `GUARDDUTY_POLICY`, `SECURITYHUB_POLICY`, `BACKUP_POLICY` | Disabled | Not managed | The service modules (`security/inspector`, `security/guardduty`, `security/security-hub`, `storage/backup`) own enablement; one owner per setting. An organization that already has these types enabled can keep them through `organization.additional_policy_types` |
| `AISERVICES_OPT_OUT_POLICY` | Disabled | Opt-in | AI services data use |
| `SECURITYHUB_CSPM_POLICY` | Disabled | Not supported | `hashicorp/aws` 6.73.0 cannot create this policy type; Security Hub CSPM uses central configuration until it can (see the [security-hub README](../modules/aws/security/security-hub/README.md)) |
| `CHATBOT_POLICY`, `BEDROCK_POLICY`, `UPGRADE_ROLLOUT_POLICY`, `NETWORK_SECURITY_DIRECTOR_POLICY` | Disabled | Not enabled | Not part of this baseline |

The module creates a policy, and enables its type, only when the policy has `targets` (plus
`organization.additional_policy_types`). A plan precondition refuses to drop any type that is enabled
today unless `organization.allow_policy_type_disable = true`, because disabling a type detaches every
policy of that type.

### SCP, RCP and declarative policy: which does what

- **SCPs** cap what IAM principals in member accounts can do. They cannot inspect security group rule
  contents, do not affect service-linked roles, and never affect the management account.
- **RCPs** cap what anyone (inside or outside the organization) can do to resources in member accounts,
  for the services that support RCPs. They are Deny-only with `Principal "*"`, and do not cover AWS
  managed KMS keys or service-linked roles.
- **Declarative policies** set a service configuration (EC2, S3, Inspector, GuardDuty, Security Hub,
  Backup) and keep it, including for new accounts and new APIs. Accounts cannot change a governed
  setting.

## Trusted access and delegated administrators

Each service principal has exactly one owner, so two modules never manage the same setting. The
governance module rejects principals owned by a service module.

| Service principal | Owner | Mechanism |
| --- | --- | --- |
| `cloudtrail.amazonaws.com` | `security/cloudtrail` `organization_admin` | Organizations trusted access, then `aws_cloudtrail_organization_delegated_admin_account` |
| `config.amazonaws.com`, `config-multiaccountsetup.amazonaws.com` | `security/config` `organization_admin` | Trusted access and `aws_organizations_delegated_administrator` for both |
| `securityhub.amazonaws.com` | `security/security-hub` `organization_admin` | `aws_securityhub_organization_admin_account` (enables trusted access) |
| `inspector2.amazonaws.com` | `security/inspector` `organization_admin` | `aws_inspector2_delegated_admin_account` per Region (enables trusted access) |
| `access-analyzer.amazonaws.com` | `security/iam-access-analyzer` `organization_admin` | Trusted access and `aws_organizations_delegated_administrator` |
| `iam.amazonaws.com` | `governance/organizations` (`root_access_management`) | Trusted access and `aws_iam_organizations_features` |
| `guardduty.amazonaws.com` | `security/guardduty` `organization_admin` | `aws_guardduty_organization_admin_account` per Region (enables trusted access) |
| `detective.amazonaws.com` | `security/detective` `organization_admin` | `aws_detective_organization_admin_account` per Region (enables trusted access) |
| `backup.amazonaws.com` | `storage/backup` `organization_admin` | Trusted access and `aws_organizations_delegated_administrator` |
| `ssm.amazonaws.com` | `governance/systems-manager` `organization_admin` | Trusted access and `aws_organizations_delegated_administrator` |
| `account.amazonaws.com`, `tagpolicies.tag.amazonaws.com`, others | `governance/organizations` `trusted_access_service_principals` | `aws_organizations_aws_service_access` |

The snapshot reports CloudTrail and IAM Access Analyzer trusted access as enabled. Adopt them with
`import` blocks (shown in those module READMEs) instead of creating them again.

## Read-only checks before any change

Run these from the management account with a read-only role and keep the output with the change record.
None of them modifies anything.

```bash
aws organizations describe-organization
aws organizations list-roots --query 'Roots[].PolicyTypes'
aws organizations list-aws-service-access-for-organization
aws organizations list-delegated-administrators
aws organizations list-policies --filter SERVICE_CONTROL_POLICY
aws organizations list-policies --filter RESOURCE_CONTROL_POLICY
aws iam list-organizations-features
aws controltower list-landing-zones
aws cloudtrail describe-trails --include-shadow-trails
```

From the security tooling account, per Region in use:

```bash
aws securityhub describe-organization-configuration
aws securityhub describe-standards --query 'Standards[].StandardsArn'
aws inspector2 list-delegated-admin-accounts
aws accessanalyzer list-analyzers
aws configservice describe-configuration-recorders
```

For each existing SCP and RCP, list its targets (`aws organizations list-targets-for-policy --policy-id
<id>`) and read it (`aws organizations describe-policy --policy-id <id>`). New policies are combined with
these, so an existing Deny still applies. Validate every new policy document before attaching it:

```bash
aws accessanalyzer validate-policy --policy-type SERVICE_CONTROL_POLICY --policy-document file://scp.json
aws accessanalyzer validate-policy --policy-type RESOURCE_CONTROL_POLICY --policy-document file://rcp.json
```

The rendered documents are in the module's `policies` output.

## Rollout

1. **Adopt the organization.** Add the `import` block and set `organization = { manage = true }`. The plan
   must show only additions to `enabled_policy_types`, with no destroy, replacement or `feature_set`
   change.
2. **Register service administrators.** Apply the `organization_admin` input of each service module in
   the management account. CloudTrail needs trusted access before an organization trail can be created
   through the API.
3. **Configure services.** In every workload account apply `security/config` (recorders first; Security
   Hub controls need Config recording). In the security tooling account apply Security Hub, Inspector,
   Access Analyzer and the Config aggregator and rules. In the management account (or CloudTrail delegated
   administrator) apply the organization trail.
4. **Attach policies to a sandbox OU.** Set each policy's `targets` to a sandbox OU or test account. Watch
   CloudTrail for `AccessDenied` and the EC2 declarative policy account status report, and check that
   pipelines, StackSets and security tooling still work. Add their roles to `exempt_principal_arns` or
   `security_admin_role_arns` where needed.
5. **Widen.** Move targets to production OUs, then the root. Keep at most nine SCPs and four RCPs per
   target; the module enforces that for its own attachments.

## Break-glass

- Keep at least one break-glass role in `exempt_principal_arns`, protected with MFA and monitored.
- A management-account administrator can always detach an SCP or RCP; the module README has the detach
  procedure. Declarative policies can be detached the same way.
- Centralized root access removes long-term root credentials from member accounts. Root-only tasks keep
  working through `sts:AssumeRoot` sessions, which `root_user_restriction` allows. The management account
  root user is outside SCPs; protect it with hardware MFA and no access keys (IAM.6, IAM.9, IAM.4 are
  live-account checks).

## What this cannot do

- Prevent root sign-in in the management account (SCPs do not apply there).
- Inspect security group or NACL rule contents in an SCP (no condition keys). These are detective:
  EC2.13, EC2.14, EC2.19, EC2.21, EC2.53, EC2.54 in Security Hub and the Config rules in `security/config`.
- Guarantee that every resource carries every governance tag. Tag policies standardize keys and values;
  the `REQUIRED_TAGS` Config rule and the Tagging standard detect missing tags.
- Manage Security Hub CSPM through Organizations policies until the provider supports
  `SECURITYHUB_CSPM_POLICY`.

[Documentation index](../README.md#documentation)
