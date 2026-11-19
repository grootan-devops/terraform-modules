# AWS Network Load Balancer Module

Scope: `workload`

A Network Load Balancer with its security group, TCP, UDP, TCP_UDP and TLS listeners, target groups with optional
static targets (instances, IPs or an Application Load Balancer), extra TLS certificates, Elastic IPs, TLS access logs
and an optional PrivateLink endpoint service. Certificates, Elastic IPs, log buckets and ALBs come from other modules;
pass their ARNs and IDs in.

## Architecture & Managed Resources

- `aws_lb.this`: `<application>-<environment>[-<name>]-nlb`, cut to 32 characters with a hash suffix when longer, so
  it never collides with an ALB of the same application.
  Internal by default; `static_ips.allocation_ids` (one per subnet, by index) gives an internet-facing NLB fixed
  addresses through `subnet_mapping`.
- `module.security_group` ([`network/security-group`](../../network/security-group)): always created and attached,
  because an NLB takes security groups only at creation. Its rules are exclusive; add sources through
  `security_group`, never with rules from outside.
- `aws_lb_listener.this` (`listeners`): each forwards to one `target_groups` key; `aws_lb_listener_certificate.this`
  adds `additional_certificate_arns` to TLS listeners.
- `aws_lb_target_group.this` (`target_groups`, named `<base>-nlb-<key>`) and `aws_lb_target_group_attachment.this`
  (`targets`). `alb` target groups are TCP with an HTTP(S) health check and register one ALB on the group port;
  `preserve_client_ip`, `proxy_protocol_v2` and `connection_termination` do not apply to them.
- `aws_vpc_endpoint_service.this`: with `endpoint_service = { enabled = true }`.
- `module.alarms` ([`observability/cloudwatch-alarms`](../../observability/cloudwatch-alarms)): built-in alarms, on by
  default; see [Built-in Alarms](#built-in-alarms).

## Security & Compliance Guardrails

- **TLS (ELB.17, ELB.18):** TLS listeners need a certificate; `ssl_policy` must be on the ELB.17 list (default
  `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09`). TCP, UDP and TCP_UDP listeners pass traffic through unencrypted by
  the load balancer; use TLS listeners where the protocol allows it.
- **Deletion protection (ELB.6), multi-AZ (ELB.13):** on by default; at least two subnets.
- **Exposure:** internal by default; no ingress until sources are listed, and only on listener ports and protocols;
  `0.0.0.0/0` and `::/0` and Elastic IPs only with `internal = false`. PrivateLink traffic is checked against the
  ingress rules (`enforce_security_group_inbound_rules_on_private_link_traffic = "on"`).
- **Egress:** only target and health check ports, to `egress_security_group_ids` or `egress_cidr_blocks`, or to the
  VPC CIDR when neither is set. Target security groups can allow `security_group_id`.
- **PrivateLink:** only the `allowed_principals` ARNs may connect (default none, `*` rejected); connections need
  acceptance by default.
- **Logs:** `access_logs` covers TLS listeners only; NLBs do not log TCP or UDP flows (use VPC flow logs). The bucket
  must be in the load balancer's Region, use SSE-S3 or a customer managed key, and allow
  `delivery.logs.amazonaws.com`.
- **Targets (ELB.21, ELB.22):** target groups and health checks default to TCP; set `protocol = "TLS"` and
  `health_check.protocol = "HTTPS"` where targets serve TLS.
- **Cost:** cross-zone load balancing is on for even spread across AZs; NLB traffic that crosses AZs is billed as
  inter-AZ data transfer. Set `cross_zone_load_balancing = false` to keep traffic in the AZ of the node that receives it.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "nlb" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/nlb?ref=<version>"

  application = "core"
  environment = "prod"
  vpc_id      = module.vpc.vpc_id
  subnet_ids  = module.vpc.private_subnet_ids

  listeners     = { app = { port = 443, target_group = "app" } }
  target_groups = { app = { port = 8443 } }
  security_group = {
    ingress_cidr_blocks       = [module.vpc.cidr_block]
    egress_security_group_ids = [module.ecs.security_group_id]
  }
}
```

### Complete Production Example

```hcl
module "nlb" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/nlb?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "edge"
  internal    = false
  vpc_id      = module.vpc.vpc_id
  subnet_ids  = module.vpc.public_subnet_ids
  static_ips  = { allocation_ids = aws_eip.nlb[*].allocation_id }

  security_group = {
    ingress_cidr_blocks       = ["0.0.0.0/0"]
    egress_security_group_ids = [module.alb.security_group_id, module.ecs.security_group_id]
  }
  listeners = {
    web = { port = 443, target_group = "web" }
    api = {
      port                        = 8443
      protocol                    = "TLS"
      target_group                = "api"
      certificate_arn             = module.certificate.arn
      additional_certificate_arns = [module.legacy_certificate.arn]
      alpn_policy                 = "HTTP2Preferred"
    }
  }
  target_groups = {
    web = { port = 443, target_type = "alb", health_check = { protocol = "HTTPS", path = "/health" }, targets = { alb = { id = module.alb.arn } } }
    api = { port = 8443, protocol = "TLS", health_check = { protocol = "HTTPS", path = "/ready" } }
  }
  access_logs = { enabled = true, bucket = module.log_bucket.name, prefix = "nlb/edge" }
}
```

### Built-in Alarms

The `nlbs` preset of [`observability/cloudwatch-alarms`](../../observability/cloudwatch-alarms) is on by default:
`nlb-lb-<target group>-unhealthy-hosts` and `nlb-lb-<target group>-no-healthy-hosts` (both critical) for each
`target_groups` key. Without `topic_arns` the alarms have no actions; `alarms = { enabled = false }` creates none.

```hcl
module "alarm_routing" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/observability/alarm-routing?ref=<version>"

  environment = "prod"
}

