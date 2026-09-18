# Terraform Modules Library

Production-grade, modular Terraform library for provisioning secure, compliant cloud infrastructure.

---

## 1. Repository Layout

Modules are grouped by cloud provider and domain under `modules/`:

```
terraform-modules/
├── .gitignore                          # Artifact exclusions
├── AWS.md                              # AWS architecture, CIS baselines & module catalog
├── README.md                           # Repository structure, consumption & Terragrunt guide
└── modules/
    └── aws/                            # AWS infrastructure modules
        ├── compute/                    # batch, ecs, eks, lambda
        ├── database/                   # dynamodb, elasticache/valkey, rds/postgres, rds/proxy
        ├── integration/                # api-gateway, eventbridge, sqs, step-functions
        ├── network/                    # alb, cloudfront, vpc, waf
        ├── security/                   # cognito, kms, secrets-manager
        └── storage/                    # amplify, efs, s3
```

---

## 2. Module Consumption

### Native Terraform
Reference modules using semantic version tags in Git (recommended for remote repos) or relative paths (for monorepos):

```hcl
# Remote Git reference (Semantic Tagging)
module "s3" {
  source = "git::https://github.com/organization/terraform-modules.git//modules/aws/storage/s3?ref=v1.0.0"

  application = "core"
  environment = "prod"
  name        = "assets"
  kms_key_arn = module.kms.key_arn
}

# Local relative reference
module "s3" {
  source = "../../modules/aws/storage/s3"

  application = "core"
  environment = "prod"
  name        = "assets"
  kms_key_arn = module.kms.key_arn
}
```

---

## 3. Terragrunt Architecture (Plainr Pattern)

The recommended Terragrunt pattern pairs a single canonical Terraform composition stack in `resources/` with sibling environment directories:

```
infra-live/
├── root.hcl                          # Remote state (S3/DynamoDB) and provider generator
├── resources/                        # Single Terraform stack composing modules
│   ├── kms.tf                        # module "kms" { source = "../modules/aws/security/kms" }
│   ├── vpc.tf                        # module "vpc" { source = "../modules/aws/network/vpc" }
│   ├── rds.tf                        # module "rds" { source = "../modules/aws/database/rds/postgres" }
│   ├── iam.tf                        # Direct IAM roles / policies
│   ├── route53.tf                    # Direct DNS records
│   ├── variables.tf                  # Parameterized inputs
│   └── outputs.tf
├── dev/
│   └── terragrunt.hcl                # source = "..//resources", dev inputs
├── qa/
│   └── terragrunt.hcl                # source = "..//resources", qa inputs
└── prod/
    └── terragrunt.hcl                # source = "..//resources", prod inputs
```

### 3.1. `root.hcl`
```hcl
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

### 3.2. `resources/` Composition Example
```hcl
# resources/kms.tf
module "kms" {
  source = "../modules/aws/security/kms"

  application             = var.application
  environment             = var.environment
  name                    = "primary"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

# resources/vpc.tf
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
}

# resources/rds.tf
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
  }
}
```

### 3.3. Environment Terragrunt (`dev/terragrunt.hcl`, `prod/terragrunt.hcl`)
```hcl
# dev/terragrunt.hcl
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

  db_instance_class        = "db.t4g.medium"
  db_multi_az              = false
  db_allocated_storage     = 20
  db_max_allocated_storage = 100
  db_username              = "dbadmin"
  db_password              = get_env("DEV_DB_PASSWORD")
}
```

```hcl
# prod/terragrunt.hcl
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

  db_instance_class        = "db.r7g.xlarge"
  db_multi_az              = true
  db_allocated_storage     = 100
  db_max_allocated_storage = 1000
  db_username              = "dbadmin"
  db_password              = get_env("PROD_DB_PASSWORD")
}
```

---

## 4. Cryptographic & Governance Standards

All modules enforce the following standards:

1. **Mandatory KMS CMK**: Data-at-rest resources require an explicit Customer Managed Key (`kms_key_arn` or `kms_key_id`). No default AWS key fallbacks.
2. **Resource Naming**:
   `${var.application}-${var.environment}-${var.name}`
3. **Mandatory Tags**:
   All resources automatically inherit:
   - `Application`: Product/service name.
   - `Environment`: Deployment tier (`dev`, `qa`, `prod`, validated via regex `^[a-z0-9-]+$`).
   - `Name`: Formatted resource name.
   Merged with any user-provided `var.tags`.
4. **Security Baselines**:
   - TLS 1.2+ minimum on all endpoints and buckets.
   - IMDSv2 strictly enforced (`http_tokens = "required"`).
   - Private subnets by default for databases and compute workloads.
   - Deletion protection enabled by default for stateful databases and storage.

---

## 5. Development & Testing Commands

```bash
# Format code canonically
terraform fmt -recursive .

# Validate syntax
terraform init -backend=false
terraform validate
```

Detailed AWS resource catalogs and baseline specifications are documented in **[AWS.md](AWS.md)**.
