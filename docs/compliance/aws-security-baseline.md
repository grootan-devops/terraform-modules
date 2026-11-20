# AWS security baseline and roadmap

This page sets out the organization-level security baseline the library supports. It covers
which AWS security services are on by default, which are optional, and which are still roadmap.
The per-resource controls each module enforces are in [Security baselines](../security-baselines.md)
and the [controls matrix](aws-security-controls-matrix.md).

## Layers

| Layer | Enforced by | Kind | Where |
| --- | --- | --- | --- |
| Resource configuration | Module defaults, validations and preconditions | Preventive | Every module under `modules/aws/` |
| Organization guardrails | SCPs, RCPs and declarative policies | Preventive | [`modules/aws/governance/organizations`](../../modules/aws/governance/organizations) |
| Configuration monitoring | AWS Config recorders, organization rules and conformance packs | Detective | [`modules/aws/security/config`](../../modules/aws/security/config) |
| Posture management | Security Hub CSPM standards and controls | Detective | [`modules/aws/security/security-hub`](../../modules/aws/security/security-hub) |
| Audit logging | Organization CloudTrail | Detective, evidence | [`modules/aws/security/cloudtrail`](../../modules/aws/security/cloudtrail) |
| Vulnerability management | Amazon Inspector | Detective | [`modules/aws/security/inspector`](../../modules/aws/security/inspector) |
| Access analysis | IAM Access Analyzer | Detective | [`modules/aws/security/iam-access-analyzer`](../../modules/aws/security/iam-access-analyzer) |
| Operational monitoring | CloudWatch alarms, routed to email and webhooks through encrypted SNS topics when enabled | Detective | [`modules/aws/observability/cloudwatch-alarms`](../../modules/aws/observability/cloudwatch-alarms) |
| Static IaC analysis | Trivy, TFLint and `terraform test` | Preventive (in CI) | github-ci-library `scan.yml` and `terraform.yml`, `make verify`, `.github/workflows/pr.yml` |

Security Hub CSPM and AWS Config report posture; they do not certify compliance with any
framework. Organizational and operational requirements also need process and live-account
evidence. Examples are incident response, access reviews, MFA on root users, and contact details.
The [gaps page](compliance-gaps-and-remediation.md) lists each one.

## Service roadmap

