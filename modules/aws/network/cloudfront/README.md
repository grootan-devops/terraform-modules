# AWS CloudFront Module

Scope: `workload`

A CloudFront distribution with origin access control for S3 and Lambda URL origins, failover origin groups, cache
behaviors built from managed or custom policies, standard logging (v2) to a CloudWatch log group in us-east-1 and an
optional WAF web ACL association. Certificates, web ACLs and origin buckets are other modules; pass their ARNs and domain names in.

## Architecture & Managed Resources

- `aws_cloudfront_distribution.this`: comment `<application>-<environment>[-<name>]`, HTTP/2 and HTTP/3, IPv6.
  Without `aliases` it uses the default `*.cloudfront.net` certificate; with `aliases` it needs
  `acm_certificate_arn` (a us-east-1 certificate, for example from [`security/acm`](../../security/acm) with
  `region = "us-east-1"`).
- `aws_cloudfront_origin_access_control.this`: one SigV4 control per origin type in use (`s3`, `lambda`), signing
  always.
- `data.aws_cloudfront_*_policy.managed`: a cache, origin request or response headers policy given as a `Managed-*`
  name is looked up once; anything else is used as a policy ID. Only names in use are looked up.
- `module.log_group` ([`observability/log-group`](../../observability/log-group)): `/aws/cloudfront/<base>` in
  us-east-1; `aws_cloudwatch_log_delivery_source.this`, `aws_cloudwatch_log_delivery_destination.this` and
  `aws_cloudwatch_log_delivery.this` deliver access logs to it (CloudFront logs only to us-east-1).
- `module.encryption` ([`core/encryption`](../../core/encryption)): the log key, in us-east-1.
- `module.alarms` ([`observability/cloudwatch-alarms`](../../observability/cloudwatch-alarms)): built-in alarms in
  us-east-1, on by default; see [Built-in Alarms](#built-in-alarms).

## Security & Compliance Guardrails

- **HTTPS to viewers and origins (CloudFront.3, .9, .10):** every behavior redirects to HTTPS; custom and Lambda URL
  origins use `https-only` with TLS 1.2.
- **TLS policy and SNI (CloudFront.7, .8, .15):** custom certificates use `sni-only` and `TLSv1.2_2025` by default;
  only TLS 1.2 or 1.3 policies are accepted.
- **Origin access control (CloudFront.13, .16):** every S3 and Lambda URL origin is signed; the bucket or function
  policy must allow `cloudfront.amazonaws.com` with `AWS:SourceArn` set to the distribution ARN.
- **Security headers:** behaviors attach `Managed-SecurityHeadersPolicy` unless another policy is set.
- **WAF (CloudFront.6):** `waf = { enabled = true, web_acl_arn = ... }` takes a `CLOUDFRONT`-scope web ACL; the
  association is owned here.
- **Logs:** standard logging (v2), always on, to a 365-day log group with deletion protection. CloudFront.5 checks
  legacy S3 logging, which this module does not use, so Security Hub still reports it.

A key passed in `kms.key_id` must be in us-east-1 and allow `logs.us-east-1.amazonaws.com` (encryption context
`aws:logs:arn = <log group ARN>`).

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "cloudfront" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/cloudfront?ref=<version>"

  application            = "core"
  environment            = "prod"
  origins                = { api = { domain_name = module.alb.dns_name } }
  default_cache_behavior = { target_origin_id = "api", cache_policy = "Managed-CachingDisabled" }
}
```

### Complete Production Example

```hcl
module "cloudfront" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/cloudfront?ref=<version>"

  application         = "core"
  environment         = "prod"
  name                = "web"
  aliases             = ["www.example.com"]
  acm_certificate_arn = module.certificate_us_east_1.arn
  waf                 = { enabled = true, web_acl_arn = module.waf_cloudfront.arn }
  default_root_object = "index.html"
  kms                 = { create = true }

  origins = {
    site = { domain_name = module.site_bucket.regional_domain_name, type = "s3" }
    api  = { domain_name = module.alb.dns_name }
  }
  default_cache_behavior = { target_origin_id = "site" }
  ordered_cache_behaviors = [{
    path_pattern          = "/api/*"
    target_origin_id      = "api"
    allowed_methods       = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cache_policy          = "Managed-CachingDisabled"
    origin_request_policy = "Managed-AllViewerExceptHostHeader"
  }]
}
```

### Built-in Alarms

The `cloudfront_distributions` preset of [`observability/cloudwatch-alarms`](../../observability/cloudwatch-alarms)
is on by default: `cloudfront-distribution-5xx-error-rate` (critical, above 5 %). `client_error_rate`
(`cloudfront-distribution-4xx-error-rate`) and `requests` (`cloudfront-distribution-requests`) are opt-in and need a
`threshold`. CloudFront publishes its metrics in us-east-1, so the alarms live there and `topic_arns` must be
us-east-1 topics: list `us-east-1` in the alarm-routing `regions` and pass
`module.alarm_routing.topic_arns["us-east-1"]`. Without `topic_arns` the alarms have no actions;
`alarms = { enabled = false }` creates none.

```hcl
module "alarm_routing" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/observability/alarm-routing?ref=<version>"

  environment = "prod"
  regions     = ["eu-west-1", "us-east-1"]
}

