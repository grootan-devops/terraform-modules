# AWS Inspector Module

Scope: `account`

Amazon Inspector (v2) for an organization, in every Region of `regions`. The management account call designates the
delegated administrator; the delegated administrator call sets the organization auto-enable configuration, activates
scanning on itself and on existing member accounts, and manages organization-wide suppression rules.

## Architecture & Managed Resources

- `aws_inspector2_delegated_admin_account.this` (`organization_admin.enabled`, management account): one per Region.
  The designation also enables trusted access for `inspector2.amazonaws.com`.
- `aws_inspector2_organization_configuration.this` (`organization_configuration.enabled`, default): auto-enables the
  selected scan types for accounts that join later.
- `aws_inspector2_enabler.admin` (`activate_admin_account`): the same scan types on the administrator account.
- `aws_inspector2_member_association.this` and `aws_inspector2_enabler.members`: existing accounts in
  `member_account_ids`, per account and Region.
- `aws_inspector2_filter.this`: suppression rules `<application>-<environment>-<key>`, per Region.

Every resource uses the resource-level `region` argument. The two calls need different credentials, so a validation
rejects `organization_admin` with `organization_configuration.enabled`. `auto_enable` covers only accounts that join
later; cover existing accounts with `member_account_ids` or an `INSPECTOR_POLICY` from
[`governance/organizations`](../../governance/organizations).

## Security & Compliance Guardrails

- **Scan types (Inspector.1-4):** EC2, ECR, Lambda standard and Lambda code scanning on by default; code repository
  scanning opt-in. Lambda code scanning needs Lambda standard scanning. ECR activation makes Inspector the enhanced
  scanner of the registry; scan on push is set in Amazon ECR (ECR.1).
- **Administrator:** the management account cannot be the administrator, and the administrator cannot be a member.
- **Suppression rules:** at least one criterion each, valid severity, finding type and comparison values, at most 10
  entries per criterion.
- **Security Hub CSPM integration is provider managed:** findings flow to Security Hub CSPM once it is enabled (Code
  Security findings excepted).
- **IAM:** Inspector uses the `AWSServiceRoleForAmazonInspector2` service-linked role; the module creates no role.
- **Encryption at rest:** AWS owned keys. A customer managed key for Lambda code snippets is set with the
  `UpdateEncryptionKey` API, which has no Terraform resource.
- **Provider gaps (6.73.0):** AMI scanning, CIS scan configurations and EC2 scan mode have no Terraform argument.
- **Destroy:** removing an enabler deactivates scanning; disabling Inspector deletes its findings.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

Delegated administrator account, provider Region:

```hcl
module "inspector" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/inspector?ref=<version>"

  environment = "prod"
}
```

### Complete Production Example

```hcl
module "inspector_admin" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/inspector?ref=<version>"
  providers = {
    aws = aws.management
  }

  environment                = "prod"
  regions                    = ["us-east-1", "eu-west-1"]
  organization_admin         = { enabled = true, account_id = "210987654321" }
  organization_configuration = { enabled = false }
}

module "inspector" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/inspector?ref=<version>"
  providers = {
    aws = aws.security
  }

  environment        = "prod"
  regions            = ["us-east-1", "eu-west-1"]
  member_account_ids = ["111111111111", "222222222222"]

  filters = {
    sandbox-low = {
      reason        = "Reviewed quarterly"
      severity      = [{ value = "LOW" }, { value = "INFORMATIONAL" }]
      resource_tags = [{ key = "Environment", value = "sandbox" }]
    }
  }

  depends_on = [module.inspector_admin]
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | `"platform"` | No |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `regions` | Regions to manage. Empty: provider Region. | `list(string)` | `[]` | No |
| `organization_admin` | Management account call: delegated administrator in every Region. | `object({...})` | `{}` | No |
| `organization_configuration` | Delegated administrator call: auto-enabled scan types and administrator activation. | `object({...})` | `{}` | No |
| `member_account_ids` | Existing accounts to associate and activate. | `list(string)` | `[]` | No |
| `filters` | Suppression rules by key, in every Region. | `map(object({...}))` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `member_associations` | Member relationship status by account_id/region. | No |
| `filter_arns` | Suppression rule ARNs by key, then Region. | No |