Trusted access and delegated administrator support are from the AWS Organizations
[service integration list](https://docs.aws.amazon.com/organizations/latest/userguide/orgs_integrate_services_list.html),
read 2026-11-18. Terraform resources are from the `hashicorp/aws` 6.73.0 provider schema. Pricing
lists billing dimensions only; check each service's pricing page for current rates.

| Service | Protects | Trusted access | Delegated admin | Terraform resources (aws_) | Scope | Default | Module status |
| --- | --- | :---: | :---: | --- | --- | --- | --- |
| AWS Organizations | Account structure, guardrails | n/a | Policy management via resource policy | `organizations_organization`, `_policy`, `_policy_attachment`, `_aws_service_access`, `_delegated_administrator`, `_resource_policy` | Global | Mandatory | Implemented: `governance/organizations` |
| AWS CloudTrail | API audit trail | Yes | Yes | `cloudtrail`, `cloudtrail_organization_delegated_admin_account`, `cloudtrail_event_data_store` | Organization trail, multi-Region | Mandatory | Implemented: `security/cloudtrail` |
| AWS Config | Resource configuration history and rules | Yes | Yes | `config_configuration_recorder`, `_delivery_channel`, `_configuration_recorder_status`, `_configuration_aggregator`, `_organization_managed_rule`, `_organization_conformance_pack`, `_remediation_configuration`, `_retention_configuration` | Per account and Region | Mandatory | Implemented: `security/config` |
| AWS Security Hub CSPM | Posture against standards | Yes | Yes | `securityhub_account`, `_finding_aggregator`, `_organization_admin_account`, `_organization_configuration`, `_configuration_policy`, `_configuration_policy_association` | Home Region with linked Regions | Enable organization-wide | Implemented: `security/security-hub` |
| Amazon Inspector | EC2, ECR, Lambda and code vulnerabilities | Yes | Yes | `inspector2_delegated_admin_account`, `_organization_configuration`, `_enabler`, `_member_association`, `_filter` | Per Region | Enable organization-wide | Implemented: `security/inspector` |
| IAM Access Analyzer | External, internal and unused access | Yes | Yes | `accessanalyzer_analyzer`, `_archive_rule` | External: per Region. Unused access: one Region | Enable organization-wide | Implemented: `security/iam-access-analyzer` |
| Amazon GuardDuty | Threat detection | Yes | Yes | `guardduty_organization_admin_account`, `_organization_configuration`, `_organization_configuration_feature`, `_detector`, `_detector_feature` | Per Region | Enable organization-wide | Implemented: `security/guardduty` (all plans incl. runtime monitoring) |
| Amazon Macie | Sensitive data in S3 | Yes | Yes | `macie2_account`, `_organization_admin_account`, `_organization_configuration`, `_classification_job` | Per Region | Enable selectively (cost scales with data scanned) | Skipped by decision |
| Amazon Detective | Investigation graphs | Yes | Yes | `detective_graph`, `_organization_admin_account`, `_organization_configuration` | Per Region | Recommended | Implemented: `security/detective` |
| Amazon Security Lake | Central security data lake (OCSF) | Yes | Yes | `securitylake_data_lake`, `_aws_log_source`, `_custom_log_source`, `_subscriber` | Per Region with rollup | Optional | Roadmap |
| AWS Audit Manager | Audit evidence collection | Yes | Yes | `auditmanager_account_registration`, `_organization_admin_account_registration`, `_assessment`, `_framework` | Per Region | Not recommended for new setups | Not built: closed to new customers on 30 April 2026; AWS Config conformance packs (`security/config`) are the evidence source |
| AWS Backup | Backup governance | Yes | Yes | `backup_vault`, `_plan`, `_selection`, `_vault_lock_configuration`, `_framework`, `_report_plan` | Per Region | Mandatory for critical resources | Implemented: `storage/backup` |
| AWS Systems Manager | Inventory, patching, secure access | Yes | Yes | `ssm_association`, `_patch_baseline`, `_resource_data_sync`, `_service_setting`, `ssmquicksetup_configuration_manager` (patch policy) | Per Region | Recommended | Implemented: `governance/systems-manager` |
| AWS Firewall Manager | Central WAF, security group and Network Firewall policies | Yes | Yes | `fms_admin_account`, `fms_policy`, `fms_resource_set` | Per Region | Recommended | Skipped by decision |
| AWS WAF | Layer 7 protection | n/a | via Firewall Manager | `wafv2_web_acl`, `_web_acl_association`, `_web_acl_logging_configuration` | Regional or CloudFront | Workload dependent | Implemented: `network/waf` |
| AWS Network Firewall | Stateful network inspection | via Firewall Manager | via Firewall Manager | `networkfirewall_firewall`, `_firewall_policy`, `_rule_group`, `_logging_configuration` | Per VPC | Workload dependent | Roadmap |
| AWS IAM Identity Center | Workforce access, permission sets | Yes | Yes | `ssoadmin_permission_set`, `_account_assignment`, `identitystore_group` | Organization | Recommended (replaces IAM users) | Implemented: `security/identity-center` |
| AWS Control Tower | Landing zone and controls | Yes | No | `controltower_landing_zone`, `_control`, `_baseline` | Organization | Recommended (not deployed here: recorders and trail are per-module) | Out of scope |

## Default enablement decision

- **Mandatory:** Organizations governance, an organization CloudTrail, and AWS Config recording in
  every account and Region in use. Security Hub controls depend on Config recording.
- **On by default for the whole organization:** Security Hub CSPM, Inspector (EC2, ECR, Lambda,
  Lambda code), IAM Access Analyzer (external access in every Region in use, plus unused access).
- **Optional, behind explicit inputs:** data events in CloudTrail, Inspector code repository
  scanning, internal-access analyzers, and the opt-in declarative and RCP policies. These cost money
  or can affect production traffic.
- **Also on by default when deployed:** GuardDuty with every protection plan, AWS Backup for DynamoDB, RDS, EFS and
  EBS, Systems Manager account settings, Session Manager, patching and inventory, and the account baseline (password
  policy, support role, security contact, EBS default encryption, S3 account public access block, IMDSv2 defaults,
  snapshot and AMI block public access, serial console off, ECR enhanced scanning, the API Gateway logging role).
- **Opt-in:** Detective (`behavior_graph.enabled`), VPC block public access, ECR replication and pull-through cache.
- **Skipped by decision:** Macie, Firewall Manager and Audit Manager (closed to new customers). **Optional, not built:** Security Lake, Network Firewall.
- **Per-account IAM hygiene:** [`governance/account-baseline`](../../modules/aws/governance/account-baseline) and the
  opt-in `restrict_iam_user_credentials` SCP; the process side is in the
  [organizational processes register](organizational-processes.md).

## Dependencies and ordering

1. Management account: adopt the organization (`import`), enable trusted access, and register each
   service's delegated administrator through the service modules' `organization_admin` input.
2. Every account: AWS Config recorder and delivery channel. The log-archive account hosts the
   delivery bucket.
3. Delegated administrator (security tooling) account: Security Hub central configuration,
   Inspector organization configuration, Access Analyzer analyzers, Config aggregator and rules.
4. Management account: enable the declarative policy types and attach the policies, sandbox OU first.

Each module README lists its own prerequisites. The full runbook is in
[AWS Organizations governance](aws-organizations-governance.md).

[Compliance documentation](README.md)
