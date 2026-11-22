# AWS RDS Proxy Module

Scope: `workload`

An RDS Proxy in front of one RDS DB instance: TLS required, clients authenticate with IAM by default, the proxy reads
the database credentials from Secrets Manager through its own role, connection pool settings on the default target
group, a security group that admits only the listed clients and reaches only the database and AWS APIs, and optional
extra read/write endpoints and a pre-created log group.

## Architecture & Managed Resources

- `aws_db_proxy.this`: `<application>-<environment>-<name>`, cut to 63 characters with a hash.
- `aws_db_proxy_default_target_group.this`, `aws_db_proxy_target.this`: the DB instance `target.db_instance_identifier`.
- `module.role` ([`security/iam-role`](../../../security/iam-role)): `<...>-proxy-<region>`, trusted by
  `rds.amazonaws.com`.
- `module.security_group` ([`network/security-group`](../../../network/security-group)): ingress on the engine port
  (5432, 3306 or 1433) from `security_group.ingress_*`; egress to `target.security_group_ids` on the database port and
  HTTPS to `security_group.egress_cidr_blocks`.
- `aws_db_proxy_endpoint.this`: `endpoints`, `<proxy>-<key>`, read/write.
- `module.log_group` ([`observability/log-group`](../../../observability/log-group)): opt-in
  `/aws/rds/proxy/<proxy>`, created before the proxy.
- `module.alarms` ([`observability/cloudwatch-alarms`](../../../observability/cloudwatch-alarms)): built-in alarms, on
  by default; see [Built-in Alarms](#built-in-alarms).

## Security & Compliance Guardrails

- **TLS (RDS.43):** `require_tls = true`, not configurable.
- **Client authentication:** `auth[*].iam_auth = "REQUIRED"` by default; `DISABLED` allows database passwords,
  `ENABLED` is accepted for SQL Server only. `default_auth_scheme = "IAM_AUTH"` uses IAM end to end; add the
  `rds-db:connect` statement to `iam_role.policy_statements`. Clients grant themselves `rds-db:connect` on
  `"${db_user_arn_prefix}/<db user>"` and connect on `port`.
- **Least privilege:** the role reads only the `auth` secrets and decrypts them only through Secrets Manager in this
  Region (`kms:ViaService`).
- **Network:** `/0` ingress rejected. Egress reaches `target.security_group_ids` on the target port (at least one
  group is required while the module creates its security group) and AWS APIs (Secrets Manager, KMS, STS) on TCP 443
  only. The default HTTPS destination `0.0.0.0/0` covers NAT gateways (Trivy suppression `AVD-AWS-0104`);
  set `security_group.egress_cidr_blocks` to the VPC CIDR when interface endpoints serve those APIs.
- **Logs:** RDS Proxy otherwise creates its own log group without retention or a key. The `/aws/rds/proxy/<proxy>`
  name is observed service behaviour, not documented, so the group is opt-in (`cloudwatch_logs.enabled`); on an
  existing proxy, import the group first.

The proxy role trusts `rds.amazonaws.com` without `aws:SourceArn`/`aws:SourceAccount` conditions: the RDS Proxy
setup guide documents none. The proxy has no data at rest, so it takes no `kms` input; `cloudwatch_logs.kms_key_arn`
encrypts the log group.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "proxy" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/database/rds/proxy?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "orders"
  vpc_id      = "vpc-0a1b2c3d4e5f67890"
  subnet_ids  = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  target      = { db_instance_identifier = "core-prod-orders", security_group_ids = ["sg-0dddddddddddddddd"] }
  auth        = [{ secret_arn = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:rds!db-1234-AbCdEf" }]
}
```

### Complete Production Example

```hcl
module "db" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/database/rds/postgres?ref=<version>"

  application    = "core"
  environment    = "prod"
  name           = "orders"
  engine_version = "18"
  vpc_id         = module.vpc.vpc_id
  subnet_ids     = module.vpc.private_subnet_ids
  security_group = {
    ingress_security_group_ids = [module.proxy.security_group_id]
  }
}

module "proxy" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/database/rds/proxy?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "orders"
  vpc_id      = module.vpc.vpc_id
  subnet_ids  = module.vpc.private_subnet_ids

  target = {
    db_instance_identifier = module.db.id
    port                   = module.db.port
    security_group_ids     = [module.db.security_group_id]
  }
  auth = [{ secret_arn = module.db.master_user_secret_arn }]

  security_group = {
    ingress_security_group_ids = [module.api.security_group_id]
    egress_cidr_blocks         = [module.vpc.cidr_block]
  }
  connection_pool = { max_connections_percent = 90 }
  cloudwatch_logs = { enabled = true }
  endpoints       = { reporting = {} }
}
```

### Built-in Alarms

The `rds_proxies` preset of [`observability/cloudwatch-alarms`](../../../observability/cloudwatch-alarms) is on by
default: `rdsproxy-proxy-connection-setup-failures` and `rdsproxy-proxy-client-auth-failures` (critical, any failure)
and `rdsproxy-proxy-borrowed-connections` (pool saturation above 80 %). `rdsproxy-proxy-client-connections` is opt-in
and needs a `threshold`. Without `topic_arns` the alarms have no actions; `alarms = { enabled = false }` creates none.

```hcl
module "alarm_routing" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/observability/alarm-routing?ref=<version>"

  environment = "prod"
}

