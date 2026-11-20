# AWS WAF Module

Scope: `workload`

A WAFv2 web ACL with AWS managed rule groups, rate limits, IP set, geo and regex rules, CloudWatch metrics and
logging with sensitive headers redacted. The protected resource associates itself: `alb` and `cloudfront` take
`waf = { enabled = true, web_acl_arn = module.waf.arn }`.

## Architecture & Managed Resources

- `aws_wafv2_web_acl.this`: `<application>-<environment>[-<name>]`. `scope = "REGIONAL"` (ALB, API Gateway,
  AppSync, Cognito) in the provider Region, or `"CLOUDFRONT"`: every resource, the log group and the key are then
  created in us-east-1 through the resource-level `region` argument.
- Rules are named `<type>-<key>` with priority bands: `managed-*` from 10, `rate-*` from 100, `ip-*` from 200,
  `geo-*` from 300, `regex-*` from 400, each in key order.
- `aws_wafv2_ip_set.this`, `aws_wafv2_regex_pattern_set.this`: `<base>-<key>`.
- `module.log_group` ([`observability/log-group`](../../observability/log-group)): `aws-waf-logs-<base>` (WAF requires
  the prefix); `aws_wafv2_web_acl_logging_configuration.this` sends logs to it.
- `module.encryption` ([`core/encryption`](../../core/encryption)): the log key, in the web ACL's Region.
- `module.alarms` ([`observability/cloudwatch-alarms`](../../observability/cloudwatch-alarms)): built-in alarms, off
  until a threshold is set; see [Built-in Alarms](#built-in-alarms).

## Security & Compliance Guardrails

- **Rules (WAF.10):** `AWSManagedRulesCommonRuleSet`, `AWSManagedRulesAmazonIpReputationList` and
  `AWSManagedRulesKnownBadInputsRuleSet` by default; a web ACL without any rule is rejected.
- **Metrics (WAF.12):** CloudWatch metrics and sampled requests on the web ACL and every rule; `metric_name` and
  `rule_metric_names` feed alarms.
- **Logging (WAF.11):** always on, 365 days with deletion protection; the `authorization` and `cookie` headers
  are redacted so credentials and session tokens stay out of the logs.

WAF adds the log group resource policy for `delivery.logs.amazonaws.com` on first delivery; the deploying principal
needs `logs:PutResourcePolicy` and `logs:DescribeResourcePolicies`. A key passed in `kms.key_id` must be in the web
ACL's Region and allow `logs.<region>.amazonaws.com` (encryption context `aws:logs:arn = <log group ARN>`).

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "waf" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/waf?ref=<version>"

  application = "core"
  environment = "prod"
}
```

### Complete Production Example

```hcl
module "waf" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/waf?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "edge"
  scope       = "CLOUDFRONT"
  kms         = { create = true }

  rate_limit_rules = { per_ip = { limit = 2000 } }
  ip_sets          = { blocked = { addresses = ["198.51.100.0/24"] } }
  ip_block_rules   = { blocked = { ip_set_key = "blocked" } }
  geo_block_rules  = { sanctioned = { countries = ["KP", "IR"] } }
}

module "cloudfront" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/cloudfront?ref=<version>"

  application            = "core"
  environment            = "prod"
  waf                    = { enabled = true, web_acl_arn = module.waf.arn }
  origins                = { api = { domain_name = module.alb.dns_name } }
  default_cache_behavior = { target_origin_id = "api", cache_policy = "Managed-CachingDisabled" }
}
```

### Built-in Alarms

The `waf_web_acls` preset of [`observability/cloudwatch-alarms`](../../observability/cloudwatch-alarms) has one
alarm, `waf-acl-blocked-requests` (warning, Sum of `BlockedRequests` over 5 minutes on all rules). Normal blocked
traffic differs per workload, so it has no default threshold and is on only when `blocked_requests.threshold` is set:
the default call creates no alarms. The alarm lives in the web ACL's Region, us-east-1 for `scope = "CLOUDFRONT"`;
pass topics from that Region (`module.alarm_routing.topic_arns["us-east-1"]` for CloudFront). Without `topic_arns`
the alarm has no actions; `alarms = { enabled = false }` creates none.

```hcl
module "alarm_routing" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/observability/alarm-routing?ref=<version>"

  environment = "prod"
}

module "waf" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/waf?ref=<version>"

  application = "core"
  environment = "prod"

  alarms = {
    topic_arns = module.alarm_routing.topic_arns["eu-west-1"]
    overrides = {
      blocked_requests = { threshold = 1000, severity = "critical" }
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
| `name` | Web ACL name. | `string` | `null` | No |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `scope` | REGIONAL or CLOUDFRONT (created in us-east-1). | `string` | `"REGIONAL"` | No |
| `default_action` | Action when no rule matches: allow or block. | `string` | `"allow"` | No |
| `managed_rules` | Managed rule groups by key: name, vendor, override action, version. | `map(object({...}))` | `{...}` | No |
| `rate_limit_rules` | Per-IP rate limits by key: requests per 5 minutes, action. | `map(object({...}))` | `{}` | No |
| `ip_sets` | IP sets by key: version and addresses. | `map(object({...}))` | `{}` | No |
| `ip_block_rules` | Rules matching an ip_sets key, by key: action. | `map(object({...}))` | `{}` | No |
| `geo_block_rules` | Country match rules by key: country codes, action. | `map(object({...}))` | `{}` | No |
| `regex_pattern_sets` | Regex pattern sets by key. | `map(object({...}))` | `{}` | No |
| `regex_match_rules` | Rules matching a regex_pattern_sets key on uri_path, query_string or single_header. | `map(object({...}))` | `{}` | No |
| `token_domains` | Domains whose CAPTCHA and challenge tokens the web ACL accepts. | `list(string)` | `[]` | No |
| `redacted_fields` | Request fields redacted in logs. | `object({...})` | `{}` | No |
| `cloudwatch_logs` | WAF log group (aws-waf-logs- prefix). | `object({...})` | `{}` | No |
| `kms` | Log encryption: {} service encryption, create = true module key, key_id your key (ARN or ID). | `object({...})` | `{}` | No |
| `alarms` | Built-in CloudWatch alarms: switch, topics by severity, per-alarm overrides. | `object({...})` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `id` | Web ACL ID. | No |
| `arn` | Web ACL ARN. | No |
| `name` | Web ACL name. | No |
| `metric_name` | Web ACL metric name (WebACL dimension). | No |
| `rule_metric_names` | Rule metric names by rule name (Rule dimension). | No |
| `log_group_name` | Log group name. | No |
| `log_group_arn` | Log group ARN. | No |
| `kms_key_arn` | Log key ARN; null for service encryption. | No |
| `alarm_arns` | Alarm ARN by key. | No |
| `alarm_names` | Alarm name by key. | No |
