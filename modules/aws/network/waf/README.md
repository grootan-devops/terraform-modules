# AWS WAFv2 Web ACL Module

The `waf` module provisions AWS WAFv2 Web Access Control Lists (Web ACLs) with AWS Managed Rule Groups, custom rate-limiting, IP set filters, and KMS-encrypted CloudWatch logging.

## Architecture & Managed Resources

- `aws_wafv2_web_acl.this`: Web ACL evaluation engine.
- `aws_wafv2_ip_set.this`: Managed IP allow/block sets.
- `aws_cloudwatch_log_group.this`: KMS-encrypted WAF activity log group (`aws-waf-logs-*`).
- `aws_wafv2_web_acl_logging_configuration.this`: Connects WAF metrics and sample requests to CloudWatch.

### Security & Compliance Guardrails

- **AWS Managed Rule Sets**: Pre-configured with Common Rule Set, Known Bad Inputs, and Amazon IP Reputation list.
- **Mandatory KMS Logging**: Log group enforces Customer Managed Key encryption (`kms_key_arn`).
- **Scope Flexibility**: Operates in `REGIONAL` mode (ALBs, API Gateways) or `CLOUDFRONT` mode.

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
module "waf" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/waf?ref=1.0.0"

  application = "core"
  environment = "prod"
  name        = "edge-filter"
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"

  cloudwatch_logs = {
    retention_in_days = 90
    kms_key_arn       = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
  }
}
```

### Complete Production Example

```hcl
module "waf" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/waf?ref=1.0.0"

  application = "enterprise"
  environment = "prod"
  name        = "ingress-guard"
  scope       = "REGIONAL"
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"

  rate_limit = 2000

  ip_sets = [
    {
      name               = "blocked-malicious-ips"
      description        = "Known threat actor IP list"
      ip_address_version = "IPV4"
      addresses          = ["198.51.100.14/32", "203.0.113.0/24"]
      action             = "block"
    }
  ]

  cloudwatch_logs = {
    retention_in_days = 90
    kms_key_arn       = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
  }

  tags = {
    SecurityLayer = "PerimeterFirewall"
  }
}
```

---

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | :---: |
| `application` | Application name | `string` | **Required** | Yes |
| `environment` | Deployment environment name (e.g. dev, staging, prod). | `string` | **Required** | Yes |
| `scope` | Specifies whether this is for an AWS CloudFront distribution or for a regional application. Valid values are CLOUDFRONT or REGIONAL. | `string` | `"REGIONAL"` | No |
| `default_action` | Default action for the WAF. Can be 'allow' or 'block' | `string` | `"allow"` | No |
| `token_domains` | List of domains to configure for the AWS WAFv2 API Key (used for CAPTCHA/JavaScript challenges). Max 5 domains. | `list(string)` | `[]` | No |
| `managed_rules` | Map of AWS Managed Rule Groups to enable | `map(object({...}))` | `{...}` | No |
| `ip_sets` | Map of IP sets to create | `map(object({...}))` | `{}` | No |
| `regex_pattern_sets` | Map of Regex Pattern Sets to create | `map(object({...}))` | `{}` | No |
| `rate_limit_rules` | Map of Rate Limit rules to create (blanket limit based on IP) | `map(object({...}))` | `{}` | No |
| `ip_block_rules` | Map of rules to block specific IP sets created in var.ip_sets | `map(object({...}))` | `{}` | No |
| `geo_block_rules` | Map of Geo match rules | `map(object({...}))` | `{}` | No |
| `association_arns` | List of ARNs (ALB, API Gateway, AppSync) to associate the WAF with | `list(string)` | `[]` | No |
| `cloudwatch_logs` | CloudWatch logs configuration | `object({...})` | `{}` | No |
| `redacted_fields` | Configuration for redacted fields in WAF logs | `object({...})` | `{}` | No |
| `name` | Name for the resource. If not provided, will be derived from application and environment. | `string` | `null` | No |
| `tags` | Additional tags to apply to all resources | `map(string)` | `{}` | No |
| `kms_key_arn` | KMS Key ARN used for encrypting WAF CloudWatch log groups. Strictly required. | `string` | **Required** | Yes |

---

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | :---: |
| `web_acl_arn` | ARN of the WAFv2 Web ACL. | No |
| `web_acl_id` | ID of the WAFv2 Web ACL. | No |
| `web_acl_capacity` | Web ACL capacity units (WCU) currently used by this Web ACL. | No |
