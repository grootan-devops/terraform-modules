# AWS VPC Module

Scope: `workload`

A VPC from one CIDR: public, private and intra subnets in up to six Availability Zones, NAT gateways, per-tier route
tables and network ACLs, flow logs, VPC endpoints and stripped default resources. Give it `cidr_block` and it computes
the subnets; give it CIDR lists to lay them out yourself.

## Architecture & Managed Resources

- `aws_vpc.this`: `<application>-<environment>[-<name>]`, DNS support and hostnames on.
- `aws_subnet.this`: one subnet per tier and AZ (`az_count`, default 3, or `azs`). Computed layout: the VPC CIDR is
  cut into 16 blocks; private subnet *i* is block *i*, intra subnets are cut from block 14 and public subnets from
  block 15 (a `/16` gives private `/20`s and public and intra `/24`s). Adding an AZ adds subnets without moving the
  others. Computed subnets need a `/16`-`/20` VPC; smaller VPCs set `cidrs`.
- `aws_route_table.this`: one public, one intra and one private table per AZ, created only for tiers with subnets.
  `aws_internet_gateway.this` and the public default route exist only with public subnets.
- `aws_nat_gateway.this`, `aws_eip.nat`: `nat.mode = "single"` (default, one gateway for every private table),
  `"per_az"` (one per AZ, each private table uses its own AZ) or `"none"`.
- `aws_network_acl.this`, `aws_network_acl_rule.this`, `aws_network_acl_association.this`: one ACL per tier with
  subnets. Defaults: public allows the VPC, 80, 443 and the ephemeral ports; private allows the VPC and the ephemeral
  ports; intra allows only the VPC. `nacl_rules` adds rules or replaces a default with the same tier, direction and
  number.
- `aws_flow_log.this`: `ALL` traffic to `module.log_group` ([`observability/log-group`](../../observability/log-group),
  `/aws/vpc/<base>/flow-logs`) with `module.role` ([`security/iam-role`](../../security/iam-role)), or to an S3 bucket
  (`flow_logs = { destination = "s3", s3_bucket_arn = ... }`).
- `aws_vpc_endpoint.this`: gateway endpoints on the private and intra route tables; interface endpoints in one tier
  with `module.endpoint_security_group` ([`network/security-group`](../../network/security-group)): HTTPS from the
  VPC CIDR, no egress.
- `aws_default_security_group.this`, `aws_default_network_acl.this`, `aws_default_route_table.this`: no rules, no
  routes.
- `aws_route.this` (`routes`), `aws_vpc_dhcp_options.this` (`dhcp_options`), `module.encryption`
  ([`core/encryption`](../../core/encryption)).
- `module.alarms` ([`observability/cloudwatch-alarms`](../../observability/cloudwatch-alarms)): built-in NAT gateway
  alarms, on by default; see [Built-in Alarms](#built-in-alarms).

## Security & Compliance Guardrails

- **Default resources stripped (EC2.2):** the default security group, network ACL and route table carry nothing.
- **No public IPs on launch (EC2.15):** every subnet sets `map_public_ip_on_launch = false`.
- **No SSH or RDP from the internet (EC2.21):** no default rule opens 22 or 3389 to `0.0.0.0/0` (the ephemeral range
  is split at 3389), and `nacl_rules` rejects such a rule.
- **No unused network ACLs (EC2.16):** ACLs and route tables exist only for tiers with subnets.
- **Flow logs on (EC2.6):** `ALL` traffic, 365-day log group with deletion protection, encrypted with the module key
  when `kms` is set. The role trusts `vpc-flow-logs.amazonaws.com` with `aws:SourceAccount` and `aws:SourceArn`.
- **Tier isolation:** intra subnets have no internet route; private subnets reach the internet only through NAT.
- **Endpoint policies:** `policy_statements` render the endpoint policy (principal `*` unless set); without them the
  service default (full access, still bound by IAM) applies.

A key passed in `kms.key_id` must allow `logs.<region>.amazonaws.com` (encryption context
`aws:logs:arn = <flow log group ARN>`). An S3 destination bucket needs a policy for `delivery.logs.amazonaws.com`.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "vpc" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/vpc?ref=<version>"

  application = "core"
  environment = "prod"
  cidr_block  = "10.0.0.0/16"
}
```

### Complete Production Example

```hcl
module "vpc" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/vpc?ref=<version>"

  application = "core"
  environment = "prod"
  cidr_block  = "10.0.0.0/16"
  az_count    = 3
  nat         = { mode = "per_az" }
  kms         = { create = true }

  flow_logs = { destination = "s3", s3_bucket_arn = module.log_bucket.arn }

  vpc_endpoints = {
    s3        = { type = "Gateway" }
    "ecr.api" = {}
    "ecr.dkr" = {}
    ssm       = {}
  }
  routes = {
    shared = { destination_cidr_block = "10.100.0.0/16", transit_gateway_id = module.tgw.id }
  }
}

