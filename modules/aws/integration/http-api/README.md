# AWS API Gateway HTTP API Module

Scope: `workload`

An API Gateway v2 HTTP API with its auto-deployed `$default` stage, Lambda, HTTP and private (VPC link) integrations,
JWT and Lambda authorizers, routes, CORS, stage and route throttling, JSON access logs, Lambda invoke permissions, an
optional VPC link with its security group, an optional Regional custom domain with mutual TLS, and an optional
customer managed key for the logs. Functions, user pools, load balancers and certificates are other modules; pass
their ARNs in.

## Architecture & Managed Resources

- `aws_apigatewayv2_api.this`: `<application>-<environment>[-<name>]`, protocol `HTTP`, `ipv4` or `dualstack`, with
  CORS when `cors.enabled`.
- `aws_apigatewayv2_stage.this`: the `$default` stage with `auto_deploy`, access logs, default throttling and one
  route setting per route with `throttling`.
- `aws_apigatewayv2_integration.this`, `aws_apigatewayv2_authorizer.this`, `aws_apigatewayv2_route.this`: one per key
  of `integrations`, `authorizers` and `routes`; routes name their integration and authorizer by key.
- `aws_lambda_permission.integrations`, `aws_lambda_permission.authorizers`: one per Lambda integration and Lambda
  authorizer.
- `module.access_log_group` ([`observability/log-group`](../../observability/log-group)):
  `/aws/apigateway/<api>/default/access`.
- `aws_apigatewayv2_vpc_link.this` and `module.vpc_link_security_group`
  ([`network/security-group`](../../network/security-group)): optional, for `private` integrations.
- `aws_apigatewayv2_domain_name.this`, `aws_apigatewayv2_api_mapping.this`: optional Regional custom domain.
- `module.encryption` ([`core/encryption`](../../core/encryption)): service encryption, module key or your key for the
  logs.
- `module.alarms` ([`observability/cloudwatch-alarms`](../../observability/cloudwatch-alarms)): built-in alarms, on by
  default; see [Built-in Alarms](#built-in-alarms).

## Security & Compliance Guardrails

- **Authorization (APIGateway.8):** every route sets `authorizer` (JWT or Lambda) or an explicit
  `authorization = "NONE"` or `"AWS_IAM"`; a route with neither fails the plan. `NONE` routes fail APIGateway.8.
  `authorization_scopes` only on JWT routes. For Cognito, set `issuer = "https://${module.auth.endpoint}"` (the
  [`security/cognito`](../../security/cognito) `endpoint` output is the user pool endpoint) and `audience` to its
  client IDs.
- **Access logs (APIGateway.9):** always on, JSON with request ID, extended request ID, IP, time, method, route key,
  path, status, protocol, response length, latencies, integration error, authorizer error and user agent; 365 days,
  deletion protection, the module key when set. HTTP APIs have no execution logs (APIGateway.1 covers REST and
  WebSocket stages only). The deploying principal needs `logs:CreateLogDelivery` and the related log delivery
  permissions; no account-level role is used.
- **Private integrations (APIGateway.10):** `tls_server_name` is required, so API Gateway connects to the listener over
  TLS. The VPC link group has no ingress and egress only to `egress_security_group_ids` and `egress_cidr_blocks`; its
  rules are exclusive. Allow the group on the load balancer (`ingress_security_group_ids`).
- **TLS (APIGateway.11):** HTTP APIs and their custom domains accept only `TLS_1_2` (TLS 1.2 and 1.3); an HTTP API
  cannot be mapped to a domain with a `SecurityPolicy_*` policy, so APIGateway.11 fails HTTP API domains by design.
  Suppress that finding, or use [`integration/api-gateway`](../api-gateway) where an enhanced policy is required. A
  custom domain turns the execute-api endpoint off; `domain.mutual_tls` adds client certificate checks from an S3
  truststore. `http` integrations take `https://` URIs only.
- **Invoke permissions:** principal `apigateway.<dns_suffix>`, on the alias when the ARN is qualified; integrations
  limited to `<execution_arn>/*`, Lambda authorizers to `<execution_arn>/authorizers/<authorizer-id>`.
- **Throttling:** the stage defaults to 1,000 requests per second with a 2,000 burst. The rate is a tenth of the
  default Regional account quota (10,000) that every API shares, so one API cannot starve the others; raise it per
  API or per route.
- **CORS:** explicit origins; `allow_credentials` with `*` is rejected.
- **WAF:** HTTP APIs cannot be associated with a WAF web ACL (APIGateway.4 covers REST stages). Use
  [`integration/api-gateway`](../api-gateway) with `waf`, or put CloudFront with a web ACL in front.

A key passed in `kms.key_id` must allow `logs.<region>.amazonaws.com` (encryption context
`aws:logs:arn = <log group ARN>`).

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "api" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/integration/http-api?ref=<version>"

  application = "core"
  environment = "prod"

  integrations = {
    orders = { type = "lambda", lambda = { function_arn = module.orders.alias_arn } }
  }

  routes = {
    "$default" = { integration = "orders", authorization = "AWS_IAM" }
  }
}
```

### Complete Production Example

```hcl
module "api" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/integration/http-api?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "public"
  kms         = { create = true }
  cors        = { enabled = true, allow_origins = ["https://app.example.com"] }
  throttling  = { burst_limit = 500, rate_limit = 250 }

  integrations = {
    orders = { type = "lambda", lambda = { function_arn = module.orders.alias_arn } }
    legacy = { type = "private", listener_arn = module.alb.https_listener_arn, tls_server_name = "legacy.internal.example.com" }
  }

  authorizers = {
    cognito = { jwt = { issuer = "https://${module.auth.endpoint}", audience = [module.auth.client_ids["web"]] } }
    partner = { lambda = { function_arn = module.partner_auth.alias_arn } }
  }

  routes = {
    "GET /orders"          = { integration = "orders", authorizer = "cognito", authorization_scopes = ["orders/read"] }
    "POST /orders"         = { integration = "orders", authorizer = "cognito", throttling = { burst_limit = 100, rate_limit = 50 } }
    "ANY /legacy/{proxy+}" = { integration = "legacy", authorizer = "partner" }
    "GET /health"          = { integration = "orders", authorization = "NONE" }
  }

  vpc_link = {
    enabled        = true
    vpc_id         = module.vpc.vpc_id
    subnet_ids     = module.vpc.private_subnet_ids
    security_group = { egress_security_group_ids = [module.alb.security_group_id] }
  }

  domain = {
    enabled         = true
    name            = "api.example.com"
    certificate_arn = module.certificate.arn
  }
}

