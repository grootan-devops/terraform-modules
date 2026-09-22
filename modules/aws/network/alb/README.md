# AWS Application Load Balancer Module

The `alb` module provisions external or internal AWS Application Load Balancers (ALBs) with HTTP-to-HTTPS automated redirection, path-based routing rules, health checks, and HTTP smuggling protections.

## Architecture & Managed Resources

- `aws_lb.this`: Application Load Balancer.
- `aws_lb_target_group.default`: Primary baseline target group.
- `aws_lb_target_group.extra`: Path-routed secondary service target groups.
- `aws_lb_listener.http_redirect`: Port 80 listener issuing 301 redirects to HTTPS 443.
- `aws_lb_listener.https`: Port 443 listener with TLS 1.3/1.2 security policy.
- `aws_security_group.alb`: Load balancer security group controlling inbound traffic.

### Security & Compliance Guardrails

- **HTTP Desync Protection**: `drop_invalid_header_fields = true` hardcoded to mitigate HTTP request smuggling attacks.
- **TLS 1.2+ Enforced**: Listener uses `ELBSecurityPolicy-TLS13-1-2-2021-06`.
- **Accidental Deletion Protection**: `deletion_protection_enabled` defaults to `true`.
- **Mandatory KMS Logging**: Access logs CloudWatch group requires `kms_key_arn`.

---

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.5.0` |
| `aws` | `>= 6.0.0, < 7.0.0` |

---

## Usage Examples

### Minimal Working Example

```hcl
module "alb" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/alb?ref=1.0.0"

  application = "core"
  environment = "prod"
  name        = "gateway"

  vpc_id          = "vpc-0a1b2c3d4e5f67890"
  subnets         = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  kms_key_arn     = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
}
```

### Complete Production Example

```hcl
module "alb" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/alb?ref=1.0.0"

  application = "enterprise"
  environment = "prod"
  name        = "public-alb"

  vpc_id                      = "vpc-0a1b2c3d4e5f67890"
  subnets                     = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  certificate_arn             = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  kms_key_arn                 = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
  internal                    = false
  idle_timeout                = 120
  deletion_protection_enabled = true

  default_target_group_name   = "api"
  default_target_group_port   = 8000
  default_health_check_path   = "/healthz"
  default_health_check_matcher = "200"

  extra_routes = {
    auth = {
      port              = 8001
      priority          = 10
      paths             = ["/auth/*", "/oauth/*"]
      health_check_path = "/auth/health"
    },
    billing = {
      port              = 8002
      priority          = 20
      paths             = ["/billing/*", "/webhooks/*"]
      health_check_path = "/billing/health"
    }
  }

  tags = {
    IngressRole = "PublicEdge"
  }
}
```

---

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | :---: |
| `name` | Name prefix for the ALB. If not provided, will be derived from application and environment. | `string` | `null` | No |
| `application` | Logical application or product name used for resource naming and tagging | `string` | **Required** | Yes |
| `environment` | Deployment environment name (e.g. dev, staging, prod). | `string` | **Required** | Yes |
| `tags` | Additional tags to apply to all resources | `map(string)` | `{}` | No |
| `vpc_id` | VPC ID where the ALB and Target Groups will be deployed | `string` | **Required** | Yes |
| `subnets` | List of public subnets for the ALB | `list(string)` | **Required** | Yes |
| `internal` | If true, the ALB will be internal | `bool` | `false` | No |
| `idle_timeout` | ALB idle timeout in seconds (how long a request can stay open). AWS default is 60. | `number` | `60` | No |
| `security_groups` | A list of security group IDs to assign to the ALB. If empty, a default security group will be created. | `list(string)` | `[]` | No |
| `allowed_cidr_blocks` | Allowed CIDR blocks for ingress to the ALB (only used if default security group is created) | `list(string)` | `["0.0.0.0/0"]` | No |
| `listener_port` | The port for the default HTTP/HTTPS listener | `number` | `80` | No |
| `listener_protocol` | The protocol for the default HTTP/HTTPS listener | `string` | `"HTTP"` | No |
| `default_target_group_name` | The name suffix of the default target group | `string` | `"gateway"` | No |
| `default_target_group_port` | The port of the default target group | `number` | `8000` | No |
| `default_target_group_protocol` | The protocol of the default target group | `string` | `"HTTP"` | No |
| `default_target_group_target_type` | The target type of the default target group (instance, ip, or lambda) | `string` | `"ip"` | No |
| `default_health_check_path` | Health check path for the default target group | `string` | `"/health"` | No |
| `default_health_check_matcher` | HTTP status code matcher for the default target group health check | `string` | `"200"` | No |
| `default_health_check_interval` | Health check interval in seconds for the default target group | `number` | `30` | No |
| `default_health_check_timeout` | Health check timeout in seconds for the default target group | `number` | `5` | No |
| `default_health_check_healthy_threshold` | Healthy threshold count for the default target group health check | `number` | `2` | No |
| `default_health_check_unhealthy_threshold` | Unhealthy threshold count for the default target group health check | `number` | `3` | No |
| `certificate_arn` | ACM certificate ARN for HTTPS listener. When set, HTTP listener redirects to HTTPS. | `string` | `null` | No |
| `extra_routes` | A map of additional routes/services to configure target groups and listener rules for | `map(object({...}))` | `{}` | No |
| `deletion_protection_enabled` | Enable deletion protection on the ALB | `bool` | `true` | No |
| `cloudwatch_logs` | CloudWatch logs configuration for the ALB log group. | `object({...})` | `null` | No |
| `kms_key_arn` | KMS Key ARN used for encrypting ALB access logs and CloudWatch logs. Strictly required. | `string` | **Required** | Yes |

---

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | :---: |
| `default_target_group_arn` | The ARN of the default target group | No |
| `extra_target_group_arns` | Map of extra route names to target group ARNs | No |
| `lb_dns` | DNS endpoint of load balancer | No |
| `security_group_id` | Security group ID of the ALB (managed or first external) | No |
| `lb_arn` | The ARN of the load balancer | No |
| `listener_arn` | The ARN of the primary load balancer listener | No |
