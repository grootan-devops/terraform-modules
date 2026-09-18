# AWS RDS PostgreSQL Module

The `rds/postgres` module provisions enterprise-grade Amazon Relational Database Service (RDS) PostgreSQL instances compliant with CIS AWS Foundations Benchmarks. It enforces network isolation, mandatory KMS storage and log encryption, parameter-group SSL enforcement, and automated cross-region backup replication.

### Architecture & Managed Resources
- `aws_db_instance.this`: PostgreSQL primary instance.
- `aws_db_subnet_group.this`: Private DB subnet group.
- `aws_db_parameter_group.this`: Engine configuration with `rds.force_ssl = 1`.
- `aws_security_group.this`: Firewall restricting port 5432 ingress.
- `aws_cloudwatch_log_group.this`: KMS-encrypted database log streams (postgresql, upgrade).
- `aws_db_instance_automated_backups_replication.this`: Optional cross-region backup replication.

### Security & Compliance Guardrails
- **Zero Public Access**: `publicly_accessible = false` hardcoded.
- **SSL Enforced**: `rds.force_ssl = "1"` hardcoded in DB parameter group.
- **Mandatory KMS CMK**: Storage (`storage_encrypted = true`), Performance Insights, and CloudWatch logs encrypted with `kms_key_id`.
- **Accidental Deletion Safeguards**: `deletion_protection = true` and `auto_minor_version_upgrade = true`.

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
module "postgres" {
  source = "git::https://github.com/organization/terraform-modules.git//modules/aws/database/rds/postgres?ref=v1.0.0"

  providers = {
    aws         = aws
    aws.replica = aws.secondary
  }

  application = "core"
  environment = "prod"
  name        = "db"

  engine_version = "16.3"
  instance_class = "db.t4g.medium"
  multi_az       = true

  vpc_id     = "vpc-0a1b2c3d4e5f67890"
  subnet_ids = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  kms_key_id = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"

  credential = {
    username = "dbadmin"
    password = var.master_db_password
  }

  backup_retention_period = 30

  cloudwatch_logs = {
    retention_in_days = {
      postgresql        = 90
      upgrade           = 90
      iam-db-auth-error = 90
    }
    kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
  }
}
```

### Complete Production Example
```hcl
module "postgres" {
  source = "git::https://github.com/organization/terraform-modules.git//modules/aws/database/rds/postgres?ref=v1.0.0"

  providers = {
    aws         = aws
    aws.replica = aws.secondary
  }

  application = "finance"
  environment = "prod"
  name        = "transactional-db"

  engine_version = "16.3"
  instance_class = "db.r7g.2xlarge"
  multi_az       = true

  vpc_id     = "vpc-0a1b2c3d4e5f67890"
  subnet_ids = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  kms_key_id = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"

  storage = {
    allocated_storage     = 200
    max_allocated_storage = 2000
    storage_type          = "gp3"
    iops                  = 12000
    storage_throughput    = 500
  }

  credential = {
    username = "finance_admin"
    password = var.db_password
  }

  allowed_cidr_blocks = ["10.0.0.0/16"]

  backup_retention_period               = 35
  monitoring_interval                   = 60
  performance_insights_retention_period = 731

  cloudwatch_logs = {
    exports = ["postgresql", "upgrade"]
    retention_in_days = {
      postgresql        = 90
      upgrade           = 90
      iam-db-auth-error = 90
    }
    kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
  }

  enable_automated_backup_replication      = true
  automated_backup_replication_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/replica-key-id"

  parameters = [
    {
      name  = "shared_preload_libraries"
      value = "pg_stat_statements"
    }
  ]

  tags = {
    AuditLevel = "PCI-DSS-L1"
  }
}
```

---

## Inputs Specification

| Name | Description | Type | Default | Required |
|---|---|---|---|:---:|
| `name` | The name of the RDS instance | `string` | `null` | No |
| `application` | The name of the product | `string` | **Required** | Yes |
| `environment` | Deployment environment name (e.g. dev, staging, prod). | `string` | **Required** | Yes |
| `engine_version` | The engine version to use. Default is 18. | `string` | **Required** | Yes |
| `instance_class` | The instance type of the RDS instance | `string` | **Required** | Yes |
| `multi_az` | Specifies if the RDS instance is multi-AZ | `bool` | **Required** | Yes |
| `parameters` | A list of DB parameters (map) to apply | `list(map(string))` | `[]` | No |
| `storage` | Storage configuration for the RDS instance. | `object({...})` | `{}` | No |
| `credential` | Credentials for the master DB user. | `object({...})` | **Required** | Yes |
| `vpc_id` | The VPC ID where the RDS instance will be deployed | `string` | **Required** | Yes |
| `subnet_ids` | A list of VPC subnet IDs to deploy the RDS instance | `list(string)` | **Required** | Yes |
| `availability_zone` | The AZ for the RDS instance. Only use if multi_az is false. | `string` | `null` | No |
| `publicly_accessible` | Bool to control if instance is publicly accessible. | `bool` | `false` | No |
| `allowed_cidr_blocks` | List of CIDR blocks allowed to access the database | `list(string)` | `[]` | No |
| `egress_cidr_blocks` | List of CIDR blocks allowed for outbound traffic from the database | `list(string)` | `["0.0.0.0/0"]` | No |
| `kms_key_id` | The ARN for the KMS encryption key. Must be provided if storage_encrypted is true. | `string` | **Required** | Yes |
| `enable_automated_backup_replication` | Whether to enable automated backup replication to the secondary region. | `bool` | `true` | No |
| `automated_backup_replication_kms_key_arn` | KMS Key ARN in the destination region for automated backup replication. Must be provided if enable_automated_backup_replication is true. | `string` | `null` | No |
| `backup_retention_period` | The days to retain backups for. Must be between 1 and 35. | `number` | **Required** | Yes |
| `monitoring_interval` | The interval, in seconds, between points when Enhanced Monitoring metrics are collected. Valid Values: 0, 1, 5, 10, 15, 30, 60. | `number` | **Required** | Yes |
| `performance_insights_retention_period` | The amount of time in days to retain Performance Insights data. Valid values are 7, 731 (2 years) or a multiple of 31. | `number` | **Required** | Yes |
| `cloudwatch_logs` | CloudWatch logs configuration for RDS PostgreSQL. | `object({...})` | **Required** | Yes |
| `tags` | Additional tags to apply to all resources | `map(string)` | `{}` | No |


---

## Outputs Specification

| Name | Description | Sensitive |
|---|---|:---:|
| `id` | The RDS instance identifier | No |
| `username` | The master username for the database | No |
| `address` | The RDS instance hostname. | No |
| `port` | The RDS instance port. | No |

