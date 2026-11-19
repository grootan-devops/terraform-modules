# AWS compliance assessment

Assessment of every AWS module in this repository against the AWS Security Hub CSPM controls and the
frameworks they map to. Assessed 2026-11-19 at release 3.0.0, against `hashicorp/aws` 6.73.0. The
[controls matrix](aws-security-controls-matrix.md) and [gaps page](compliance-gaps-and-remediation.md) are
generated from the [inventory](aws-compliance-inventory.json) and are the current record. The figures on
this page are a snapshot of that release.

## Scope and method

- **What was assessed:** all 49 AWS module directories of 3.0.0 (the 24 that existed in 2.0.0, rebuilt on one standard, and
  the modules added in 3.0.0), covering every `resource` and `data` block, variable default, validation, output, provider
  constraint and test.
- **Code evidence:** each inventory entry names a module, resource and security area, the configuration
  that is enforced, what is missing, and evidence as a file plus a regular expression. A test fails the
  build when that expression no longer matches the code.
- **Control mapping:** Security Hub control IDs only. CIS v1.2.0, v1.4.0, v3.0.0 and v5.0.0, NIST SP 800-53
  r5 and 800-171 r2, PCI DSS v3.2.1 and v4.0.1, AWS Resource Tagging, AI Security Best Practices and CRI
  Profile v2.2 requirement IDs are joined from the Security Hub CSPM user guide
  ([catalog](data/securityhub-controls.json), 590 controls), never typed by hand.
- **Capability check:** every argument used exists in the provider schema. A control the provider cannot
  express is `NOT_SUPPORTED`, not a fake input.
- **Not done here:** nothing was applied to an AWS account. Live organization state (enabled policy types,
  trusted access, root MFA, account contacts) is `REQUIRES_RUNTIME_VALIDATION`. Use the read-only checks in
  [AWS Organizations governance](aws-organizations-governance.md).

Security Hub CSPM and AWS Config report posture. Passing their checks does not certify compliance with
any framework.

## Where each control is enforced

| Layer | Meaning | Inventory entries |
| --- | --- | ---: |
| `terraform` | The module sets it, validates it or rejects the insecure value at plan time | 577 |
| `organizations` | An SCP, RCP or declarative policy in `governance/organizations` once attached | 30 |
| `config` | An AWS Config rule or conformance pack detects drift | 21 |
| `security_hub` | A Security Hub CSPM control reports it | 12 |
| `runtime` | Only a live-account check can show it | 17 |
| `operational` | Needs a process, a person or another service | 9 |

## Overall result

| Status | Entries |
| --- | ---: |
| `PASS` | 415 |
| `PARTIAL` | 204 |
| `FAIL` | 3 |
| `PROVIDER_MANAGED` | 16 |
| `NOT_SUPPORTED` | 14 |
| `REQUIRES_RUNTIME_VALIDATION` | 9 |
| `NOT_APPLICABLE` | 5 |

In 2.0.0 the same assessment found 88 `PASS`, 125 `PARTIAL` and 96 `FAIL` entries. `PARTIAL` mostly means "secure by
default, the caller may override" or, for opt-in features, "available, off by default"; with no `kms` input a module
uses the AWS managed key, so controls that require a customer managed key are `PARTIAL` until one is set. None of
these figures are a compliance percentage.

## Critical and high-risk findings in 2.0.0, and what 3.0.0 did

| Finding in 2.0.0 | Risk | 3.0.0 |
| --- | --- | --- |
| No organization guardrails, organization trail, Config recording, Security Hub, Inspector or Access Analyzer modules | No preventive or detective layer above the resources | Seven new modules (governance, CloudTrail, Config, Security Hub, Inspector, Access Analyzer, CloudWatch alarms) |
| VPC public and private NACL defaults allowed TCP 22 and 1024–65535 (incl. 3389) from `0.0.0.0/0` | EC2.21, CIS 5.x | Port 22 removed; the ephemeral range excludes 3389 |
| ALB internet-facing by default, `0.0.0.0/0` ingress default, plain-HTTP forwarding without a certificate | Unintended exposure, ELB.1 | `internal` required, ingress default empty, plain HTTP needs `allow_plain_http`, ELB.17 TLS policy by default |
| SQS module could not plan (`kms_master_key_id` conflicts with `sqs_managed_sse_enabled`); no TLS-only policy | Module unusable; SQS.1 | Fixed, TLS-deny on both queues, EventBridge grant scoped by source ARN |
| Step Functions granted `lambda:InvokeFunction` on `*` and logged full execution data | Over-privilege, data exposure | No Lambda statement without ARNs; execution data off by default; KMS grants scoped |
| EKS created an `AmazonS3FullAccess` role unconditionally; default version 1.30 unsupported | Over-privilege, EKS.2 | Role gated and scoped; version required |
| Batch `batch:SubmitJob` on `*` | Over-privilege | Scoped to the module's queues and job definitions |
| Caller tags could overwrite governance tags; no `ManagedBy` tag in 23 modules | Tagging standard, audit | Governance tags merged last, `ManagedBy = "Terraform"` everywhere the schema allows tags |
| RDS password stored in state | Secrets in state | Write-only `password_wo` or a Secrets Manager-managed password; no plain password input |
| API Gateway execution logging off; DynamoDB witness input broken; CloudFront log group in the wrong Region; EventBridge log group without a CMK | Logging gaps and bugs | Fixed |
| Cognito minimum password length 6 | Cognito.3 | 14 by default, validated at least 8 |
| No IaC security scanning, no compliance evidence | Regressions unnoticed | Trivy and TFLint in CI (github-ci-library), `terraform test` for every module; generated compliance views checked by tests |

## Remaining gaps

The [gaps page](compliance-gaps-and-remediation.md) lists every entry that is not `PASS`, with its
remediation, and the [resource and compliance map](resource-compliance-map.md) gives the reason for every
control left out. In short:

- **Out of code:** root MFA and root access keys, per-user IAM MFA and key rotation (detected, and prevented
  for new users by the opt-in `restrict_iam_user_credentials` SCP), Macie (skipped by decision), and the
  [organizational processes](organizational-processes.md).
- **Open in code:**
  - CloudFront.17 (signed URLs with trusted key groups) and CloudFront.5 (legacy S3 logging; the module uses v2
    logging to CloudWatch Logs).
  - EC2.58 and EC2.60 (Systems Manager Incident Manager endpoints) under the opt-in NIST 800-53 standard.
- **AWS limits:** APIGateway.11 fails for every HTTP API custom domain, because API Gateway accepts only `TLS_1_2`
  there; use `integration/api-gateway` (REST) where the control or WAF is required.
- **Opt-in by design:** customer managed keys (the default is the AWS managed key), organization policies, which
  are created only when they have targets, and those that can break workloads (region restriction, identity
  perimeter, network guardrails, VPC block public access, IAM user credentials), CloudTrail data events,
  internal-access analyzers, alarm routing (CloudWatch.15 and .17 and the CIS CloudWatch.1–14 checks pass
  once routing is enabled with confirmed subscribers), and the AWS Config rule set (209 rules, enabled per
  delegated administrator or account).
- **Not built:** AWS Audit Manager, closed to new customers since 30 April 2026. AWS Config rules and
  conformance packs and Security Hub provide the evidence instead.

## Release notes

3.0.0 has no upgrade path from 2.x, because no stack used the 2.x modules. [MIGRATION.md](../../MIGRATION.md)
lists the requirements and interface changes, and the [CHANGELOG](../../CHANGELOG.md) lists every change.

[Compliance documentation](README.md)
