# AWS Infrastructure Architecture & Standards Guide

This document defines the architecture, compliance baselines, cryptographic standards, module catalog, and consumption patterns for Amazon Web Services (AWS) infrastructure modules within this repository.

Every AWS module is located under [`modules/aws/`](modules/aws/) and engineered in strict alignment with the **AWS Well-Architected Framework**, **CIS AWS Foundations Benchmarks (v3.0)**, and organizational security policies.

---

## 1. AWS Module Catalog

All AWS modules are organized into functional domain categories under `modules/aws/`:

| Domain | Module Directory | Primary AWS Resources Managed | Compliance Baseline |
|---|---|---|:---:|
| **Compute** | [`modules/aws/compute/batch`](modules/aws/compute/batch) | `aws_batch_compute_environment`, `aws_batch_job_queue`, `aws_batch_job_definition` | SOC2 Type II |
| | [`modules/aws/compute/ecs`](modules/aws/compute/ecs) | `aws_ecs_cluster`, `aws_ecs_task_definition`, `aws_ecs_service` | AWS Container Security |
| | [`modules/aws/compute/eks`](modules/aws/compute/eks) | `aws_eks_cluster`, `aws_eks_node_group`, `aws_eks_addon` | CIS EKS Benchmark v1.4 |
| | [`modules/aws/compute/eks/cluster`](modules/aws/compute/eks/cluster) | Standalone Control Plane, Secrets Envelope Encryption, OIDC Provider | CIS EKS Control Plane |
| | [`modules/aws/compute/eks/node_group`](modules/aws/compute/eks/node_group) | Managed Node Group, IMDSv2 Launch Template, KMS EBS Encryption | CIS EKS Worker Nodes |
| | [`modules/aws/compute/lambda`](modules/aws/compute/lambda) | `aws_lambda_function`, `aws_lambda_alias`, `aws_cloudwatch_log_group` | CIS Serverless 1.1 |
| **Database** | [`modules/aws/database/dynamodb`](modules/aws/database/dynamodb) | `aws_dynamodb_table`, `aws_dynamodb_contributor_insights` | CIS DynamoDB 1.1 |
| | [`modules/aws/database/elasticache/valkey`](modules/aws/database/elasticache/valkey) | `aws_elasticache_replication_group`, `aws_elasticache_parameter_group` | PCI-DSS In-Transit |
| | [`modules/aws/database/rds/postgres`](modules/aws/database/rds/postgres) | `aws_db_instance`, `aws_db_parameter_group`, `aws_db_subnet_group` | CIS RDS 2.3.1 - 2.3.3 |
| | [`modules/aws/database/rds/proxy`](modules/aws/database/rds/proxy) | `aws_db_proxy`, `aws_db_proxy_default_target_group`, `aws_iam_role` | Connection Resilience |
| **Integration** | [`modules/aws/integration/api-gateway`](modules/aws/integration/api-gateway) | `aws_api_gateway_rest_api`, `aws_api_gateway_stage`, `aws_cloudwatch_log_group` | API Security Top 10 |
| | [`modules/aws/integration/eventbridge`](modules/aws/integration/eventbridge) | `aws_cloudwatch_event_bus`, `aws_cloudwatch_event_rule`, `aws_cloudwatch_event_target` | Enterprise Event Mesh |
| | [`modules/aws/integration/sqs`](modules/aws/integration/sqs) | `aws_sqs_queue`, `aws_sqs_queue_redrive_policy`, `aws_sqs_queue_policy` | Resilient Messaging |
| | [`modules/aws/integration/step-functions`](modules/aws/integration/step-functions) | `aws_sfn_state_machine`, `aws_cloudwatch_log_group`, `aws_iam_role` | Orchestration Security |
| **Network** | [`modules/aws/network/alb`](modules/aws/network/alb) | `aws_lb`, `aws_lb_listener`, `aws_lb_target_group` | AWS Well-Architected |
| | [`modules/aws/network/cloudfront`](modules/aws/network/cloudfront) | `aws_cloudfront_distribution`, `aws_cloudfront_origin_access_control` | CIS CloudFront 1.1 |
| | [`modules/aws/network/vpc`](modules/aws/network/vpc) | `aws_vpc`, `aws_subnet`, `aws_flow_log`, `aws_vpc_endpoint` | CIS VPC 3.1 - 3.9 |
| | [`modules/aws/network/waf`](modules/aws/network/waf) | `aws_wafv2_web_acl`, `aws_wafv2_ip_set`, `aws_wafv2_logging_configuration` | OWASP Top 10 |
| **Security** | [`modules/aws/security/cognito`](modules/aws/security/cognito) | `aws_cognito_user_pool`, `aws_cognito_user_pool_risk_configuration` | NIST SP 800-63B |
| | [`modules/aws/security/kms`](modules/aws/security/kms) | `aws_kms_key`, `aws_kms_alias`, `aws_kms_replica_key` | CIS KMS 2.8, 2.9 |
| | [`modules/aws/security/secrets-manager`](modules/aws/security/secrets-manager) | `aws_secretsmanager_secret`, `aws_secretsmanager_secret_rotation` | CIS Secrets 1.1 |
| **Storage** | [`modules/aws/storage/amplify`](modules/aws/storage/amplify) | `aws_amplify_app`, `aws_amplify_branch`, `aws_amplify_domain_association` | Static Web Baseline |
| | [`modules/aws/storage/efs`](modules/aws/storage/efs) | `aws_efs_file_system`, `aws_efs_mount_target`, `aws_efs_file_system_policy` | CIS EFS 1.1 |
| | [`modules/aws/storage/s3`](modules/aws/storage/s3) | `aws_s3_bucket`, `aws_s3_bucket_public_access_block`, `aws_s3_bucket_policy` | CIS S3 2.1.1 - 2.1.5 |

