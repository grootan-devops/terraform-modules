# AWS Certificate Manager Module

Scope: `workload`

A public ACM certificate validated through DNS records in a Route 53 hosted zone. ACM renews it automatically while
the validation records stay in place. Set `region = "us-east-1"` for a CloudFront certificate.

## Architecture & Managed Resources

- `aws_acm_certificate.this`: `domain_name` plus `subject_alternative_names`, `key_algorithm`, DNS validation,
  certificate transparency logging on, created before it is destroyed so listeners never lose a certificate.
- `aws_route53_record.validation`: one CNAME per distinct name in `validation.zone_id` (a wildcard shares its base
  name's record), allowed to overwrite the record of a certificate being replaced.
- `aws_acm_certificate_validation.this`: waits for issuance; the `arn` output comes from it, so a listener or
  distribution that uses `arn` waits too.
- With `validation = { enabled = false }`, no records are created; `validation_records` lists them for external DNS.

## Security & Compliance Guardrails

- **Renewal (ACM.1):** ACM-issued, DNS-validated certificates renew automatically while the records exist.
- **Key strength (ACM.2):** `RSA_2048`, `EC_prime256v1` or `EC_secp384r1` only.
- **Tags (ACM.3):** governance tags on the certificate.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "certificate" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/acm?ref=<version>"

  application = "core"
  environment = "prod"
  domain_name = "api.example.com"
  validation  = { zone_id = module.zone.zone_id }
}
```

### Complete Production Example

```hcl
module "certificate_us_east_1" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/acm?ref=<version>"

  application               = "core"
  environment               = "prod"
  name                      = "web"
  region                    = "us-east-1"
  domain_name               = "example.com"
  subject_alternative_names = ["*.example.com"]
  key_algorithm             = "EC_prime256v1"
  validation                = { zone_id = module.zone.zone_id }
}

module "cloudfront" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/cloudfront?ref=<version>"

  application            = "core"
  environment            = "prod"
  aliases                = ["www.example.com"]
  acm_certificate_arn    = module.certificate_us_east_1.arn
  origins                = { site = { domain_name = module.site_bucket.regional_domain_name, type = "s3" } }
  default_cache_behavior = { target_origin_id = "site" }
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | **Required** | Yes |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `name` | Certificate name. | `string` | `null` | No |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `domain_name` | Certificate domain name. | `string` | **Required** | Yes |
| `subject_alternative_names` | Additional domain names. | `list(string)` | `[]` | No |
| `key_algorithm` | Key algorithm: RSA_2048, EC_prime256v1 or EC_secp384r1. | `string` | `"RSA_2048"` | No |
| `validation` | DNS validation records in a Route 53 zone. | `object({...})` | `{}` | No |
| `region` | Certificate Region (us-east-1 for CloudFront). Null: provider Region. | `string` | `null` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `arn` | Certificate ARN, after validation when enabled. | No |
| `domain_name` | Certificate domain name. | No |
| `status` | Certificate status. | No |
| `validation_record_fqdns` | Validation record FQDNs. | No |
| `validation_records` | Validation records for external DNS: name, type, value. | No |
