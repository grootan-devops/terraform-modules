# Terragrunt architecture

The recommended Terragrunt pattern pairs a single canonical Terraform composition stack in `resources/` with sibling environment directories:

```text
infra-live/
├── root.hcl                          # Remote state (S3/DynamoDB) and provider generator
├── resources/                        # Single Terraform stack composing modules
│   ├── kms.tf                        # KMS module pinned to the public Git release
│   ├── vpc.tf                        # VPC module pinned to the public Git release
│   ├── rds.tf                        # RDS module pinned to the public Git release
│   ├── iam.tf                        # Direct IAM roles / policies
│   ├── route53.tf                    # Direct DNS records
│   ├── variables.tf                  # Parameterized inputs
│   └── outputs.tf
├── dev/
│   └── terragrunt.hcl                # immutable Git source for resources, dev inputs
├── qa/
│   └── terragrunt.hcl                # immutable Git source for resources, qa inputs
└── prod/
    └── terragrunt.hcl                # immutable Git source for resources, prod inputs
```

## `root.hcl`

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
  required_version = ">= 1.9.0"

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

## `resources/` Composition Example

```hcl
# resources/kms.tf
module "kms" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/kms?ref=<version>"

  application             = var.application
  environment             = var.environment
  name                    = "primary"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

# resources/vpc.tf
module "vpc" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/vpc?ref=<version>"

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
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/database/rds/postgres?ref=<version>"

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

## Environment Terragrunt (`dev/terragrunt.hcl`, `prod/terragrunt.hcl`)

```hcl
# dev/terragrunt.hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "git::https://github.com/contoso-corporation/infra-live.git//resources?ref=1.0.0"
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
  source = "git::https://github.com/contoso-corporation/infra-live.git//resources?ref=1.0.0"
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

The rules for sources, versions, state, providers and secrets in such a stack are in
[Consuming modules](consumption.md).

[Documentation index](../README.md#documentation)