---

## 2. Mandatory Cryptographic Key Governance (KMS CMK)

Silent fallbacks to AWS default managed keys (`aws/s3`, `aws/rds`, `aws/sqs`) are strictly prohibited across all modules:

1. **Explicit Customer Managed Keys Only**: Every module supporting data-at-rest encryption strictly requires an explicit Customer Managed Key (`kms_key_arn` or `kms_key_id`) as a mandatory, non-default variable.
2. **Annual Key Rotation**: Customer managed keys provisioned via `modules/aws/security/kms` enforce automated annual rotation (`enable_key_rotation = true`).
3. **SQS Key Evasion Prevention**: SQS queues enforce `kms_master_key_id = var.kms_key_arn` and disable `sqs_managed_sse_enabled = false` to guarantee cryptographic boundaries.
4. **S3 Bucket Key Optimization**: S3 buckets enforce S3 Bucket Keys (`bucket_key_enabled = true`), reducing AWS KMS API request costs by up to 99% for high-throughput operations.
5. **Log Group CMK Encryption**: All CloudWatch log groups created across modules enforce customer managed key encryption (`kms_key_id = var.kms_key_arn`).

---

## 3. CIS Security & Network Hardening Baselines

1. **IMDSv2 Enforced**: EKS compute instances and EC2 launch templates strictly enforce `http_tokens = "required"` and `http_put_response_hop_limit = 1` to prevent SSRF credential harvesting.
2. **TLS 1.2+ Enforced**:
   - S3 bucket policies inject explicit `Deny` statements for `aws:SecureTransport = false` and `s3:TlsVersion < 1.2`.
   - Application Load Balancers enforce `ELBSecurityPolicy-TLS13-1-2-2021-06`.
   - CloudFront distributions enforce `minimum_protocol_version = "TLSv1.2_2021"`.
   - EFS file systems enforce in-transit TLS transport policies.
3. **Private-by-Default Networking**:
   - RDS instances hardcode `publicly_accessible = false` and enforce `rds.force_ssl = 1` in custom parameter groups.
   - ElastiCache clusters are isolated in private database subnets with in-transit TLS encryption.
   - EKS control plane API server endpoints require explicit private access configuration.
4. **Fail-Safe Immutability**:
   - RDS databases enforce `deletion_protection = true`.
   - S3 buckets enforce object versioning (`enable_versioning = true`).
   - VPC Flow Logs are enabled by default with 90-day retention to a KMS-encrypted CloudWatch log group.

---

## 4. Resource Naming & Tagging Standards

Every module implements deterministic naming and centralized tagging via `locals.tf`:

### Resource Naming Formula
```
${var.application}-${var.environment}-${var.name}
```
*(If `var.name` is null or empty, resources resolve cleanly to `${var.application}-${var.environment}`)*.

### Standard Tags
All resources automatically inherit the following tags merged with any user-provided `var.tags`:
- `Application`: Name of the system or application service.
- `Environment`: Target deployment tier (`dev`, `staging`, `prod`, validated via regex `^[a-z0-9-]+$`).
- `Name`: Full rendered resource name.

---

## 5. End-to-End Native Terraform Composition

The following complete configuration demonstrates how to compose the categorized modules into a secure, multi-tier production stack:

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0, < 7.0.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

# 1. Primary Encryption Key (Security)
module "kms" {
  source = "git::https://github.com/organization/terraform-modules.git//modules/aws/security/kms?ref=v1.0.0"

  application             = "core"
  environment             = "prod"
  name                    = "primary"
  description             = "Primary customer managed key for core production stack"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

# 2. Network Infrastructure (Network)
module "vpc" {
  source = "git::https://github.com/organization/terraform-modules.git//modules/aws/network/vpc?ref=v1.0.0"

  application = "core"
  environment = "prod"
  name        = "network"