module "proxy" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/database/rds/proxy?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "orders"
  vpc_id      = module.vpc.vpc_id
  subnet_ids  = module.vpc.private_subnet_ids
  target      = { db_instance_identifier = module.db.id, security_group_ids = [module.db.security_group_id] }
  auth        = [{ secret_arn = module.db.master_user_secret_arn }]

  alarms = {
    topic_arns = module.alarm_routing.topic_arns["eu-west-1"]
    overrides = {
      borrowed_connections = { threshold = 90 }
      client_auth_failures = { enabled = false }
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
| `name` | Proxy name. | `string` | **Required** | Yes |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `engine_family` | POSTGRESQL, MYSQL or SQLSERVER. | `string` | `"POSTGRESQL"` | No |
| `target` | Target DB instance, its port (null: engine default) and security groups. | `object({...})` | **Required** | Yes |
| `vpc_id` | VPC ID. | `string` | **Required** | Yes |
| `subnet_ids` | Private subnet IDs in two or more AZs. | `list(string)` | **Required** | Yes |
| `security_group` | Security group: ingress sources, HTTPS egress to AWS APIs and extra groups. | `object({...})` | `{}` | No |
| `default_auth_scheme` | NONE (secrets to the database) or IAM_AUTH (end-to-end IAM). | `string` | `"NONE"` | No |
| `auth` | Database secrets; clients must use IAM auth unless iam_auth = DISABLED. | `list(object({...}))` | `[]` | No |
| `idle_client_timeout` | Idle client timeout in seconds (1-28800). | `number` | `1800` | No |
| `debug_logging` | Log SQL statement details. | `bool` | `false` | No |
| `connection_pool` | Connection pool of the default target group. | `object({...})` | `{}` | No |
| `iam_role` | Proxy role: extend it or bring your own. | `object({...})` | `{}` | No |
| `cloudwatch_logs` | Pre-created proxy log group. | `object({...})` | `{}` | No |
| `endpoints` | Extra read/write endpoints by key; empty lists use the proxy subnets and groups. | `map(object({...}))` | `{}` | No |
| `alarms` | Built-in CloudWatch alarms: switch, topics by severity, per-alarm overrides. | `object({...})` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `id` | Proxy ID. | No |
| `arn` | Proxy ARN. | No |
| `name` | Proxy name (ProxyName dimension). | No |
| `endpoint` | Default endpoint. | No |
| `port` | Port the proxy listens on. | No |
| `resource_id` | Proxy resource ID (prx-...). | No |
| `db_user_arn_prefix` | rds-db:connect ARN prefix, without the user name. | No |
| `endpoints` | Extra endpoint hostnames by key. | No |
| `security_group_id` | Module security group ID; null when not created. | No |
| `role_arn` | Proxy role ARN. | No |
| `role_name` | Proxy role name; null for a role brought by the caller. | No |
| `log_group_name` | Log group name; null when not created. | No |
| `alarm_arns` | Alarm ARN by key. | No |
| `alarm_names` | Alarm name by key. | No |
