# AWS RDS PostgreSQL Module

Scope: `workload`

An RDS for PostgreSQL instance with secure defaults: Multi-AZ, private, storage encrypted with the AWS managed key (or a
module or caller key), TLS forced, IAM database authentication, a master password managed in Secrets Manager,
14-day backups, deletion protection, Enhanced Monitoring every 60 seconds, Performance Insights, and `postgresql` and
`upgrade` logs in CloudWatch Logs for 365 days. Optional cross-Region backup replication and RDS event notifications.
A caller only needs `name`, `engine_version`, `vpc_id` and `subnet_ids`.

## Architecture & Managed Resources

- `aws_db_instance.this`: identifier `<application>-<environment>-<name>`, cut to 63 characters with a hash; a final
  snapshot `<identifier>-final-<timestamp>` on deletion.
- `aws_db_subnet_group.this`, `aws_db_parameter_group.this` (`<name>-postgres<major>` with `rds.force_ssl = 1`,
  replaced before the old one is removed on a major upgrade).
- `module.security_group` ([`network/security-group`](../../../network/security-group)): ingress on `port` from
  `security_group.ingress_*`; egress only to `security_group.egress_cidr_blocks` (empty by default; set it for
  extensions that call out, such as `aws_s3` or `aws_lambda`).
- `module.monitoring_role` ([`security/iam-role`](../../../security/iam-role)): `<...>-monitoring-<region>` with
  `AmazonRDSEnhancedMonitoringRole`, trusted by `monitoring.rds.amazonaws.com` for this account and instance only.
- `module.log_group` ([`observability/log-group`](../../../observability/log-group)):
  `/aws/rds/instance/<identifier>/<export>`, created before the instance.
- `aws_cloudwatch_query_definition.recent_errors`, `.slow_queries`: Logs Insights queries on the PostgreSQL log.
- `aws_db_instance_automated_backups_replication.this`: `backup_replication.enabled`, through the resource `region`.
- `aws_db_event_subscription.this`: `event_subscription.enabled`, instance events and parameter group changes.
- `module.encryption` ([`core/encryption`](../../../core/encryption)): AWS managed key, module key or your key.
- `module.alarms` ([`observability/cloudwatch-alarms`](../../../observability/cloudwatch-alarms)): built-in alarms, on
  by default; see [Built-in Alarms](#built-in-alarms).

## Security & Compliance Guardrails

- **Private and encrypted (RDS.2, RDS.3, RDS.38):** `publicly_accessible = false`; storage, Performance Insights,
  the master secret and logs use the module key when one is set; `rds.force_ssl = 1` cannot be overridden.
- **Credentials (RDS.10, RDS.25):** IAM authentication on; master user `dbadmin` (default admin names rejected);
  the password is generated and rotated in Secrets Manager, or sent write-only with `password_wo` (never in state).
- **Resilience (RDS.5, RDS.8, RDS.11, RDS.17):** Multi-AZ, deletion protection, 14-day backups (7-35), final snapshot,
  tags copied to snapshots.
- **Monitoring (RDS.6, RDS.9, RDS.36, CloudWatch.16):** Enhanced Monitoring (1-60 s, never off), Performance
  Insights, `postgresql` export required, log groups kept 365 days with deletion protection.
- **Patching (RDS.13):** automatic minor version upgrades; major upgrades are never applied implicitly.
  `engine_version` takes a major version only, so automatic minor upgrades never show as drift.
- **Supported versions:** PostgreSQL 15 or later (13 and 14 leave standard support); RDS Extended Support is off
  (`extended_support = false`), so an instance is upgraded when its major version leaves standard support instead of
  being billed for Extended Support.
- **Events (RDS.20, RDS.21):** `event_subscription` sends instance events (including maintenance, configuration change
  and failure) and parameter group changes to an SNS topic. The topic policy and its key policy must allow
  `events.rds.amazonaws.com`; with [`alarm-routing`](../../../observability/alarm-routing), add it to
  `additional_publisher_service_principals`, or no event arrives.
- **Network:** `/0` ingress rejected; no egress unless `egress_cidr_blocks` is set.
- **Backups (RDS.26):** add the instance to an AWS Backup plan with [`storage/backup`](../../../storage/backup).

The module key (`kms.create = true`) lets principals of this account use it through RDS and Secrets Manager in this
Region (`kms:CallerAccount`, `kms:ViaService`) and lets CloudWatch Logs use it for this instance's log groups. A key
passed in `kms.key_id` needs the same grants. The instance metric alarms are built in
([Built-in Alarms](#built-in-alarms)); metric filters on the logs belong to
[`observability/cloudwatch-alarms`](../../../observability/cloudwatch-alarms) (`log_metric_filters` with the
`log_group_names` output). The default port is the engine default (RDS.23); set `port` to change it.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "db" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/database/rds/postgres?ref=<version>"

  application    = "core"
  environment    = "prod"
  name           = "orders"
  engine_version = "18"
  vpc_id         = "vpc-0a1b2c3d4e5f67890"
  subnet_ids     = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
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
  instance_class = "db.r8g.large"
  storage        = { allocated_storage = 100, max_allocated_storage = 500 }
  parameters     = { log_min_duration_statement = { value = "500" } }
  kms            = { create = true }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
  security_group = {
    ingress_security_group_ids = [module.proxy.security_group_id]
  }

  backup_replication = { enabled = true, region = "eu-central-1", kms_key_arn = module.backup_key_frankfurt.arn }
  event_subscription = { enabled = true, sns_topic_arn = module.alarm_routing.topic_arns["eu-west-1"]["critical"] }
}

module "alarm_routing" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/observability/alarm-routing?ref=<version>"

  environment                             = "prod"
  regions                                 = ["eu-west-1"]
  email_subscriptions                     = { critical = ["dba@example.com"] }
  additional_publisher_service_principals = ["events.rds.amazonaws.com"]
}
```

### Major Version Upgrade

Set the next major version together with `allow_major_version_upgrade = true` and `apply_immediately = true`. The
module creates the new `postgres<major>` parameter group first, moves the instance to it and then deletes the old
group, which RDS only allows once the instance has left it, so the change cannot wait for the maintenance window:

```hcl
  engine_version              = "19"
  allow_major_version_upgrade = true
  apply_immediately           = true
```

With `extended_support = false`, RDS upgrades an instance whose major version leaves standard support. Set
`engine_version` to the version RDS moved it to; the next plan creates the matching `postgres<major>` parameter group
and moves the instance to it.

### Built-in Alarms

The `rds_instances` preset of [`observability/cloudwatch-alarms`](../../../observability/cloudwatch-alarms) is on by
default: `rds-instance-cpu` (80 %), `rds-instance-free-storage` (below 20 % of `storage.allocated_storage`; storage
autoscaling does not move it), `rds-instance-read-latency-p99` and `rds-instance-write-latency-p99` (20 ms).
`rds-instance-freeable-memory` and `rds-instance-connections` (`database_connections`) are opt-in and need a
`threshold`. Without `topic_arns` the alarms have no actions; `alarms = { enabled = false }` creates none.

```hcl
module "alarm_routing" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/observability/alarm-routing?ref=<version>"

  environment = "prod"
}