module "lambda" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/compute/lambda?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "orders"
  vpc_id      = module.vpc.vpc_id
  subnet_ids  = module.vpc.private_subnet_ids
}
```

### Built-in Alarms

The `nat_gateways` preset of [`observability/cloudwatch-alarms`](../../observability/cloudwatch-alarms) is on by
default, one entry per NAT gateway keyed by its AZ: `nat-<az>-error-port-allocation` (critical) and
`nat-<az>-packets-drop-rate` (warning, above 0.01 % of packets in). `nat.mode = "single"` gives two alarms,
`"per_az"` two per AZ and `"none"` none. Without `topic_arns` the alarms have no actions; `alarms = { enabled = false }`
creates none.

```hcl
module "alarm_routing" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/observability/alarm-routing?ref=<version>"

  environment = "prod"
}

module "vpc" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/vpc?ref=<version>"

  application = "core"
  environment = "prod"
  cidr_block  = "10.0.0.0/16"
  nat         = { mode = "per_az" }

  alarms = {
    topic_arns = module.alarm_routing.topic_arns["eu-west-1"]
    overrides = {
      error_port_allocation = { threshold = 10 }
      packets_drop_rate     = { enabled = false }
    }
  }
}
```

`overrides` takes the preset's alarm keys and fields (`enabled`, `threshold`, `evaluation_periods`,
`datapoints_to_alarm`, `period`, `severity`); a field left out keeps the preset default.

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | **Required** | Yes |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `name` | VPC name. | `string` | `null` | No |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `cidr_block` | VPC IPv4 CIDR. | `string` | **Required** | Yes |
| `az_count` | Availability Zones to use (1-6). | `number` | `3` | No |
| `azs` | Availability Zone names. Empty: the first az_count zones. | `list(string)` | `[]` | No |
| `public_subnets` | Public tier: enabled, CIDRs (one per AZ; empty: computed). | `object({...})` | `{}` | No |
| `private_subnets` | Private tier: enabled, CIDRs (one per AZ; empty: computed). | `object({...})` | `{}` | No |
| `intra_subnets` | Intra tier (no internet route): enabled, CIDRs (one per AZ; empty: computed). | `object({...})` | `{}` | No |
| `nat` | NAT gateways: single, per_az or none. | `object({...})` | `{}` | No |
| `nacl_rules` | Extra network ACL rules by key; same tier, direction and number replaces a default. | `map(object({...}))` | `{}` | No |
| `routes` | Extra routes by key: tiers, one destination, one target. | `map(object({...}))` | `{}` | No |
| `flow_logs` | VPC flow logs: destination cloudwatch or s3, traffic type, aggregation interval. | `object({...})` | `{}` | No |
| `cloudwatch_logs` | Flow log group (destination cloudwatch). | `object({...})` | `{}` | No |
| `kms` | Encryption: {} AWS managed key, create = true module key, key_id your key (ARN or ID). | `object({...})` | `{}` | No |
| `iam_role` | Flow log role: extend it or bring your own. | `object({...})` | `{}` | No |
| `vpc_endpoints` | VPC endpoints by service (s3, ecr.api, ssm...): type, subnet tier, private DNS, policy. | `map(object({...}))` | `{}` | No |
| `dhcp_options` | Custom DHCP option set. | `object({...})` | `{}` | No |
| `alarms` | Built-in CloudWatch alarms: switch, topics by severity, per-alarm overrides. | `object({...})` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `vpc_id` | VPC ID. | No |
| `vpc_arn` | VPC ARN. | No |
| `cidr_block` | VPC CIDR. | No |
| `azs` | Availability Zones in subnet order. | No |
| `public_subnet_ids` | Public subnet IDs, one per AZ. | No |
| `private_subnet_ids` | Private subnet IDs, one per AZ. | No |
| `intra_subnet_ids` | Intra subnet IDs, one per AZ. | No |
| `public_subnet_cidrs` | Public subnet CIDRs. | No |
| `private_subnet_cidrs` | Private subnet CIDRs. | No |
| `intra_subnet_cidrs` | Intra subnet CIDRs. | No |
| `public_route_table_ids` | Public route table IDs. | No |
| `private_route_table_ids` | Private route table IDs, one per AZ. | No |
| `intra_route_table_ids` | Intra route table IDs. | No |
| `nat_gateway_ids` | NAT gateway IDs. | No |
| `nat_public_ips` | NAT gateway public IPs. | No |
| `vpc_endpoint_ids` | VPC endpoint IDs by service key. | No |
| `vpc_endpoint_security_group_id` | Interface endpoint security group ID; null without one. | No |
| `flow_log_id` | Flow log ID; null when disabled. | No |
| `log_group_name` | Flow log group name; null unless cloudwatch. | No |
| `log_group_arn` | Flow log group ARN; null unless cloudwatch. | No |
| `kms_key_arn` | Key ARN in use; null for the AWS managed key. | No |
| `alarm_arns` | Alarm ARN by key. | No |
| `alarm_names` | Alarm name by key. | No |
