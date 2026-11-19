# AWS Security Group Module

Scope: `workload`

A security group with one `aws_vpc_security_group_ingress_rule`/`egress_rule` per source. Every module that needs a
security group composes it.

## Architecture & Managed Resources

- `aws_security_group.this`: `name_prefix` `<application>-<environment>[-<name>][-<purpose>]-`, created before the old
  one is destroyed on replacement.
- `aws_vpc_security_group_ingress_rule.this`, `aws_vpc_security_group_egress_rule.this`: one per map entry;
  `self = true` references the group itself.
- `aws_vpc_security_group_rules_exclusive.this`: the group has only these rules; a rule added outside Terraform is
  removed on the next apply.

## Security & Compliance Guardrails

- **No open ingress (EC2.18, EC2.19):** `0.0.0.0/0` and `::/0` ingress need `allow_public_ingress = true`.
- **No default egress:** the group has no egress rule unless `egress_rules` adds one.
- **One source per rule:** each rule names exactly one CIDR, prefix list, security group or `self`, with a
  description.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "sg" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/security-group?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "bastion"
  vpc_id      = "vpc-0a1b2c3d4e5f67890"
}
```

### Complete Production Example

```hcl
module "sg" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/security-group?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "orders"
  purpose     = "app"
  vpc_id      = "vpc-0a1b2c3d4e5f67890"
  ingress_rules = {
    alb = { description = "HTTP from the ALB", from_port = 8080, to_port = 8080, referenced_security_group_id = "sg-0123456789abcdef0" }
  }
  egress_rules = {
    https = { description = "HTTPS to AWS APIs", from_port = 443, to_port = 443, prefix_list_id = "pl-12345678" }
  }
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | **Required** | Yes |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `name` | Instance name. | `string` | `null` | No |
| `purpose` | Group purpose, appended to the name. | `string` | `null` | No |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `vpc_id` | VPC ID. | `string` | **Required** | Yes |
| `description` | Group description. | `string` | `null` | No |
| `ingress_rules` | Ingress rules by key; one source per rule. | `map(object({...}))` | `{}` | No |
| `egress_rules` | Egress rules by key; one destination per rule. | `map(object({...}))` | `{}` | No |
| `allow_public_ingress` | Allow ingress from 0.0.0.0/0 or ::/0 (internet-facing load balancers only). | `bool` | `false` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `id` | Security group ID. | No |
| `arn` | Security group ARN. | No |
| `name` | Security group name. | No |
| `ingress_rule_ids` | Ingress rule IDs by key. | No |
| `egress_rule_ids` | Egress rule IDs by key. | No |
