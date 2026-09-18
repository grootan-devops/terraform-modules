# AWS API Gateway REST Module

The `api-gateway` module manages Amazon API Gateway REST APIs featuring Lambda authorizers, OpenAPI definition stitching, stage deployment governance, and KMS-encrypted CloudWatch access logging.

### Architecture & Managed Resources
- `aws_api_gateway_rest_api.this`: Core REST API definition.
- `aws_api_gateway_stage.this`: Deployed execution stage with throttling parameters.
- `aws_cloudwatch_log_group.this`: KMS-encrypted API Gateway access log group.

### Security & Compliance Guardrails
- **Mandatory KMS Logging**: Access logs CloudWatch group requires `kms_key_arn`.
- **Throttling Governance**: Configures default burst and rate limits to protect backend services from DDoS.

---

## Requirements & Providers

| Requirement | Version |
|---|---|
| `terraform` | `>= 1.5.0` |
| `aws` | `>= 6.0.0, < 7.0.0` |

---

## Usage Examples

### Minimal Working Example
```hcl
module "api_gateway" {
  source = "git::https://github.com/organization/terraform-modules.git//modules/aws/integration/api-gateway"

  application = "core"
  environment = "prod"
  name        = "rest-api"
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
}
```

### Complete Production Example
```hcl
module "api_gateway" {
  source = "git::https://github.com/organization/terraform-modules.git//modules/aws/integration/api-gateway"

  application = "portal"
  environment = "prod"
  name        = "public-gateway"
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"

  rate_limiting = {
    rate_limit  = 1000
    burst_limit = 2000
  }

  access_logs = {
    retention_in_days = 90
    format            = jsonencode({
      requestId   = "$context.requestId"
      ip          = "$context.identity.sourceIp"
      caller      = "$context.identity.caller"
      user        = "$context.identity.user"
      requestTime = "$context.requestTime"
      httpMethod  = "$context.httpMethod"
      status      = "$context.status"
    })
  }

  tags = {
    ApiType = "PublicREST"
  }
}
```

---

## Inputs Specification

| Name | Description | Type | Default | Required |
|---|---|---|---|:---:|
| `application` | The name of the product/application. | `string` | **Required** | Yes |
| `environment` | The environment suffix for resources, for example dev, staging, or prod. | `string` | **Required** | Yes |
| `minimum_compression_size` | Minimum response size in bytes before API Gateway compression is applied. Use null to disable. | `number` | `null` | No |
| `endpoint_type` | Endpoint type for the REST API. Valid values are REGIONAL, EDGE, or PRIVATE. | `string` | `"REGIONAL"` | No |
| `tracing_enabled` | Whether to enable API Gateway X-Ray tracing on the managed stage. | `bool` | `true` | No |
| `access_logs` | Mandatory managed API Gateway stage access log configuration. | `object({...})` | `{}` | No |
| `rate_limiting` | Default API Gateway method throttling applied to all methods. | `object({...})` | `{}` | No |
| `waf_web_acl_arn` | Optional AWS WAFv2 Web ACL ARN to associate with the API Gateway stage. | `string` | `null` | No |
| `authorizers` | Map of Cognito user-pool API Gateway authorizers. | `map(object({...}))` | `{}` | No |
| `lambda_authorizers` | Map of Lambda REQUEST authorizers (accept JWT or API key). | `map(object({...}))` | `{}` | No |
| `routes` | Map of route paths to method definitions. | `map(object({...}))` | `{}` | No |
| `models` | Map of API Gateway request/response models. | `map(object({...}))` | `{}` | No |
| `request_validators` | Map of API Gateway request validators. | `map(object({...}))` | `{}` | No |
| `cors` | Default automatic CORS support using MOCK OPTIONS methods. Routes can override these values. | `object({...})` | `{}` | No |
| `stage` | Stage configuration. | `object({...})` | `{}` | No |
| `method_settings` | Default API Gateway method settings applied to all methods. Routes and methods can override these values. | `object({...})` | `{}` | No |
| `custom_domain` | Optional API Gateway custom domain configuration. | `object({...})` | `{}` | No |
| `gateway_responses` | Custom gateway responses map keyed by response type (e.g. ACCESS_DENIED, UNAUTHORIZED) to override default status codes, parameters, and templates. | `map(object({...}))` | `{}` | No |
| `name` | Name for the resource. If not provided, will be derived from application and environment. | `string` | `null` | No |
| `tags` | Additional tags to apply to all resources | `map(string)` | `{}` | No |
| `kms_key_arn` | KMS Key ARN used for encrypting API Gateway CloudWatch logs. Strictly required. | `string` | **Required** | Yes |


---

## Outputs Specification

| Name | Description | Sensitive |
|---|---|:---:|
| `rest_api_id` | The ID of the REST API Gateway | No |
| `stage_name` | The deployed stage name | No |
| `execution_arn` | The execution ARN of the REST API Gateway | No |
| `invoke_url` | The URL to invoke the API pointing to the stage. | No |

