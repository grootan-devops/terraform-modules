# AWS API Gateway REST Module

Scope: `workload`

A REST API built from a generated OpenAPI definition (Lambda, HTTP, AWS and MOCK integrations, Cognito and Lambda
authorizers, CORS, models, validators, gateway responses), with its deployment, stage, access and execution logs,
method settings, Lambda invoke permissions, WAF association, optional Regional custom domain and optional customer
managed key for the logs. Functions, user pools, web ACLs and certificates are other modules; pass their ARNs in.

## Architecture & Managed Resources

- `aws_api_gateway_rest_api.this`: `<application>-<environment>[-<name>]`, defined by the OpenAPI `body`; cross-input
  checks (unknown authorizer, model or validator, CORS credentials) are preconditions.
- `aws_api_gateway_deployment.this`, `aws_api_gateway_stage.this`: stage named after the environment unless
  `stage.name` is set; redeployed when the definition changes.
- `aws_api_gateway_method_settings.this`: `*/*` (execution logging, metrics, throttling, caching) plus one override per
  route or method with `method_settings`.
- `module.access_log_group`, `module.execution_log_group` ([`observability/log-group`](../../observability/log-group)):
  `/aws/apigateway/<api>/<stage>/access` and `API-Gateway-Execution-Logs_<api-id>/<stage>`, created before API Gateway
  writes to them.
- `aws_lambda_permission.routes`, `aws_lambda_permission.authorizers`: invoke permissions on the function alias.
- `aws_wafv2_web_acl_association.this`, `aws_api_gateway_domain_name.this`, `aws_api_gateway_base_path_mapping.this`:
  optional.
- `module.encryption` ([`core/encryption`](../../core/encryption)): service encryption, module key or your key for the
  logs.

## Security & Compliance Guardrails

- **Logging (APIGateway.1):** execution logging at `ERROR` (or `INFO`) with metrics and no data trace; JSON access
  logs; both groups 365 days, deletion protection, the module key when set. Both need the account-level API Gateway
  CloudWatch Logs role, which [`governance/account-baseline`](../../governance/account-baseline) owns.
- **Authorization (APIGateway.8):** every method except `OPTIONS` needs `authorizer_key` unless
  `allow_unauthenticated_methods = true`.
- **Invoke permissions:** take the lambda module's `invoke_arn` and `alias_arn`; each permission is limited to this
  API, stage, method and path (`ANY` and path parameters become `*`); authorizers to `<execution_arn>/authorizers/*`.
- **TLS (APIGateway.11):** enhanced policies only (AWS calls `TLS_1_0` and `TLS_1_2` legacy):
  `SecurityPolicy_TLS13_1_2_PFS_PQ_2025_09` on Regional APIs and the custom domain, `SecurityPolicy_TLS12_PFS_2025_EDGE`
  on edge-optimized APIs, with `endpoint_access_mode = "STRICT"` (set `BASIC` only for cross-endpoint callers). The
  execute-api endpoint is turned off when a custom domain is on.
- **Cache (APIGateway.5):** `cache_data_encrypted` is forced on wherever caching is on.
- **X-Ray (APIGateway.3):** on by default. **WAF (APIGateway.4):** `waf.web_acl_arn`. **Backend certificate
  (APIGateway.2):** `client_certificate_id`.

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
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/integration/api-gateway?ref=<version>"

  application = "core"
  environment = "prod"
}
```

### Complete Production Example

```hcl
module "api" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/integration/api-gateway?ref=<version>"

  application     = "core"
  environment     = "prod"
  name            = "public"
  kms             = { create = true }
  waf             = { enabled = true, web_acl_arn = module.waf.arn }
  method_settings = { throttling_rate_limit = 1000, throttling_burst_limit = 2000 }
  cors            = { enabled = true, allow_origins = ["https://app.example.com"] }

  authorizers = {
    cognito = { provider_arns = [module.cognito.arn] }
  }

  routes = {
    "/orders" = {
      methods = {
        GET  = { authorizer_key = "cognito", lambda = { invoke_arn = module.orders.invoke_arn, alias_arn = module.orders.alias_arn } }
        POST = { authorizer_key = "cognito", lambda = { invoke_arn = module.orders.invoke_arn, alias_arn = module.orders.alias_arn } }
      }
    }
    "/orders/{id}" = {
      methods = {
        GET = { authorizer_key = "cognito", lambda = { invoke_arn = module.orders.invoke_arn, alias_arn = module.orders.alias_arn } }
      }
    }
  }

  custom_domain = {
    enabled         = true
    domain_name     = "api.example.com"
    certificate_arn = module.certificate.arn
  }
}

