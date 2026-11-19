# Compliance documentation

These pages show which AWS security controls this library enforces, where, and how strongly.
They are evidence for an assessment, not a certificate: AWS Security Hub CSPM and AWS Config
report posture, and many framework requirements also need process and live-account evidence.

| Question | Read |
| --- | --- |
| What did the audit of every module find, and what changed in 3.0.0? | [Compliance assessment](aws-compliance-assessment.md) |
| Which compliance codes does each resource meet, and which codes are left out and why? | [Resource and compliance map](resource-compliance-map.md) (generated), [map CSV](resource-compliance-map.csv) |
| Which control applies to which resource, with status and evidence? | [Controls matrix](aws-security-controls-matrix.md) (generated), [inventory JSON](aws-compliance-inventory.json), [inventory CSV](aws-compliance-inventory.csv) (generated) |
| How are Organizations policies, trusted access and delegated administrators set up? | [AWS Organizations governance](aws-organizations-governance.md) |
| Which Security Hub CSPM standards are enabled, with which ARNs? | [Security Hub standards](security-hub-standards.md) |
| Which resources have CloudWatch alarms, and which cannot? | [CloudWatch monitoring coverage](cloudwatch-monitoring-coverage.md) |
| Which security services are on by default, and what is next? | [Security baseline and roadmap](aws-security-baseline.md) |
| Which requirements need a procedure and evidence instead of code? | [Organizational processes](organizational-processes.md) |
| What is still open, and what needs a live account? | [Gaps and remediation](compliance-gaps-and-remediation.md) |
| Which scanner findings are suppressed, and why? | [Scanner suppressions](scanner-suppressions.md) |

## How the evidence stays honest

- `aws-compliance-inventory.json` is the source of truth. Each entry names a module, resource and
  security area, with status before and after 3.0.0, the enforcement layer, Security Hub control IDs,
  and evidence as a file plus a regular expression.
- Framework requirement IDs (CIS, NIST SP 800-53 and 800-171, PCI DSS, CRI Profile) are never typed by
  hand. They are joined from `data/securityhub-controls.json`, generated from the AWS Security Hub CSPM
  user guide by `scripts/compliance/fetch_securityhub_controls.py`.
- `tests/test_compliance_inventory.py` runs in `make contracts`. It fails when an evidence pattern no
  longer matches the code, when a control ID is unknown, or when the generated views are stale
  (`python3 scripts/compliance/render_compliance.py` regenerates them).

[Documentation index](../../README.md#documentation)
