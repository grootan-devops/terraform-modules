# AWS IAM Access Analyzer Module

Scope: `account`

IAM Access Analyzer for an organization. The management account call enables trusted access and registers the
delegated administrator; the delegated administrator call creates an organization external access analyzer in every
Region of `regions`, one organization unused access analyzer, an opt-in organization internal access analyzer and
archive rules.

## Architecture & Managed Resources

- `aws_organizations_aws_service_access.this` (`organization_admin.manage_trusted_access`, default on) and
  `aws_organizations_delegated_administrator.this` (`organization_admin.enabled`, management account) for
  `access-analyzer.amazonaws.com`. This module owns that trusted access; `governance/organizations` rejects the
  principal.
- `aws_accessanalyzer_analyzer.external` (`analyzers.enabled`, default): `ORGANIZATION`, one per Region,
  `<application>-<environment>-external`.
- `aws_accessanalyzer_analyzer.unused`: `ORGANIZATION_UNUSED_ACCESS` in `unused_access.region` (IAM is global, one
  analyzer covers every Region), `<application>-<environment>-unused`.
- `aws_accessanalyzer_analyzer.internal` (`internal_access.enabled`): `ORGANIZATION_INTERNAL_ACCESS` in one Region.
- `aws_accessanalyzer_archive_rule.this`: named after the map key; an external rule without `region` lands on every
  external analyzer. Archive rules archive only new findings.

The two calls need different credentials, so a validation rejects `organization_admin` with `analyzers.enabled`.

## Security & Compliance Guardrails

- **External access (IAM.28):** an organization analyzer in every Region of `regions`.
- **Unused access:** on by default, 90-day tracking period (1-365); the owner account cannot be excluded. Use 45 days
  to match IAM.22.
- **Internal access:** opt-in, billed per resource monitored; scope it with `inclusions`.
- **Administrator:** the management account cannot be the delegated administrator.
- **Archive rules:** a comparator on every filter, 1-20 values each, and an analyzer of this call in the rule's Region.
  Add `isPublic = false` to external rules so they never archive public-access findings.
- **Security Hub CSPM integration is provider managed:** findings flow to Security Hub CSPM once both are enabled.
- **Encryption at rest:** AWS owned keys; no customer managed key option.
- **Tags:** analyzers carry caller and governance tags; archive rules have no tags.

Policy validation has no Terraform resource; run it in CI:

```bash
aws accessanalyzer validate-policy --policy-type SERVICE_CONTROL_POLICY --policy-document file://scp.json
aws accessanalyzer check-no-new-access --policy-type IDENTITY_POLICY \
  --existing-policy-document file://current.json --new-policy-document file://proposed.json
```

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

Delegated administrator account, provider Region:

```hcl
module "iam_access_analyzer" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/iam-access-analyzer?ref=<version>"

  environment = "prod"
}
```

### Complete Production Example

```hcl
module "iam_access_analyzer_admin" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/iam-access-analyzer?ref=<version>"
  providers = {
    aws = aws.management
  }

  environment        = "prod"
  organization_admin = { enabled = true, account_id = "210987654321" }
  analyzers          = { enabled = false }
}

import {
  to = module.iam_access_analyzer_admin.aws_organizations_aws_service_access.this[0]
  id = "access-analyzer.amazonaws.com"
}

module "iam_access_analyzer" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/iam-access-analyzer?ref=<version>"
  providers = {
    aws = aws.security
  }

  environment = "prod"
  regions     = ["us-east-1", "eu-west-1"]

  unused_access = { region = "us-east-1", unused_access_age = 45, exclusion_resource_tags = [{ break-glass = "true" }] }
  internal_access = {
    enabled    = true
    region     = "us-east-1"
    inclusions = [{ resource_types = ["AWS::S3::Bucket", "AWS::DynamoDB::Table"] }]
  }

  archive_rules = {
    TrustedAuditAccount = {
      analyzer = "external"
      filters = [
        { criteria = "principal.AWS", eq = ["333333333333"] },
        { criteria = "isPublic", eq = ["false"] },
      ]
    }
  }

  depends_on = [module.iam_access_analyzer_admin]
}
```

The `import` block adopts trusted access that is already enabled.

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | `"platform"` | No |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `regions` | Regions for external access analyzers. Empty: provider Region. | `list(string)` | `[]` | No |
| `analyzers` | Delegated administrator call: organization analyzers and archive rules. | `object({...})` | `{}` | No |
| `organization_admin` | Management account call: trusted access and delegated administrator. | `object({...})` | `{}` | No |
| `unused_access` | Organization unused access analyzer in one Region (null: provider Region). | `object({...})` | `{}` | No |
| `internal_access` | Organization internal access analyzer in one Region (null: provider Region). | `object({...})` | `{}` | No |
| `archive_rules` | Archive rules by rule name: analyzer (external, unused, internal), region, filters. | `map(object({...}))` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `external_analyzer_arns` | External access analyzer ARNs by Region. | No |
| `unused_access_analyzer_arn` | Unused access analyzer ARN; null when off. | No |
| `internal_access_analyzer_arn` | Internal access analyzer ARN; null when off. | No |
| `analyzer_names` | Names of the analyzers this call creates, by kind. | No |
