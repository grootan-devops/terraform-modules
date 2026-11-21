# AWS CloudFront Module

Scope: `workload`

A CloudFront distribution with origin access control for S3 and Lambda URL origins, failover origin groups, cache
behaviors built from managed or custom policies, standard logging (v2) to a CloudWatch log group in us-east-1 or to an
S3 bucket, and an optional WAF web ACL association. Certificates, web ACLs, origin buckets and log buckets are other
modules; pass their ARNs and domain names in.

## Architecture & Managed Resources

- `aws_cloudfront_distribution.this`: comment `<application>-<environment>[-<name>]`, HTTP/2 and HTTP/3, IPv6.
  Without `aliases` it uses the default `*.cloudfront.net` certificate; with `aliases` it needs
  `acm_certificate_arn` (a us-east-1 certificate, for example from [`security/acm`](../../security/acm) with
  `region = "us-east-1"`).
- `aws_cloudfront_origin_access_control.this`: one SigV4 control per origin type in use (`s3`, `lambda`), signing
  always.
- `data.aws_cloudfront_*_policy.managed`: a cache, origin request or response headers policy given as a `Managed-*`
  name is looked up once; anything else is used as a policy ID. Only names in use are looked up.
- `aws_cloudwatch_log_delivery_source.this`, `aws_cloudwatch_log_delivery_destination.this` and
  `aws_cloudwatch_log_delivery.this`: access log delivery in JSON, always created in us-east-1 (the CloudFront
  logging API Region), to one destination chosen by `logging.destination`:
  - `cloudwatch` (default): `module.log_group` ([`observability/log-group`](../../observability/log-group)),
    `/aws/cloudfront/<base>` in us-east-1.
  - `s3`: the bucket in `logging.s3_bucket_arn`, in any Region; no log group is created. Objects land under
    `<prefix>/<account>/CloudFront/<distribution-id>/<yyyy>/<MM>/<dd>/<HH>/` (`prefix` default `AWSLogs`, one folder),
    the layout of other AWS logs in a log bucket.
- `module.encryption` ([`core/encryption`](../../core/encryption)): the log group key, in us-east-1.

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
- **Logs:** standard logging (v2), always on, to a 365-day log group with deletion protection, or to an S3 bucket whose
  lifecycle sets the retention. CloudFront.5 checks legacy S3 logging, which this module does not use, so Security
  Hub still reports it.

A key passed in `kms.key_id` must be in us-east-1 and allow `logs.us-east-1.amazonaws.com` (encryption context
`aws:logs:arn = <log group ARN>`). `kms` and `cloudwatch_logs` apply to the `cloudwatch` destination only; `kms` is rejected with `s3`.

With `logging = { destination = "s3", s3_bucket_arn = ... }` the bucket name may hold only letters, digits, `-` and `_`
(no dots), and its policy must let `delivery.logs.amazonaws.com` write with `aws:SourceArn`
`arn:aws:logs:us-east-1:<account>:delivery-source:*`: [`storage/log-bucket`](../../storage/log-bucket) with
`vended_logs = { enabled = true }` grants it. A bucket encrypted with a customer managed key must also allow
`delivery.logs.amazonaws.com` in its key policy.

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
  logging             = { destination = "s3", s3_bucket_arn = module.logs.arn }

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

module "logs" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/storage/log-bucket?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "logs"
  vended_logs = { enabled = true }
}
```

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
| `logging` | Access log destination: cloudwatch or s3 (s3_bucket_arn, prefix). | `object({...})` | `{}` | No |
| `cloudwatch_logs` | Access log group in us-east-1 (destination cloudwatch). | `object({...})` | `{}` | No |
| `kms` | Log encryption in us-east-1: {} service encryption, create = true module key, key_id your key (ARN or ID). | `object({...})` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `id` | Distribution ID. | No |
| `arn` | Distribution ARN. | No |
| `domain_name` | Distribution domain name. | No |
| `hosted_zone_id` | Route 53 zone ID for alias records. | No |
| `log_group_name` | Access log group name; null unless cloudwatch. | No |
| `log_group_arn` | Access log group ARN; null unless cloudwatch. | No |
| `kms_key_arn` | Log key ARN; null for service encryption. | No |