module "zone" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/route53?ref=<version>"

  application = "core"
  environment = "prod"
  zone_name   = "example.com"

  records = {
    api = { name = "api", type = "A", alias = { name = module.api.domain_target_name, zone_id = module.api.domain_zone_id } }
  }
}
```

### Built-in Alarms

The `http_apis` preset of [`observability/cloudwatch-alarms`](../../observability/cloudwatch-alarms) is on by default,
on the API ID and the `$default` stage: `httpapi-api-5xx-rate` (critical, above 5 %) and `httpapi-api-latency-p99`
(above 2500 ms). None is opt-in. Without `topic_arns` the alarms have no actions; `alarms = { enabled = false }`
creates none.

```hcl
module "alarm_routing" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/observability/alarm-routing?ref=<version>"

  environment = "prod"
}

module "api" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/integration/http-api?ref=<version>"

  application = "core"
  environment = "prod"

  alarms = {
    topic_arns = module.alarm_routing.topic_arns["eu-west-1"]
    overrides = {
      server_error_rate = { threshold = 2 }
      latency_p99       = { enabled = false }
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
| `name` | Instance name. | `string` | `null` | No |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `description` | API description. | `string` | `null` | No |
| `ip_address_type` | ipv4 or dualstack. | `string` | `"ipv4"` | No |
| `integrations` | Integrations by key: lambda, http or private. | `map(object({...}))` | `{}` | No |
| `authorizers` | Authorizers by key: jwt or lambda. | `map(object({...}))` | `{}` | No |
| `routes` | Routes by route key: integration, authorizer or authorization, scopes, throttling. | `map(object({...}))` | `{}` | No |
| `cors` | CORS configuration. | `object({...})` | `{}` | No |
| `throttling` | Stage default throttling. | `object({...})` | `{}` | No |
| `detailed_metrics` | Per-route CloudWatch metrics. | `bool` | `false` | No |
| `kms` | Log encryption: {} CloudWatch Logs service encryption, create = true module key, key_id your key (ARN or ID). | `object({...})` | `{}` | No |
| `cloudwatch_logs` | Access log group and format. | `object({...})` | `{}` | No |
| `vpc_link` | VPC link for private integrations. | `object({...})` | `{}` | No |
| `domain` | Regional custom domain mapped to the stage. | `object({...})` | `{}` | No |
| `alarms` | Built-in CloudWatch alarms: switch, topics by severity, per-alarm overrides. | `object({...})` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `id` | HTTP API ID (ApiId dimension). | No |
| `arn` | HTTP API ARN. | No |
| `name` | HTTP API name. | No |
| `api_endpoint` | Default execute-api endpoint. | No |
| `execution_arn` | Execution ARN for invoke permissions. | No |
| `stage_name` | Stage name (Stage dimension). | No |
| `invoke_url` | Stage invoke URL. | No |
| `authorizer_ids` | Authorizer IDs by key. | No |
| `log_group_name` | Access log group name. | No |
| `log_group_arn` | Access log group ARN. | No |
| `kms_key_arn` | Log key ARN in use; null for service encryption. | No |
| `vpc_link_id` | VPC link ID; null without a VPC link. | No |
| `security_group_id` | VPC link security group ID; null without one. | No |
| `domain_target_name` | Custom domain target for Route 53 aliases; null without a domain. | No |
| `domain_zone_id` | Custom domain hosted zone ID for Route 53 aliases; null without a domain. | No |
| `alarm_arns` | Alarm ARN by key. | No |
| `alarm_names` | Alarm name by key. | No |
