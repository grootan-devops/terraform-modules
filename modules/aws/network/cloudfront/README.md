# AWS CloudFront Distribution Module

The `cloudfront` module provisions Amazon CloudFront Content Delivery Network (CDN) distributions with Origin Access Control (OAC), modern TLS 1.2+ viewers, and KMS-encrypted CloudWatch delivery logs.

## Architecture & Managed Resources

- `aws_cloudfront_distribution.this`: Primary CDN distribution.
- `aws_cloudfront_origin_access_control.this`: Origin Access Control for S3 bucket origin authorization.
- `aws_cloudwatch_log_group.this`: KMS-encrypted delivery log group.

### Security & Compliance Guardrails

- **TLS 1.2+ Enforced**: Minimum protocol version hardcoded to `TLSv1.2_2021`.
- **Redirect to HTTPS**: All cache behaviors enforce `viewer_protocol_policy = "redirect-to-https"`.
- **Mandatory KMS Logging**: CloudWatch delivery log group requires `kms_key_arn`.

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
module "cdn" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/cloudfront?ref=1.0.0"

  application         = "core"
  environment         = "prod"
  aliases             = ["app.company.com"]
  acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  kms_key_arn         = "arn:aws:kms:us-east-1:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"

  default_cache_behavior_origin_id = "s3-assets"
  origins = [
    {
      domain_name              = "company-assets-prod.s3.us-west-2.amazonaws.com"
      origin_id                = "s3-assets"
      origin_access_control_id = ""
      is_s3                    = true
    }
  ]
  cloudwatch_logs = {
    retention_in_days = 90
    kms_key_arn       = "arn:aws:kms:us-east-1:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
  }
}
```

### Complete Production Example

```hcl
module "cdn" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/cloudfront?ref=1.0.0"

  application         = "portal"
  environment         = "prod"
  name                = "main-distribution"
  aliases             = ["portal.company.com"]
  acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  web_acl_id          = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/portal-waf/1234"
  kms_key_arn         = "arn:aws:kms:us-east-1:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"

  origin_access_controls = {
    s3_oac = {
      name                              = "portal-s3-oac"
      description                       = "OAC for portal S3 origin"
      origin_access_control_origin_type = "s3"
      signing_behavior                  = "always"
      signing_protocol                  = "sigv4"
    }
  }

  origins = [
    {
      domain_name              = "company-portal-prod.s3.us-west-2.amazonaws.com"
      origin_id                = "portal-s3"
      origin_access_control_id = "s3_oac"
      is_s3                    = true
    }
  ]

  default_cache_behavior_origin_id = "portal-s3"
  static_paths                     = ["/static/*", "/assets/*"]

  custom_error_responses = [
    {
      error_code            = 404
      response_code         = 200
      error_caching_min_ttl = 300
      response_page_path    = "/index.html"
    }
  ]

  cloudwatch_logs = {
    retention_in_days           = 90
    kms_key_arn                 = "arn:aws:kms:us-east-1:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
    deletion_protection_enabled = true
  }

  tags = {
    EdgeTier = "GlobalCDN"
  }
}
```

---

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | :---: |
| `application` | Application name | `string` | **Required** | Yes |
| `environment` | Deployment environment name (e.g. dev, staging, prod). | `string` | **Required** | Yes |
| `aliases` | List of aliases (CNAMEs) for the CloudFront distribution | `list(string)` | **Required** | Yes |
| `acm_certificate_arn` | ARN of the ACM certificate to use | `string` | **Required** | Yes |
| `web_acl_id` | ID of the WAF Web ACL to associate | `string` | `null` | No |
| `default_root_object` | The default root object to return when a user requests the root URL | `string` | `null` | No |
| `origin_access_controls` | Map of Origin Access Controls to create | `map(object({...}))` | `{}` | No |
| `origins` | List of origins for the CloudFront distribution | `list(object({...}))` | `[]` | No |
| `origin_groups` | List of origin groups for failover configurations | `list(object({...}))` | `[]` | No |
| `default_cache_behavior_origin_id` | The origin ID for the default cache behavior | `string` | **Required** | Yes |
| `static_paths` | List of path patterns to apply the static cache behavior | `list(string)` | `[]` | No |
| `custom_error_responses` | List of custom error responses | `list(object({...}))` | `[]` | No |
| `cache_tag_config_header_name` | Header name for cache tags if needed | `string` | `null` | No |
| `cloudwatch_logs` | CloudWatch logs configuration | `object({...})` | **Required** | Yes |
| `geo_restriction` | The restriction configuration for this distribution (geo_restriction) | `object({...})` | `{ restriction_type = "none" }` | No |
| `name` | Name for the resource. If not provided, will be derived from application and environment. | `string` | `null` | No |
| `tags` | Additional tags to apply to all resources | `map(string)` | `{}` | No |
| `kms_key_arn` | KMS Key ARN used for encrypting CloudFront CloudWatch delivery logs. Strictly required. | `string` | **Required** | Yes |

---

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | :---: |
| `id` | Identifier of the CloudFront distribution. | No |
| `arn` | ARN of the CloudFront distribution. | No |
| `domain_name` | Domain name corresponding to the distribution. | No |
| `hosted_zone_id` | CloudFront Route 53 zone ID that can be used to route an Alias resource to. | No |
