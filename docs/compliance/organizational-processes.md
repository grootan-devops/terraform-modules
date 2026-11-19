# Organizational processes

Some framework requirements cannot be met by Terraform, AWS Config or Security Hub. They need a written
procedure, a named owner, a schedule, and evidence that the procedure ran. This register lists those
processes, the evidence an assessor will ask for, and which module or AWS service produces that evidence.
The codes are the requirement IDs in each framework. CIS AWS Foundations, AWS FSBP and AWS Resource
Tagging are technical benchmarks with no process requirements, so they have no column here.

Keep the evidence where an auditor can read it, for example a controlled document store or an S3 bucket
with Object Lock ([`storage/s3`](../../modules/aws/storage/s3)), with the date, the owner and the outcome of
each run.

## Register

| # | Process | Owner (role) | How often | Evidence to keep | Produced by | NIST SP 800-53 r5 | NIST SP 800-171 r2 | PCI DSS v4.0.1 | CRI Profile v2.2 (CSF 2.0 category) |
| ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Information security policy and roles | Head of security | Review every 12 months | Approved policy with version and date; roles and responsibilities matrix | Document store | PL-1, PL-2, PM-1 | 3.12.4 | 12.1.1, 12.1.2, 12.1.3 | GV.PO, GV.RR |
| 2 | Risk assessment | Head of security with system owners | Every 12 months and after significant change | Risk register with likelihood, impact, owner and treatment; targeted risk analyses | Document store; Security Hub and Inspector findings as input | RA-3 | 3.11.1 | 12.3.1 | ID.RA |
| 3 | Asset inventory | Platform team | Continuous, reviewed quarterly | Inventory of accounts, resources and software; review sign-off | AWS Config ([`security/config`](../../modules/aws/security/config)), Systems Manager inventory ([`governance/systems-manager`](../../modules/aws/governance/systems-manager)) | CM-8 | 3.4.1 | 12.5.1 | ID.AM |
| 4 | Access management and access reviews | System owners | Review every 6 months; remove inactive accounts within 90 days | Review records per account and role, with approvals and removals | IAM Identity Center, IAM Access Analyzer unused-access findings ([`security/iam-access-analyzer`](../../modules/aws/security/iam-access-analyzer)), IAM credential reports | AC-2, AC-2(3), AC-6(7) | 3.1.1, 3.1.5 | 7.2.4, 8.2.6 | PR.AA |
| 5 | Joiners, movers and leavers; screening | HR with system owners | On every change; access removed immediately on leaving | Screening records; access request, change and revocation tickets with timestamps | HR system; IAM Identity Center; CloudTrail ([`security/cloudtrail`](../../modules/aws/security/cloudtrail)) | PS-3, PS-4, PS-5 | 3.9.1, 3.9.2 | 8.2.5, 12.7.1 | GV.RR, PR.AA |
| 6 | Security awareness and role training | Head of security | On hire and every 12 months; program reviewed every 12 months | Training completion records; program review | Learning platform | AT-2, AT-3 | 3.2.1, 3.2.2, 3.2.3 | 12.6.1, 12.6.2, 12.6.3 | PR.AT |
| 7 | Change management | Engineering leads | Every change | Pull request with review, CI results (`make verify`, TFLint and Trivy), Terraform plan, approval and deployment record | Git hosting and CI; CloudTrail | CM-3, CM-4 | 3.4.3, 3.4.4 | 6.5.1, 6.5.2 | PR.PS |
| 8 | Vulnerability management and patching | Platform team | Continuous scanning; critical patches within one month; scan review every 3 months; external scans every 3 months | Scan results, remediation tickets with dates, exceptions with approval | Amazon Inspector ([`security/inspector`](../../modules/aws/security/inspector)), Systems Manager patch compliance, external approved scanning vendor | RA-5, SI-2 | 3.11.2, 3.11.3, 3.14.1 | 6.3.1, 6.3.3, 11.3.1, 11.3.2 | ID.RA, PR.PS |
| 9 | Penetration testing | Head of security | Every 12 months and after significant change | Test scope, report, remediation and retest evidence | Third-party tester | CA-8 | 3.12.1 | 11.4.1, 11.4.2, 11.4.3 | ID.IM |
| 10 | Log review and security monitoring | Security operations | Daily review of security events; alerts handled on arrival | Review log; alert tickets; evidence that failures of critical security controls are detected and handled | Security Hub ([`security/security-hub`](../../modules/aws/security/security-hub)), GuardDuty ([`security/guardduty`](../../modules/aws/security/guardduty)), CloudWatch alarms with routing ([`observability/alarm-routing`](../../modules/aws/observability/alarm-routing)) | AU-6, SI-4 | 3.3.1, 3.3.4, 3.3.5 | 10.4.1, 10.7.2 | DE.CM, DE.AE |
| 11 | Incident response | Security operations | Plan reviewed and tested every 12 months; responders trained | Incident response plan; test or exercise record; incident tickets and post-incident reviews | Amazon Detective ([`security/detective`](../../modules/aws/security/detective)), GuardDuty findings, post-incident reports | IR-2, IR-3, IR-4, IR-6, IR-8 | 3.6.1, 3.6.2, 3.6.3 | 12.10.1, 12.10.2, 12.10.4 | RS.MA, RS.AN, RS.CO |
| 12 | Backup, recovery and contingency | Platform team | Backups continuous; restore test at least every 12 months; plan reviewed every 12 months | Contingency plan; backup job reports; restore test results | AWS Backup and its audit framework ([`storage/backup`](../../modules/aws/storage/backup)) | CP-2, CP-4, CP-9, CP-10 | 3.8.9 | 12.10.1 | PR.DS, RC.RP |
| 13 | Third-party and service provider management | Procurement with head of security | Every 12 months per provider | Provider list, contracts with security responsibilities, due diligence, compliance status (for AWS: reports from AWS Artifact) | Document store; AWS Artifact | SA-9, SR-6 | — | 12.8.1, 12.8.2, 12.8.3, 12.8.4, 12.8.5 | GV.SC |
| 14 | Control assessment and plans of action | Head of security | Continuous monitoring; assessment every 12 months | Assessment reports, open findings with owners and target dates | Security Hub security scores ([`security/security-hub`](../../modules/aws/security/security-hub)), AWS Config rules and conformance packs ([`security/config`](../../modules/aws/security/config)) | CA-2, CA-5, CA-7 | 3.12.1, 3.12.2, 3.12.3 | 12.4.2 (service providers) | GV.OV, ID.IM |
| 15 | Cryptographic key management | Platform team | Key rotation every 12 months (automatic); procedures reviewed every 12 months | Key inventory, key policies, rotation status, procedures for generation, storage, rotation and retirement | AWS KMS ([`security/kms`](../../modules/aws/security/kms)) | SC-12 | 3.13.10 | 3.6.1, 3.7.1, 3.7.4 | PR.DS |
| 16 | Secure development and infrastructure-as-code review | Engineering leads | Every change; developer training every 12 months | Code review records, static analysis results, training records | CI: Trivy, TFLint, `terraform test` | SA-8, SA-11, SA-15 | 3.13.2 | 6.2.1, 6.2.2, 6.2.3, 6.2.4 | PR.PS |