  cidr_block                  = "10.0.0.0/16"
  aws_availability_zone_names = ["us-west-2a", "us-west-2b", "us-west-2c"]
  public_subnet_cidrs         = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnet_cidrs        = ["10.0.10.0/24", "10.0.20.0/24", "10.0.30.0/24"]
  intra_subnet_cidrs          = ["10.0.100.0/24", "10.0.200.0/24", "10.0.300.0/24"]

  kms_key_arn = module.kms.key_arn

  cloudwatch_logs = {
    enabled           = true
    exports           = ["vpc_flow"]
    retention_in_days = { vpc_flow = 90 }
    kms_key_arn       = module.kms.key_arn
  }
}

# 3. Encrypted Object Storage (Storage)
module "app_storage" {
  source = "git::https://github.com/organization/terraform-modules.git//modules/aws/storage/s3?ref=v1.0.0"

  application = "core"
  environment = "prod"
  name        = "app-data"

  kms_key_arn       = module.kms.key_arn
  enable_versioning = true
}

# 4. Managed Relational Database (Database)
module "db" {
  source = "git::https://github.com/organization/terraform-modules.git//modules/aws/database/rds/postgres?ref=v1.0.0"

  application = "core"
  environment = "prod"
  name        = "app-db"

  engine_version = "16.3"
  instance_class = "db.r7g.large"
  multi_az       = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.intra_subnet_ids
  kms_key_id = module.kms.key_arn

  credential = {
    username = "dbadmin"
    password = var.db_master_password
  }

  storage = {
    allocated_storage     = 100
    max_allocated_storage = 500
    storage_type          = "gp3"
    iops                  = 3000
    storage_throughput    = 125
  }

  cloudwatch_logs = {
    exports           = ["postgresql", "upgrade"]
    retention_in_days = { postgresql = 90, upgrade = 90 }
    kms_key_arn       = module.kms.key_arn
  }
}

# 5. Containerized Compute Workload (Compute)
module "ecs" {
  source = "git::https://github.com/organization/terraform-modules.git//modules/aws/compute/ecs?ref=v1.0.0"

  application = "core"
  environment = "prod"
  name        = "cluster"

  kms_key_arn = module.kms.key_arn
  vpc_id      = module.vpc.vpc_id

