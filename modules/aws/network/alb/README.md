# AWS Application Load Balancer Module

Scope: `workload`

An Application Load Balancer with its security group, HTTPS and HTTP listeners, target groups, listener rules, extra
SNI certificates, S3 access and connection logs and an optional WAF web ACL association. Certificates, web ACLs and
log buckets are other modules; pass their ARNs and names in.

## Architecture & Managed Resources

- `aws_lb.this`: `<application>-<environment>[-<name>]`, cut to 32 characters with a hash suffix when longer.
  `internal` is required: exposure is always an explicit decision.
- `module.security_group` ([`network/security-group`](../../network/security-group)): the listener ports open to
  `ingress_cidr_blocks`, `ingress_security_group_ids` and `ingress_prefix_list_ids`; egress only on the target and
  health check ports, to `egress_cidr_blocks` and `egress_security_group_ids`, or to the VPC CIDR when both are empty.
- `aws_lb_listener.https`: `https_listener.certificate_arn` and `ssl_policy`; `aws_lb_listener_certificate.this` adds
  `additional_certificate_arns` for SNI.
- `aws_lb_listener.http`: a 301 redirect to HTTPS; it forwards plain HTTP only with `http_listener.forward = true`.
- `aws_lb_target_group.this` (`target_groups`, named `<base>-<key>`), `aws_lb_listener_rule.this` (`listener_rules`,
  on every forwarding listener). Listeners forward to `default_target_group`, or answer 404 without one.
- `aws_wafv2_web_acl_association.this`: with `waf = { enabled = true, web_acl_arn = ... }`.

## Security & Compliance Guardrails

- **TLS (ELB.1, ELB.17, ELB.18):** HTTP redirects to HTTPS; `ssl_policy` must be on the ELB.17 list (default
  `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09`, TLS 1.2 and 1.3 with restricted ciphers and post-quantum key exchange,
  the AWS console default).
- **Headers and desync (ELB.4, ELB.12):** invalid header fields are dropped; desync mitigation is `defensive` or
  `strictest`.
- **Deletion protection (ELB.6), multi-AZ (ELB.13):** on by default; at least two subnets.
- **Exposure:** no ingress until sources are listed; `0.0.0.0/0` and `::/0` are rejected unless `internal = false`.
- **WAF (ELB.16):** the module owns the association; `waf.fail_open = false` keeps requests blocked when WAF is
  unreachable.
- **Logs (ELB.5):** `access_logs` writes access and connection logs to a bucket in the load balancer's Region. ALB log
  delivery supports SSE-S3 only, so the bucket must not use SSE-KMS and its policy must allow
  `logdelivery.elasticloadbalancing.amazonaws.com`.
- **Targets (ELB.21, ELB.22):** target groups default to HTTP because most targets do not serve TLS; set
  `protocol = "HTTPS"` where they do and the health check follows.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "alb" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/alb?ref=<version>"

  application    = "core"
  environment    = "prod"
  internal       = true
  vpc_id         = module.vpc.vpc_id
  subnet_ids     = module.vpc.private_subnet_ids
  https_listener = { certificate_arn = module.certificate.arn }
}
```

### Complete Production Example

```hcl
module "alb" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/alb?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "web"
  internal    = false
  vpc_id      = module.vpc.vpc_id
  subnet_ids  = module.vpc.public_subnet_ids

  security_group = {
    ingress_cidr_blocks       = ["0.0.0.0/0"]
    egress_security_group_ids = [module.ecs_service.security_group_id]
  }
  https_listener = {
    certificate_arn             = module.certificate.arn
    additional_certificate_arns = [module.legacy_certificate.arn]
  }
  target_groups = {
    app = { port = 8080 }
    api = { port = 9090, health_check = { path = "/ready" } }
  }
  default_target_group = "app"
  listener_rules = {
    api = { priority = 10, target_group = "api", path_patterns = ["/api/*"] }
  }
  waf         = { enabled = true, web_acl_arn = module.waf.arn }
  access_logs = { enabled = true, bucket = module.log_bucket.name, prefix = "alb/web" }
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | **Required** | Yes |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `name` | Load balancer name. | `string` | `null` | No |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `internal` | Internal (true) or internet-facing (false). | `bool` | **Required** | Yes |
| `vpc_id` | VPC ID. | `string` | **Required** | Yes |
| `subnet_ids` | Subnet IDs in at least two AZs. | `list(string)` | **Required** | Yes |
| `security_group` | Security group: listener sources, target destinations, extra groups. | `object({...})` | `{}` | No |
| `https_listener` | HTTPS listener: port, certificate, extra SNI certificates, TLS policy. | `object({...})` | `{}` | No |
| `http_listener` | HTTP listener: redirects to HTTPS; forward = true serves plain HTTP. | `object({...})` | `{}` | No |
| `target_groups` | Target groups by key: port, protocol, target type, health check. | `map(object({...}))` | `{}` | No |
| `default_target_group` | Target group key for the listener default action. Null: fixed 404. | `string` | `null` | No |
| `listener_rules` | Listener rules by key: priority, target group, path and host conditions. | `map(object({...}))` | `{}` | No |
| `access_logs` | Access and connection logs to an S3 bucket. | `object({...})` | `{}` | No |
| `waf` | REGIONAL WAF web ACL association. | `object({...})` | `{}` | No |
| `idle_timeout` | Idle timeout in seconds (1-4000). | `number` | `60` | No |
| `desync_mitigation_mode` | Desync mitigation: defensive or strictest. | `string` | `"defensive"` | No |
| `deletion_protection` | Block deletion of the load balancer. | `bool` | `true` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `id` | Load balancer ID. | No |
| `arn` | Load balancer ARN, once its listeners exist. | No |
| `arn_suffix` | ARN suffix for CloudWatch metrics. | No |
| `name` | Load balancer name. | No |
| `dns_name` | DNS name. | No |
| `zone_id` | Route 53 zone ID for alias records. | No |
| `security_group_id` | Load balancer security group ID; null when not created. | No |
| `https_listener_arn` | HTTPS listener ARN; null when disabled. | No |
| `http_listener_arn` | HTTP listener ARN; null when disabled. | No |
| `target_group_arns` | Target group ARNs by key, once a listener uses them. | No |
| `target_group_arn_suffixes` | Target group ARN suffixes by key, for CloudWatch metrics. | No |
