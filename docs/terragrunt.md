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
      version = ">= 6.73.0"
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
EOF
}
```

## `resources/` Composition Example

```hcl
# resources/kms.tf
module "kms" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/kms?ref=<version>"

  application = var.application
  environment = var.environment
  name        = "primary"
}

# resources/vpc.tf
module "vpc" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/vpc?ref=<version>"

  application = var.application
  environment = var.environment
  cidr_block  = var.vpc_cidr
  az_count    = var.az_count
  nat         = { mode = var.nat_mode }
  kms         = { key_id = module.kms.arn }
}

# resources/rds.tf
module "rds" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/database/rds/postgres?ref=<version>"

  application    = var.application
  environment    = var.environment
  name           = "db"
  engine_version = "18"
  instance_class = var.db_instance_class
  multi_az       = var.db_multi_az
  vpc_id         = module.vpc.vpc_id
  subnet_ids     = module.vpc.intra_subnet_ids
  kms            = { key_id = module.kms.arn }
  storage        = { allocated_storage = var.db_allocated_storage, max_allocated_storage = var.db_max_allocated_storage }
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

  vpc_cidr = "10.10.0.0/16"
  az_count = 2
  nat_mode = "single"

  db_instance_class        = "db.t4g.medium"
  db_multi_az              = false
  db_allocated_storage     = 20
  db_max_allocated_storage = 100
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

  vpc_cidr = "10.0.0.0/16"
  az_count = 3
  nat_mode = "per_az"

  db_instance_class        = "db.r7g.xlarge"
  db_multi_az              = true
  db_allocated_storage     = 100
  db_max_allocated_storage = 1000
}
```

The rules for sources, versions, state, providers and secrets in such a stack are in
[Consuming modules](consumption.md).

[Documentation index](../README.md#documentation)