  services = {
    backend-api = {
      cpu               = 1024
      memory            = 2048
      subnet_ids        = module.vpc.private_subnet_ids
      assign_public_ip  = false
      container_port    = 8080
      image             = "123456789012.dkr.ecr.us-west-2.amazonaws.com/api:v1.2.0"
      desired_count     = 3
      environment_variables = {
        DB_HOST   = module.db.endpoint
        S3_BUCKET = module.app_storage.bucket_name
      }
    }
  }
}

# 6. Safe Direct Resource: Route53 Private DNS Record
resource "aws_route53_record" "db_internal" {
  zone_id = "Z0123456789ABCDEF012"
  name    = "db.internal.company.com"
  type    = "CNAME"
  ttl     = 300
  records = [module.db.endpoint]
}
```

---

## 6. Terragrunt AWS Architecture (Plainr Pattern)

To achieve maximum simplicity, maintainability, and zero code duplication across environments (`dev`, `qa`, `prod`), this module library is designed to be orchestrated using the **Plainr Terragrunt Architecture**:
- A single canonical Terraform composition stack in **`resources/`**.
- A master **`root.hcl`** managing remote state and provider generation.
- Thin environment directories (**`dev/`**, **`qa/`**, **`prod/`**) that invoke `..//resources` with environment-specific inputs.

```
infra-live/
├── root.hcl                          # Root Terragrunt configuration (remote state & provider generator)
├── resources/                        # Single canonical Terraform composition layer
│   ├── alb.tf                        # Calls modules/aws/network/alb
│   ├── cognito.tf                    # Calls modules/aws/security/cognito
│   ├── ecs.tf                        # Calls modules/aws/compute/ecs
│   ├── iam.tf                        # Safe direct resources (roles, policies)
│   ├── kms.tf                        # Calls modules/aws/security/kms
│   ├── rds.tf                        # Calls modules/aws/database/rds/postgres
│   ├── route53.tf                    # Safe direct resources (DNS records)
│   ├── s3.tf                         # Calls modules/aws/storage/s3
│   ├── vpc.tf                        # Calls modules/aws/network/vpc
│   ├── variables.tf                  # Parameterized environment variables
│   └── outputs.tf                    # Stack outputs
├── dev/
│   └── terragrunt.hcl                # Invocates resources/ with dev inputs
├── qa/
│   └── terragrunt.hcl                # Invocates resources/ with qa inputs
└── prod/
    └── terragrunt.hcl                # Invocates resources/ with prod inputs
```

### 6.1. Master Root Configuration: `root.hcl`
The root `root.hcl` manages S3 remote state storage with DynamoDB state locking and automatically generates standardized provider configurations across all sibling environment directories:

```hcl
# root.hcl
remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket         = "company-tf-state-storage-prod"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-2"
    encrypt        = true
    kms_key_id     = "arn:aws:kms:us-east-2:123456789012:key/company-global-state-key"
    dynamodb_table = "company-tf-locks"
  }
}

generate "provider" {
  path      = "provider_override.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0, < 7.0.0"
    }
  }
}

provider "aws" {
  region = "us-east-2"
  default_tags {
    tags = {
      Orchestrator = "Terragrunt"
      Repository   = "infra-live"
      Environment  = "${path_relative_to_include()}"
    }
  }
}

provider "aws" {
  alias  = "replica"
  region = "us-east-1"
}
EOF
}
```

---

### 6.2. The Canonical Composition Layer: `resources/`
The `resources/` directory wires together the modular building blocks from `modules/aws/` and adds safe direct resources (IAM policies, DNS records).

#### `resources/kms.tf`
```hcl
module "kms" {
  source = "../modules/aws/security/kms"

  application             = var.application
  environment             = var.environment
  name                    = "primary"
  description             = "KMS CMK for ${var.application}-${var.environment}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}
```

#### `resources/vpc.tf`
```hcl
module "vpc" {
  source = "../modules/aws/network/vpc"

  application                 = var.application
  environment                 = var.environment
  name                        = "network"
  cidr_block                  = var.vpc_cidr
  aws_availability_zone_names = var.availability_zones
  public_subnet_cidrs         = var.public_subnet_cidrs
  private_subnet_cidrs        = var.private_subnet_cidrs
  intra_subnet_cidrs          = var.intra_subnet_cidrs
  kms_key_arn                 = module.kms.key_arn

  cloudwatch_logs = {
    enabled           = true
    exports           = ["vpc_flow"]
    retention_in_days = { vpc_flow = var.log_retention_days }
    kms_key_arn       = module.kms.key_arn
  }
}
```

#### `resources/rds.tf`
```hcl
module "rds" {
  source = "../modules/aws/database/rds/postgres"

  application    = var.application
  environment    = var.environment
  name           = "db"
  engine_version = "16.3"
  instance_class = var.db_instance_class
  multi_az       = var.db_multi_az

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.intra_subnet_ids
  kms_key_id = module.kms.key_arn

  credential = {
    username = var.db_username
    password = var.db_password
  }

  storage = {
    allocated_storage     = var.db_allocated_storage
    max_allocated_storage = var.db_max_allocated_storage
    storage_type          = "gp3"
    iops                  = var.db_iops
    storage_throughput    = var.db_throughput
  }

  backup_retention_period = var.db_backup_retention_period

  cloudwatch_logs = {
    exports           = ["postgresql", "upgrade"]
    retention_in_days = { postgresql = var.log_retention_days, upgrade = var.log_retention_days }
    kms_key_arn       = module.kms.key_arn
  }
}
```

---

### 6.3. Environment Invocations: `dev/`, `qa/`, `prod/`

#### `dev/terragrunt.hcl`
```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "..//resources"
}

inputs = {
  application = "company"
  environment = "dev"

  vpc_cidr             = "10.10.0.0/16"
  availability_zones   = ["us-east-2a", "us-east-2b"]
  public_subnet_cidrs  = ["10.10.1.0/24", "10.10.2.0/24"]
  private_subnet_cidrs = ["10.10.10.0/24", "10.10.20.0/24"]
  intra_subnet_cidrs   = ["10.10.100.0/24", "10.10.200.0/24"]

  db_instance_class         = "db.t4g.medium"
  db_multi_az               = false
  db_allocated_storage      = 20
  db_max_allocated_storage  = 100
  db_iops                   = 3000
  db_throughput             = 125
  db_username               = "dbadmin"
  db_password               = get_env("DEV_DB_PASSWORD")
  db_backup_retention_period = 7

  log_retention_days = 7
}
```

#### `prod/terragrunt.hcl`
```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "..//resources"
}

inputs = {
  application = "company"
  environment = "prod"

  vpc_cidr             = "10.0.0.0/16"
  availability_zones   = ["us-east-2a", "us-east-2b", "us-east-2c"]
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.20.0/24", "10.0.30.0/24"]
  intra_subnet_cidrs   = ["10.0.100.0/24", "10.0.200.0/24", "10.0.300.0/24"]

  db_instance_class         = "db.r7g.xlarge"
  db_multi_az               = true
  db_allocated_storage      = 100
  db_max_allocated_storage  = 1000
  db_iops                   = 6000
  db_throughput             = 250
  db_username               = "dbadmin"
  db_password               = get_env("PROD_DB_PASSWORD")
  db_backup_retention_period = 35

  log_retention_days = 90
}
```
