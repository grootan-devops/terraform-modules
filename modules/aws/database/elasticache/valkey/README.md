# AWS ElastiCache Valkey Module

Scope: `workload`

A Valkey replication group (cluster mode disabled) in private subnets: two nodes with automatic failover and Multi-AZ,
encryption at rest (AWS managed key, module key or your key) and TLS required, daily snapshots, slow and engine logs
in CloudWatch Logs, a security group that admits only the listed sources on the Valkey port, and optional RBAC or a
write-only AUTH token.

## Architecture & Managed Resources

- `aws_elasticache_replication_group.this`: ID `<application>-<environment>-<name>`, cut to 40 characters with a hash.
- `aws_elasticache_subnet_group.this`, `aws_elasticache_parameter_group.this` (`<name>-valkey<major>`, replaced
  before the old one is removed on a major upgrade).
- `module.security_group` ([`network/security-group`](../../../network/security-group)): ingress on `port` from
  `security_group.ingress_*`; no egress (nodes start no connections).
- `module.log_group` ([`observability/log-group`](../../../observability/log-group)):
  `/aws/elasticache/<id>/slow-log` and `/engine-log`.
- `module.encryption` ([`core/encryption`](../../../core/encryption)): AWS managed key, module key or your key.

## Security & Compliance Guardrails

- **Encryption (ElastiCache.4, ElastiCache.5):** at rest always on; TLS `required`.
- **High availability (ElastiCache.3):** two nodes by default; failover and Multi-AZ follow `num_cache_clusters > 1`.
- **Backups (ElastiCache.1):** 7-day snapshots by default (1-35), final snapshot on deletion.
- **Patching (ElastiCache.2):** automatic minor version upgrades.
- **Network (ElastiCache.7):** dedicated subnet group; `/0` ingress rejected; no egress rule.
- **Authentication:** an RBAC user group (`user_group_id`) or a write-only AUTH token (`auth_token_wo` with
  `auth_token_wo_version`) that never reaches state. Without either, only the network rules guard the port.
- **Logs:** slow and engine logs on by default, 365 days, deletion protection, the module key when one is set.

The module key (`kms.create = true`) lets principals of this account use it through ElastiCache in this Region
(`kms:CallerAccount`, `kms:ViaService`) and lets CloudWatch Logs use it for this group's log groups. A key passed in
`kms.key_id` needs the same grants. The deploying role needs the CloudWatch Logs log delivery permissions
(`logs:CreateLogDelivery` and related).

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "valkey" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/database/elasticache/valkey?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "cache"
  vpc_id      = "vpc-0a1b2c3d4e5f67890"
  subnet_ids  = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
}
```

### Complete Production Example

```hcl
module "valkey" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/database/elasticache/valkey?ref=<version>"

  application        = "core"
  environment        = "prod"
  name               = "sessions"
  node_type          = "cache.r8g.large"
  num_cache_clusters = 3
  kms                = { create = true }
  parameters         = { "maxmemory-policy" = "allkeys-lru" }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
  security_group = {
    ingress_security_group_ids = [module.api.security_group_id]
  }

  auth_token_wo         = ephemeral.aws_secretsmanager_secret_version.valkey_token.secret_string
  auth_token_wo_version = 1
}
```

### Alarms

This module has no built-in alarms. The `elasticache_clusters` preset of
[`observability/cloudwatch-alarms`](../../../observability/cloudwatch-alarms) keys its alarms by member cluster ID, and
`member_clusters` is only known after apply (and changes after a failover or a new replica count). Once the cache
exists, pass the IDs to `cloudwatch-alarms` directly:

```hcl
module "valkey_alarms" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/observability/cloudwatch-alarms?ref=<version>"

  application   = "core"
  environment   = "prod"
  name          = "sessions"
  notifications = { enabled = true, topic_arns = module.alarm_routing.topic_arns }

  elasticache_clusters = {
    sessions = {
      replication_group_id = module.valkey.id
      cache_cluster_ids    = ["core-prod-sessions-001", "core-prod-sessions-002", "core-prod-sessions-003"]
    }
  }
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | **Required** | Yes |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `name` | Replication group name. | `string` | **Required** | Yes |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `engine_version` | Valkey version (major.minor). | `string` | `"9.1"` | No |
| `node_type` | Node type. | `string` | `"cache.t4g.micro"` | No |
| `num_cache_clusters` | Nodes: primary plus replicas (1-6). | `number` | `2` | No |
| `port` | Port the nodes listen on. | `number` | `6379` | No |
| `parameters` | Parameter group values by name. | `map(string)` | `{}` | No |
| `snapshot_retention_limit` | Automatic snapshot retention in days. | `number` | `7` | No |
| `snapshot_window` | Daily UTC snapshot window (hh:mm-hh:mm). Null: AWS picks. | `string` | `null` | No |
| `user_group_id` | RBAC user group ID. | `string` | `null` | No |
| `auth_token_wo` | Write-only AUTH token. | `string` | `null` | No |
| `auth_token_wo_version` | AUTH token version; change it to send a new token. | `number` | `null` | No |
| `auth_token_update_strategy` | Token change: SET, ROTATE or DELETE. Null: ROTATE. | `string` | `null` | No |
| `kms` | Encryption: {} AWS managed key, create = true module key, key_id your key (ARN or ID). | `object({...})` | `{}` | No |
| `vpc_id` | VPC ID. | `string` | **Required** | Yes |
| `subnet_ids` | Private subnet IDs. | `list(string)` | **Required** | Yes |
| `security_group` | Security group: ingress sources and extra groups. | `object({...})` | `{}` | No |
| `cloudwatch_logs` | Slow and engine log delivery to CloudWatch Logs. | `object({...})` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `id` | Replication group ID (ReplicationGroupId dimension). | No |
| `arn` | Replication group ARN. | No |
| `primary_endpoint_address` | Primary endpoint address. | No |
| `reader_endpoint_address` | Reader endpoint address. | No |
| `port` | Port. | No |
| `member_clusters` | Cache cluster IDs (CacheClusterId dimension). | No |
| `security_group_id` | Module security group ID; null when not created. | No |
| `log_group_names` | Log group names by log type. | No |
| `kms_key_arn` | Key ARN in use; null for the AWS managed key. | No |
