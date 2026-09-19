# AWS RDS Proxy Module

The `rds/proxy` module manages Amazon RDS Proxy connection pooling pools for PostgreSQL workloads, mitigating connection exhaustion and reducing failover recovery times.

### Architecture & Managed Resources
- `aws_db_proxy.this`: RDS Proxy endpoint.
- `aws_db_proxy_default_target_group.this`: Manages connection pools and timeouts.
- `aws_db_proxy_target.this`: Associates the proxy with primary DB instances.
- `aws_iam_role.proxy`: IAM execution role authorized to decrypt Secrets Manager credentials.

### Security & Compliance Guardrails
- **TLS Enforced**: `require_tls = true` hardcoded.
- **Mandatory KMS Decrypt Authorization**: IAM role policy strictly scoped to decrypt with `kms_key_arn`.

---

## Requirements & Providers

| Requirement | Version |
|---|---|
| `terraform` | `>= 1.5.0` |
| `aws` | `>= 6.0.0, < 7.0.0` |

---

## Usage Examples

### Minimal Working Example
```hcl
module "rds_proxy" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/database/rds/proxy?ref=1.0.0"

  application   = "core"
  environment   = "prod"
  name          = "db-proxy"
  engine_family = "POSTGRESQL"

  vpc_id                 = "vpc-0a1b2c3d4e5f67890"
  subnet_ids             = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  db_instance_identifier = module.postgres.id
  kms_key_arn            = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
  auth_secrets           = [module.db_secret.arn]
}
```

### Complete Production Example
```hcl
module "rds_proxy" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/database/rds/proxy?ref=1.0.0"

  application   = "billing"
  environment   = "prod"
  name          = "pg-proxy"
  engine_family = "POSTGRESQL"

  vpc_id             = "vpc-0a1b2c3d4e5f67890"
  subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  security_group_ids = ["sg-0123456789abcdef0"]

  db_instance_identifier = module.postgres.id
  kms_key_arn            = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
  auth_secrets           = [module.db_secret.arn]

  connection_borrow_timeout = 120
  max_connections_percent   = 90
  max_idle_connections_percent = 50

  tags = {
    Tier = "ConnectionPooling"
  }
}
```

---

## Inputs Specification

| Name | Description | Type | Default | Required |
|---|---|---|---|:---:|
| `application` | The name of the product | `string` | **Required** | Yes |
| `environment` | Deployment environment name (e.g. dev, staging, prod). | `string` | **Required** | Yes |
| `name` | The name of the RDS proxy (optional). Will be used in combination with application and environment. | `string` | `null` | No |
| `tags` | A mapping of tags to assign to the resource. | `map(string)` | `{}` | No |
| `engine_family` | The kinds of databases that the proxy can connect to (MYSQL, POSTGRESQL, SQLSERVER). | `string` | **Required** | Yes |
| `kms_key_arn` | The ARN of the KMS key used to encrypt the database secret in Secrets Manager. Strictly required. | `string` | **Required** | Yes |
| `vpc_id` | The VPC ID where the RDS proxy security group will be created | `string` | **Required** | Yes |
| `vpc_subnet_ids` | One or more VPC subnet IDs to associate with the new proxy. | `list(string)` | **Required** | Yes |
| `allowed_cidr_blocks` | List of CIDR blocks allowed to access the database proxy | `list(string)` | `[]` | No |
| `debug_logging` | Whether the proxy includes detailed information about SQL statements in its logs. | `bool` | `false` | No |
| `default_auth_scheme` | Default authentication scheme that the proxy uses (NONE or IAM_AUTH). | `string` | `"NONE"` | No |
| `endpoint_network_type` | Network type of the DB proxy endpoint (IPV4, IPV6, DUAL). | `string` | `"IPV4"` | No |
| `idle_client_timeout` | The number of seconds that a connection to the proxy can be inactive before the proxy disconnects it. | `number` | `1800` | No |
| `target_connection_network_type` | Network type that the proxy uses to connect to the target database (IPV4 or IPV6). | `string` | `"IPV4"` | No |
| `auth_blocks` | Configuration block(s) with authorization mechanisms to connect to the associated instances or clusters. | `list(object({...}))` | `[]` | No |
| `connection_pool_config` | The settings that determine the size and behavior of the connection pool for the target group. | `object({...})` | `{}` | No |
| `db_instance_identifier` | DB instance identifier to register as a target. Either db_instance_identifier or db_cluster_identifier should be specified. | `string` | **Required** | Yes |
| `endpoints` | Map of endpoints to create for the proxy. | `map(object({...}))` | `{}` | No |


---

## Outputs Specification

| Name | Description | Sensitive |
|---|---|:---:|
| `endpoint` | Default RDS Proxy endpoint. | No |
| `arn` | RDS Proxy ARN. | No |

