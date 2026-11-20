# AWS Naming Helper

Scope: `helper`

Derives every resource name and the governance tags for the AWS modules, so names never collide across Regions,
accounts or module instances. See [Naming and tagging](../../../../docs/naming-and-tagging.md).

## Architecture & Managed Resources

- Data sources only: `aws_caller_identity`, `aws_region`, `aws_partition`.

## Security & Compliance Guardrails

- Validates `application`, `environment` and `name` once for every module.
- Truncated names end with 6 hex characters of the MD5 of the full name.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "naming" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/core/naming?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "orders"
}
```

### Complete Production Example

```hcl
module "naming" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/core/naming?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "orders"
  tags        = { Team = "payments" }
  names = {
    role   = { suffix = "exec", uniqueness = "account" }
    bucket = { suffix = "assets", uniqueness = "global", max_length = 63 }
    lb     = { max_length = 32 }
  }
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | **Required** | Yes |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `name` | Instance name. | `string` | `null` | No |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `region` | Region for names. Null: provider Region. | `string` | `null` | No |
| `names` | Names to derive: suffix, uniqueness (region, account, global), max_length. | `map(object({...}))` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `name` | Base name. | No |
| `names` | Derived names. | No |
| `tags` | Caller and governance tags. | No |
| `governance_tags` | Governance tags. | No |
| `account_id` | Account ID. | No |
| `region` | Region. | No |
| `partition` | Partition. | No |
| `dns_suffix` | Partition DNS suffix. | No |
