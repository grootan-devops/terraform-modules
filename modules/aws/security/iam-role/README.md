# AWS IAM Role Module

Scope: `workload`

An IAM role with a trust policy, an inline policy, managed policy attachments, an optional permissions boundary and an
optional instance profile. Every module that needs a role composes it.

## Architecture & Managed Resources

- `aws_iam_role.this`: named `<application>-<environment>[-<name>][-<purpose>]-<region>`.
- `aws_iam_role_policy.this`: inline policy from `policy_statements` and `policy_documents`.
- `aws_iam_role_policy_attachment.this`: one per `managed_policy_arns` entry.
- `aws_iam_role_policies_exclusive.this`, `aws_iam_role_policy_attachments_exclusive.this`: the role has only these
  policies; anything attached outside Terraform is removed on the next apply.
- `aws_iam_instance_profile.this`: when `instance_profile.enabled`.

## Security & Compliance Guardrails

- **No full admin (IAM.1):** `*` actions on `*` resources are rejected.
- **No wildcard trust:** `trust.aws_principals` cannot be `*`.
- **Confused deputy:** service modules pass `aws:SourceAccount`/`aws:SourceArn` in `trust.conditions`.
- **Region in the name:** IAM is account-global; the same application in two Regions gets two roles.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "role" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/iam-role?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "worker"
  trust       = { services = ["ec2.amazonaws.com"] }
}
```

### Complete Production Example

```hcl
module "role" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/iam-role?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "orders"
  purpose     = "pod"
  trust = {
    services = ["pods.eks.amazonaws.com"]
    actions  = ["sts:AssumeRole", "sts:TagSession"]
  }
  managed_policy_arns      = ["arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"]
  permissions_boundary_arn = "arn:aws:iam::111122223333:policy/workload-boundary"
  policy_statements = [{
    sid       = "ReadOrders"
    actions   = ["dynamodb:GetItem", "dynamodb:Query"]
    resources = ["arn:aws:dynamodb:eu-west-1:111122223333:table/core-prod-orders"]
  }]
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | **Required** | Yes |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `name` | Instance name. | `string` | `null` | No |
| `purpose` | Role purpose, appended to the name. | `string` | `null` | No |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `role_name` | Exact role name. Null: derived. | `string` | `null` | No |
| `include_region_in_name` | Append the Region to the derived name. | `bool` | `true` | No |
| `description` | Role description. | `string` | `null` | No |
| `trust` | Who may assume the role. | `object({...})` | **Required** | Yes |
| `managed_policy_arns` | Managed policies to attach. | `list(string)` | `[]` | No |
| `policy_statements` | Inline policy statements. | `list(object({...}))` | `[]` | No |
| `policy_documents` | Policy JSON documents merged into the inline policy. | `list(string)` | `[]` | No |
| `permissions_boundary_arn` | Permissions boundary ARN. | `string` | `null` | No |
| `path` | IAM path. | `string` | `"/"` | No |
| `max_session_duration` | Max session duration (3600-43200 s). | `number` | `3600` | No |
| `instance_profile` | Create an instance profile. | `object({...})` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `arn` | Role ARN. | No |
| `name` | Role name. | No |
| `id` | Role unique ID. | No |
| `instance_profile_arn` | Instance profile ARN. | No |
| `instance_profile_name` | Instance profile name. | No |
| `policy_json` | Inline policy JSON; null without one. | No |
| `trust_policy_json` | Trust policy JSON. | No |