module "nlb" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/nlb?ref=<version>"

  application   = "core"
  environment   = "prod"
  vpc_id        = module.vpc.vpc_id
  subnet_ids    = module.vpc.private_subnet_ids
  listeners     = { app = { port = 443, target_group = "app" } }
  target_groups = { app = { port = 8443 } }

  alarms = {
    topic_arns = module.alarm_routing.topic_arns["eu-west-1"]
    overrides = {
      no_healthy_hosts = { evaluation_periods = 3 }
      unhealthy_hosts  = { enabled = false }
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
| `name` | Load balancer name. | `string` | `null` | No |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `internal` | Internal (true) or internet-facing (false). | `bool` | `true` | No |
| `vpc_id` | VPC ID. | `string` | **Required** | Yes |
| `subnet_ids` | Subnet IDs in at least two AZs. | `list(string)` | **Required** | Yes |
| `ip_address_type` | ipv4 or dualstack. | `string` | `"ipv4"` | No |
| `static_ips` | Elastic IP allocation IDs, one per subnet in subnet_ids order. | `object({...})` | `{}` | No |
| `security_group` | Security group: listener sources, target destinations, extra groups. | `object({...})` | `{}` | No |
| `listeners` | Listeners by key: port, protocol, target group key, TLS settings. | `map(object({...}))` | **Required** | Yes |
| `target_groups` | Target groups by key: port, protocol, target type, health check, static targets. | `map(object({...}))` | **Required** | Yes |
| `access_logs` | TLS listener access logs to an S3 bucket. | `object({...})` | `{}` | No |
| `endpoint_service` | PrivateLink endpoint service. | `object({...})` | `{}` | No |
| `cross_zone_load_balancing` | Cross-zone load balancing. | `bool` | `true` | No |
| `zonal_shift` | Route 53 ARC zonal shift. | `bool` | `true` | No |
| `dns_record_client_routing_policy` | DNS client routing policy. | `string` | `"any_availability_zone"` | No |
| `enforce_security_group_inbound_rules_on_private_link_traffic` | Apply security group ingress to PrivateLink traffic: on or off. | `string` | `"on"` | No |
| `deletion_protection` | Block deletion of the load balancer. | `bool` | `true` | No |
| `alarms` | Built-in CloudWatch alarms: switch, topics by severity, per-alarm overrides. | `object({...})` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `id` | Load balancer ID. | No |
| `arn` | Load balancer ARN. | No |
| `arn_suffix` | ARN suffix for CloudWatch metrics. | No |
| `name` | Load balancer name. | No |
| `dns_name` | DNS name. | No |
| `zone_id` | Route 53 zone ID for alias records. | No |
| `security_group_id` | Load balancer security group ID. | No |
| `listener_arns` | Listener ARNs by key. | No |
| `target_group_arns` | Target group ARNs by key. | No |
| `target_group_arn_suffixes` | Target group ARN suffixes by key, for CloudWatch metrics. | No |
| `endpoint_service_name` | PrivateLink endpoint service name; null when disabled. | No |
| `endpoint_service_id` | PrivateLink endpoint service ID; null when disabled. | No |
| `alarm_arns` | Alarm ARN by key. | No |
| `alarm_names` | Alarm name by key. | No |