module "zone" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/route53?ref=<version>"

  application = "core"
  environment = "prod"
  zone_name   = "example.com"

  records = {
    api = { name = "api", type = "A", alias = { name = module.api.regional_domain_name, zone_id = module.api.regional_zone_id } }
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
| `description` | API description. | `string` | `null` | No |
| `endpoint_type` | REGIONAL or EDGE. | `string` | `"REGIONAL"` | No |
| `tls` | Enhanced TLS policies of the API and the custom domain; null picks the default for the endpoint type. | `object({...})` | `{}` | No |
| `binary_media_types` | Binary media types. | `list(string)` | `[]` | No |
| `minimum_compression_size` | Compression threshold in bytes (0-10485760); null: off. | `number` | `null` | No |
| `stage` | Stage name (default: environment), description and variables. | `object({...})` | `{}` | No |
| `cache_cluster` | Stage cache cluster; always encrypted. | `object({...})` | `{}` | No |
| `tracing` | X-Ray tracing on the stage. | `object({...})` | `{}` | No |
| `kms` | Log encryption: {} CloudWatch Logs service encryption, create = true module key, key_id your key (ARN or ID). | `object({...})` | `{}` | No |
| `cloudwatch_logs` | Access and execution log groups and the access log format. | `object({...})` | `{}` | No |
| `execution_logging` | Stage execution logging and metrics. | `object({...})` | `{}` | No |
| `client_certificate_id` | Client certificate ID for backends (APIGateway.2). | `string` | `null` | No |
| `waf` | WAFv2 web ACL association (APIGateway.4). | `object({...})` | `{}` | No |
| `method_settings` | Stage-wide throttling and caching. | `object({...})` | `{}` | No |
| `authorizers` | Cognito user pool authorizers by key. | `map(object({...}))` | `{}` | No |
| `lambda_authorizers` | Lambda REQUEST authorizers by key: the lambda module's invoke_arn and alias_arn. | `map(object({...}))` | `{}` | No |
| `routes` | Routes by path: methods by HTTP verb, CORS and method settings overrides. | `map(object({...}))` | `{}` | No |
| `allow_unauthenticated_methods` | Allow methods without an authorizer. | `bool` | `false` | No |
| `models` | Models by name: JSON schema. | `map(string)` | `{}` | No |
| `request_validators` | Request validators by name. | `map(object({...}))` | `{}` | No |
| `cors` | CORS preflight (MOCK OPTIONS) defaults; routes override. | `object({...})` | `{}` | No |
| `gateway_responses` | Gateway response overrides by type. | `map(object({...}))` | `{}` | No |
| `custom_domain` | Regional custom domain mapped to the stage. | `object({...})` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `id` | REST API ID. | No |
| `arn` | REST API ARN. | No |
| `name` | REST API name. | No |
| `execution_arn` | Execution ARN for invoke permissions. | No |
| `invoke_url` | Stage invoke URL. | No |
| `stage_arn` | Stage ARN. | No |
| `stage_name` | Stage name. | No |
| `regional_domain_name` | Custom domain target for Route 53 aliases; null without a domain. | No |
| `regional_zone_id` | Custom domain hosted zone ID for Route 53 aliases; null without a domain. | No |
| `log_group_name` | Access log group name. | No |
| `log_group_arn` | Access log group ARN. | No |
| `kms_key_arn` | Log key ARN in use; null for service encryption. | No |