## Minimum content of each procedure

Each procedure should state its purpose, scope, owner, schedule, the steps, how exceptions are approved,
and where the evidence is kept. Specific points the frameworks ask for:

- **Access reviews (4):** cover every account and role, including service and break-glass roles. Record who
  reviewed, what changed and when. Accounts inactive for 90 days are disabled or removed.
- **Leavers (5):** access removal is immediate, and the timestamps in IAM Identity Center or CloudTrail are
  the evidence.
- **Changes (7):** a security impact check happens before approval, and PCI controls are reconfirmed after a
  significant change. In this repository, `MIGRATION.md` and the plan review are part of that record.
- **Patching (8):** critical security patches are installed within one month of release. Exceptions carry a
  documented risk acceptance and an end date.
- **Log review (10):** daily review applies to security events and systems in scope. Alarms only count as
  monitoring once they reach a person, so alarm routing must be enabled with confirmed subscribers.
- **Incident response (11):** the plan names roles, communication paths (including card brands and acquirers
  for PCI), evidence preservation, and recovery steps. The yearly test can be a tabletop exercise.
- **Backups (12):** restore tests prove recovery within the agreed recovery time, not only that backup jobs
  succeed.

## What the modules cannot do

The modules produce the technical evidence: configuration history, findings, logs, scan results and backup
reports. They do not approve risk, train people, screen staff, sign contracts or decide that a test was good
enough. Those steps need a person and a record. An assessor treats a requirement without that record as
not met, even when the technical evidence is complete.

[Compliance documentation](README.md)
