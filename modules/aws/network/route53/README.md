# AWS Route 53 Hosted Zone Module

Scope: `workload`

A public or private Route 53 hosted zone with its records, health checks, DNS query logging and DNSSEC signing.
Records point at other modules through aliases (`module.alb.dns_name`, `module.cloudfront.domain_name`).

## Architecture & Managed Resources

- `aws_route53_zone.this`: public by default; private when `vpc_ids` is set. Never force-destroyed.
- `aws_route53_record.this` (`records`): names relative to the zone (`""` is the apex); either `records` with a TTL or
  an `alias = { name, zone_id, evaluate_target_health }`; optional failover routing with a health check.
- `aws_route53_health_check.this` (`health_checks`): tagged `<base>-<key>`; HTTPS checks use port 443 with SNI.
- Query logging (public zones): `module.log_group` ([`observability/log-group`](../../observability/log-group))
  `/aws/route53/<zone>` in us-east-1, `aws_cloudwatch_log_resource_policy.query_logging` (us-east-1, one per zone,
  scoped to this zone and account) and `aws_route53_query_log.this`. Route 53 writes query logs only to us-east-1.
- DNSSEC (public zones): `module.dnssec_key` ([`security/kms`](../../security/kms)), an `ECC_NIST_P256`
  `SIGN_VERIFY` key in us-east-1, `aws_route53_key_signing_key.this` and `aws_route53_hosted_zone_dnssec.this`.
- `module.encryption` ([`core/encryption`](../../core/encryption)): the query log key, in us-east-1.

## Security & Compliance Guardrails

- **Query logging (Route53.2):** always on for public zones, 365 days with deletion protection. The resource policy lets
  only `route53.amazonaws.com` write, for this zone (`aws:SourceArn`) and account (`aws:SourceAccount`).
- **DNSSEC:** on for public zones. The key policy grants `dnssec-route53.amazonaws.com` the statements AWS documents:
  `kms:DescribeKey`, `kms:GetPublicKey`, `kms:Sign` and `kms:Verify` with `aws:SourceAccount` and `aws:SourceArn`,
  and `kms:CreateGrant` only for AWS resources. Signing starts at once; add the `ds_record` output to the parent zone
  to complete the chain of trust. Asymmetric keys do not rotate; Route 53 rotates by adding a new key-signing key.
- **Tagged health checks (Route53.1).**

A key passed in `kms.key_id` must be in us-east-1 and allow `logs.us-east-1.amazonaws.com` (encryption context
`aws:logs:arn = <query log group ARN>`). CloudWatch Logs allows ten resource policies per account and Region; each
public zone with query logging uses one in us-east-1.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "zone" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/route53?ref=<version>"

  application = "core"
  environment = "prod"
  zone_name   = "example.com"
}
```

### Complete Production Example

```hcl
module "zone" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/route53?ref=<version>"

  application = "core"
  environment = "prod"
  zone_name   = "example.com"
  kms         = { create = true }

  records = {
    apex = { type = "A", alias = { name = module.cloudfront.domain_name, zone_id = module.cloudfront.hosted_zone_id } }
    api  = { name = "api", type = "A", alias = { name = module.alb.dns_name, zone_id = module.alb.zone_id, evaluate_target_health = true } }
    mail = { type = "MX", records = ["10 mail.example.com"], ttl = 3600 }
  }
  health_checks = { api = { fqdn = "api.example.com", resource_path = "/health" } }
}

module "internal_zone" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/route53?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "internal"
  zone_name   = "prod.internal"
  vpc_ids     = [module.vpc.vpc_id]
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | **Required** | Yes |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `name` | Zone instance name. | `string` | `null` | No |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `zone_name` | Domain name of the hosted zone. | `string` | **Required** | Yes |
| `comment` | Zone comment. | `string` | `null` | No |
| `vpc_ids` | VPC IDs for a private zone. Empty: public zone. | `list(string)` | `[]` | No |
| `records` | Records by key: name relative to the zone ("" apex), type, TTL and values or alias, failover. | `map(object({...}))` | `{}` | No |
| `health_checks` | Health checks by key: type, endpoint, path, thresholds. | `map(object({...}))` | `{}` | No |
| `cloudwatch_logs` | Query log group in us-east-1 (public zones). | `object({...})` | `{}` | No |
| `dnssec` | DNSSEC signing for public zones with a us-east-1 KMS key. | `object({...})` | `{}` | No |
| `kms` | Query log encryption in us-east-1: {} service encryption, create = true module key, key_id your key (ARN or ID). | `object({...})` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `zone_id` | Hosted zone ID. | No |
| `name` | Zone name. | No |
| `arn` | Hosted zone ARN. | No |
| `name_servers` | Name servers to delegate to. | No |
| `record_fqdns` | Record FQDNs by key. | No |
| `health_check_ids` | Health check IDs by key. | No |
| `ds_record` | DS record for the parent zone; null without DNSSEC. | No |
| `log_group_name` | Query log group name; null without query logging. | No |
| `log_group_arn` | Query log group ARN; null without query logging. | No |
| `kms_key_arn` | Query log key ARN; null for service encryption. | No |