module "db" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/database/rds/postgres?ref=<version>"

  application    = "core"
  environment    = "prod"
  name           = "orders"
  engine_version = "18"
  vpc_id         = module.vpc.vpc_id
  subnet_ids     = module.vpc.private_subnet_ids

  alarms = {
    topic_arns = module.alarm_routing.topic_arns["eu-west-1"]
    overrides = {
      cpu              = { threshold = 90 }
      read_latency_p99 = { enabled = false }
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
| `name` | Instance name. | `string` | **Required** | Yes |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `engine_version` | PostgreSQL major version; minor versions follow automatic upgrades. | `string` | **Required** | Yes |
| `instance_class` | Instance class. | `string` | `"db.t4g.medium"` | No |
| `multi_az` | Multi-AZ standby. | `bool` | `true` | No |
| `storage` | Storage: size, autoscaling limit (0: off), type, IOPS, throughput. | `object({...})` | `{}` | No |
| `parameters` | DB parameters by name; rds.force_ssl is fixed at 1. | `map(object({...}))` | `{}` | No |
| `credential` | Master user; password managed in Secrets Manager unless password_wo is set. | `object({...})` | `{}` | No |
| `password_wo` | Write-only master password. | `string` | `null` | No |
| `password_wo_version` | Master password version; change it to send a new password. | `number` | `null` | No |
| `vpc_id` | VPC ID. | `string` | **Required** | Yes |
| `subnet_ids` | Private subnet IDs in two or more AZs. | `list(string)` | **Required** | Yes |
| `port` | Database port. | `number` | `5432` | No |
| `security_group` | Security group: ingress sources, egress and extra groups. | `object({...})` | `{}` | No |
| `kms` | Encryption: {} AWS managed key, create = true module key, key_id your key (ARN or ID). | `object({...})` | `{}` | No |
| `allow_major_version_upgrade` | Allow an engine_version change to the next major version. | `bool` | `false` | No |
| `apply_immediately` | Apply changes now instead of in the maintenance window. | `bool` | `false` | No |
| `extended_support` | Enrol in paid RDS Extended Support after standard support ends. | `bool` | `false` | No |
| `deletion_protection` | Block deletion of the instance. | `bool` | `true` | No |
| `backup_retention_period` | Automated backup retention in days. | `number` | `14` | No |
| `backup_replication` | Automated backup replication to another Region with a key there. | `object({...})` | `{}` | No |
| `monitoring_interval` | Enhanced Monitoring interval in seconds. | `number` | `60` | No |
| `iam_role` | Enhanced Monitoring role: extend it or bring your own. | `object({...})` | `{}` | No |
| `performance_insights_retention_period` | Performance Insights retention in days: 7, 731 or a multiple of 31. | `number` | `7` | No |
| `cloudwatch_logs` | Log exports and their log groups. | `object({...})` | `{}` | No |
| `event_subscription` | RDS event notifications to an SNS topic. | `object({...})` | `{}` | No |
| `alarms` | Built-in CloudWatch alarms: switch, topics by severity, per-alarm overrides. | `object({...})` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `id` | DB instance identifier (DBInstanceIdentifier dimension). | No |
| `arn` | DB instance ARN. | No |
| `resource_id` | DB resource ID for rds-db:connect policies. | No |
| `address` | Hostname. | No |
| `endpoint` | Endpoint (host:port). | No |
| `port` | Port. | No |
| `security_group_id` | Module security group ID; null when not created. | No |
| `master_user_secret_arn` | Secrets Manager secret of the master user; null with password_wo. | No |
| `monitoring_role_arn` | Enhanced Monitoring role ARN. | No |
| `log_group_names` | Log group names by export. | No |
| `kms_key_arn` | Key ARN in use; null for the AWS managed key. | No |
| `alarm_arns` | Alarm ARN by key. | No |
| `alarm_names` | Alarm name by key. | No |
