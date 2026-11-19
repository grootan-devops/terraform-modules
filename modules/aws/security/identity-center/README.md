# AWS IAM Identity Center Module

Scope: `organization`

Permission sets, account assignments and optional identity store groups for the organization's IAM Identity Center
instance. The instance is discovered in the provider Region (`data.aws_ssoadmin_instances`); run it from the
management account or the Identity Center delegated administrator.

## Architecture & Managed Resources

- `aws_ssoadmin_permission_set.this`: one per `permission_sets` key, named `<application>-<environment>-<key>` (32
  characters at most), one-hour sessions by default.
- `aws_ssoadmin_managed_policy_attachment.this`, `aws_ssoadmin_customer_managed_policy_attachment.this`,
  `aws_ssoadmin_permission_set_inline_policy.this` (typed `policy_statements` through
  [`core/policy-document`](../../core/policy-document)), `aws_ssoadmin_permissions_boundary_attachment.this`.
- `aws_ssoadmin_managed_policy_attachments_exclusive.this`,
  `aws_ssoadmin_customer_managed_policy_attachments_exclusive.this`: per permission set, only the listed policies stay
  attached; anything attached outside Terraform is removed on the next apply.
- `aws_identitystore_group.this` and `aws_identitystore_group_membership.this`: optional groups
  (`<application>-<environment>-<key>`) for the built-in identity store; IdP-synced groups come in as `principal_id`.
- `aws_ssoadmin_account_assignment.this`: one per assignment and account, after the permission set's policies.
- `module.naming` ([`core/naming`](../../core/naming)): names and governance tags.

## Security & Compliance Guardrails

- **Short sessions:** `session_duration` defaults to `PT1H` and is limited to `PT1H`-`PT12H`.
- **Least privilege:** `managed_policy_arns` accepts AWS managed policies only; customer managed policies are
  referenced by name and must exist in every assigned account; inline statements need explicit resources.
- **Permissions boundary:** an AWS managed or customer managed boundary per permission set.
- **Group-based access:** assignments take a `groups` key or a group/user `principal_id`; prefer groups.
- `account_ids` must be known at plan (literal IDs or data sources), because they key the assignments.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "identity_center" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/identity-center?ref=<version>"

  environment = "prod"
  permission_sets = {
    readonly = { managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"] }
  }
}
```

### Complete Production Example

```hcl
module "identity_center" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/identity-center?ref=<version>"

  environment = "prod"

  permission_sets = {
    admin = {
      managed_policy_arns  = ["arn:aws:iam::aws:policy/AdministratorAccess"]
      session_duration     = "PT2H"
      permissions_boundary = { enabled = true, customer_managed_policy = { name = "platform-boundary" } }
    }
    readonly = {
      managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
      policy_statements   = [{ sid = "DenySecrets", effect = "Deny", actions = ["secretsmanager:GetSecretValue"], resources = ["*"] }]
    }
  }

  groups = {
    platform-admins = { description = "Platform administrators." }
  }

  account_assignments = {
    admins = { permission_set = "admin", group = "platform-admins", account_ids = ["222222222222", "333333333333"] }
    audit  = { permission_set = "readonly", principal_id = data.aws_identitystore_group.auditors.group_id, account_ids = ["222222222222"] }
  }
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | `"platform"` | No |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `permission_sets` | Permission sets by key: policies, boundary, session duration. | `map(object({...}))` | `{}` | No |
| `groups` | Identity store groups by key: description and member user IDs. | `map(object({...}))` | `{}` | No |
| `account_assignments` | Assignments by key: permission set key, principal and account IDs. | `map(object({...}))` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `instance_arn` | Identity Center instance ARN. | No |
| `identity_store_id` | Identity store ID. | No |
| `permission_set_arns` | Permission set ARNs by key. | No |
| `group_ids` | Identity store group IDs by key. | No |