module "cloudfront" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/cloudfront?ref=<version>"

  application            = "core"
  environment            = "prod"
  origins                = { api = { domain_name = module.alb.dns_name } }
  default_cache_behavior = { target_origin_id = "api", cache_policy = "Managed-CachingDisabled" }

  alarms = {
    topic_arns = module.alarm_routing.topic_arns["us-east-1"]
    overrides = {
      server_error_rate = { threshold = 2 }
      client_error_rate = { enabled = true, threshold = 15 }
    }
  }
}
```

`overrides` takes the preset's alarm keys and fields (`enabled`, `threshold`, `evaluation_periods`,
`datapoints_to_alarm`, `period`, `severity`); a field left out keeps the preset default. To turn the default alarm
off, set `server_error_rate = { enabled = false }`.

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | **Required** | Yes |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `name` | Distribution name. | `string` | `null` | No |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `aliases` | Alternate domain names. Empty: the default CloudFront certificate. | `list(string)` | `[]` | No |
| `acm_certificate_arn` | us-east-1 ACM certificate ARN for the aliases. | `string` | `null` | No |
| `minimum_protocol_version` | Viewer TLS policy. | `string` | `"TLSv1.2_2025"` | No |
| `waf` | CLOUDFRONT-scope WAF web ACL (CloudFront.6). | `object({...})` | `{}` | No |
| `origins` | Origins by ID: domain name, type s3, lambda or custom, path. | `map(object({...}))` | **Required** | Yes |
| `origin_groups` | Failover origin groups by ID: primary, secondary, status codes. | `map(object({...}))` | `{}` | No |
| `default_cache_behavior` | Default behavior: origin, methods, cache, origin request and response headers policies (Managed-* name or ID). | `object({...})` | **Required** | Yes |
| `ordered_cache_behaviors` | Path behaviors in order, same fields as the default plus path_pattern. | `list(object({...}))` | `[]` | No |
| `default_root_object` | Object for / requests, such as index.html (CloudFront.1). | `string` | `null` | No |
| `custom_error_responses` | Custom error responses. | `list(object({...}))` | `[]` | No |
| `geo_restriction` | Geo restriction: none, whitelist or blacklist with country codes. | `object({...})` | `{}` | No |
| `price_class` | Price class. | `string` | `"PriceClass_All"` | No |
| `cloudwatch_logs` | Access log group in us-east-1. | `object({...})` | `{}` | No |
| `kms` | Log encryption in us-east-1: {} service encryption, create = true module key, key_id your key (ARN or ID). | `object({...})` | `{}` | No |
| `alarms` | Built-in CloudWatch alarms: switch, topics by severity, per-alarm overrides. | `object({...})` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `id` | Distribution ID. | No |
| `arn` | Distribution ARN. | No |
| `domain_name` | Distribution domain name. | No |
| `hosted_zone_id` | Route 53 zone ID for alias records. | No |
| `log_group_name` | Access log group name. | No |
| `log_group_arn` | Access log group ARN. | No |
| `kms_key_arn` | Log key ARN; null for service encryption. | No |
| `alarm_arns` | Alarm ARN by key. | No |
| `alarm_names` | Alarm name by key. | No |
