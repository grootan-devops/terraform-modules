# AWS DynamoDB Table Module

Scope: `workload`

A DynamoDB table with secure defaults: on-demand capacity, point-in-time recovery for 35 days, deletion protection,
server-side encryption with the AWS managed key (or a module or caller key), optional streams, secondary indexes,
global table replicas with a strong-consistency witness, Contributor Insights, and target-tracking autoscaling for
`PROVISIONED` tables. A caller only needs `name` and `hash_key`.

## Architecture & Managed Resources

- `aws_dynamodb_table.this`: `<application>-<environment>-<name>`; key attributes are derived from the table and index
  keys (type `S` unless listed in `attributes`).
- `module.encryption` ([`core/encryption`](../../core/encryption)): AWS managed key, module key or your key.
- `aws_appautoscaling_target.this`, `aws_appautoscaling_policy.this`: `PROVISIONED` tables only, read and write
  capacity of the table and every global secondary index (keys `table-read`, `index-<name>-write`...).
- `aws_dynamodb_contributor_insights.this`: opt-in, on the table and the listed indexes.

## Security & Compliance Guardrails

- **Encryption at rest:** server-side encryption is always on; no `kms` input uses the AWS managed key
  (`aws/dynamodb`). With a customer managed key every replica must name its own key in its Region.
- **Point-in-time recovery (DynamoDB.2):** always on, 35 days by default (1-35), on the table and every replica.
- **Deletion protection (DynamoDB.6):** on by default for the table and every replica.
- **Capacity (DynamoDB.1):** on demand by default; `PROVISIONED` tables and their indexes get target tracking unless
  `autoscaling.enabled = false`.
- **Tags (DynamoDB.5):** governance tags merged last; replicas propagate them.
- **Backups (DynamoDB.4):** add the table to an AWS Backup plan with [`storage/backup`](../../storage/backup).

The module key (`kms.create = true`) allows principals of this account to use it through DynamoDB in this Region only
(`kms:CallerAccount`, `kms:ViaService`), as the AWS managed key does. A key passed in `kms.key_id` needs the same grant.
With autoscaling, an apply resets table capacity to `provisioned_capacity` until the next scaling action; keep it at
the minimum you accept.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "dynamodb" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/database/dynamodb?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "sessions"
  hash_key    = "session_id"
}
```

### Complete Production Example

```hcl
module "dynamodb" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/database/dynamodb?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "orders"
  hash_key    = "account_id"
  range_key   = "order_id"
  attributes  = { created_at = "N" }
  kms         = { create = true }
  stream      = { enabled = true }

  billing_mode         = "PROVISIONED"
  provisioned_capacity = { read = 20, write = 10 }
  autoscaling          = { max_read_capacity = 400, max_write_capacity = 200 }

  global_secondary_indexes = {
    by_status = { hash_key = "status", range_key = "created_at" }
  }

  replicas = {
    frankfurt = { region_name = "eu-central-1", kms_key_arn = module.orders_key_frankfurt.arn }
  }
}

module "orders_consumer" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/compute/lambda?ref=<version>"

  application   = "core"
  environment   = "prod"
  name          = "orders-consumer"
  event_sources = { orders = { type = "dynamodb", arn = module.dynamodb.stream_arn } }
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | **Required** | Yes |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `name` | Table name. | `string` | **Required** | Yes |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `hash_key` | Partition key attribute. | `string` | **Required** | Yes |
| `range_key` | Sort key attribute. | `string` | `null` | No |
| `attributes` | Key attribute types by name: S, N or B; unlisted keys are S. | `map(string)` | `{}` | No |
| `billing_mode` | PAY_PER_REQUEST or PROVISIONED. | `string` | `"PAY_PER_REQUEST"` | No |
| `provisioned_capacity` | PROVISIONED read and write units; the autoscaling minimum. | `object({...})` | `{}` | No |
| `autoscaling` | Target tracking for PROVISIONED tables and indexes. | `object({...})` | `{}` | No |
| `table_class` | STANDARD or STANDARD_INFREQUENT_ACCESS. | `string` | `"STANDARD"` | No |
| `point_in_time_recovery_days` | Point-in-time recovery period in days. | `number` | `35` | No |
| `deletion_protection` | Block deletion of the table and replicas. | `bool` | `true` | No |
| `stream` | DynamoDB Streams. | `object({...})` | `{}` | No |
| `global_secondary_indexes` | Global secondary indexes by name. | `map(object({...}))` | `{}` | No |
| `local_secondary_indexes` | Local secondary indexes by name; set at creation only. | `map(object({...}))` | `{}` | No |
| `on_demand_throughput` | PAY_PER_REQUEST maximum read and write request units. | `object({...})` | `{}` | No |
| `warm_throughput` | Warm throughput in read and write units per second. | `object({...})` | `{}` | No |
| `kms` | Encryption: {} AWS managed key, create = true module key, key_id your key (ARN or ID). | `object({...})` | `{}` | No |
| `replicas` | Global table replicas by key: Region, key ARN, consistency mode. | `map(object({...}))` | `{}` | No |
| `witness_region` | Witness Region for strong consistency. | `string` | `null` | No |
| `contributor_insights` | Contributor Insights on the table and listed indexes. | `object({...})` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `id` | Table ID. | No |
| `arn` | Table ARN. | No |
| `name` | Table name. | No |
| `stream_arn` | Stream ARN; null without a stream. | No |
| `global_secondary_index_names` | Global secondary index names. | No |
| `kms_key_arn` | Key ARN in use; null for the AWS managed key. | No |
