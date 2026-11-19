# AWS Detective Module

Scope: `account`

Amazon Detective for an organization: the management account call designates the Detective administrator in every
Region of `regions`; the administrator account call manages the organization behavior graph, auto-enable for new
accounts and existing member accounts in the same Regions.

Detective depends on GuardDuty: enable [GuardDuty](../guardduty) in the account and Region first, and for at least
48 hours, before enabling Detective; Detective ingests GuardDuty findings as a core data source.

## Architecture & Managed Resources

- `aws_detective_organization_admin_account.this` (`organization_admin.enabled`): the same administrator in every
  Region. The designation also registers the delegated administrator for `detective.amazonaws.com`, enables trusted
  access and creates the organization behavior graph.
- `aws_detective_graph.this` (`behavior_graph.enabled`): one graph per Region, tagged `<application>-<environment>`.
  The administrator call adopts the graph the designation created (or import it by its ARN first).
- `aws_detective_organization_configuration.this`: `auto_enable` for accounts that join later.
- `aws_detective_member.this`: existing organization accounts (`member_accounts`: account ID => root email) in every
  Region; Detective sends them no invitation.

Run the management account call first, then the administrator call.

## Security & Compliance Guardrails

- **Encryption is provider managed:** Detective encrypts graph data with AWS owned keys at rest and in transit (TLS
  1.2); it offers no customer managed key.
- **Least privilege:** the management account cannot be the administrator, and the administrator is never its own
  member.
- **Tags:** caller tags first, governance tags last.
- **Destroy:** removing a designation or a graph deletes that Region's behavior graph and its data.
- **Provider gaps:** the optional data source packages (`UpdateDatasourcePackages`: EKS audit logs, AWS security
  findings) and the Amazon Security Lake integration have no Terraform resource; manage them in the console or API.

Detective is billed per GB ingested per account and Region; each Region in `regions` adds a graph.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "detective" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/detective?ref=<version>"

  environment    = "prod"
  behavior_graph = { enabled = true }
}
```

### Complete Production Example

```hcl
module "detective_management" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/detective?ref=<version>"

  environment        = "prod"
  regions            = ["eu-west-1", "us-east-1"]
  organization_admin = { enabled = true, account_id = module.organization.account_ids["security"] }
}

module "detective" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/detective?ref=<version>"

  environment = "prod"
  regions     = ["eu-west-1", "us-east-1"]
  behavior_graph = {
    enabled         = true
    member_accounts = { "210987654321" = "aws-workloads@example.com" }
  }

  depends_on = [module.guardduty]
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | `"platform"` | No |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `regions` | Regions to manage. Empty: provider Region. | `list(string)` | `[]` | No |
| `behavior_graph` | Administrator call: behavior graph, auto-enable, members (account ID => root email). | `object({...})` | `{}` | No |
| `organization_admin` | Management account call: Detective administrator. | `object({...})` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `graph_arns` | Behavior graph ARN by Region. | No |
| `member_ids` | Member ID by account_id/region key. | No |
| `member_statuses` | Member status by account_id/region key. | No |
