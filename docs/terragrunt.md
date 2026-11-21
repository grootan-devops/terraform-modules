# Terragrunt architecture

A live repository runs each module where its scope says (the `Scope` column of the [AWS catalog](AWS.md#catalog)):
`workload` modules once per environment, `account` modules once per account, `organization` modules once per
organization. Each scope gets its own composition root and its own Terragrunt unit, so each has its own state.

```text
infra-live/
├── root.hcl                     # remote state, shared locals and inputs
├── environment.hcl              # shared by every environment unit
├── resources/                   # workload composition root: module calls only
│   ├── versions.tf
│   ├── providers.tf
│   ├── variables.tf
│   ├── network.tf               # kms, vpc, security-group
│   ├── data.tf                  # rds/postgres, rds/proxy, dynamodb, elasticache/valkey
│   ├── api.tf                   # alb, ecs, api-gateway, http-api, cognito
│   ├── outputs.tf
│   └── tests/offline.tftest.hcl
├── layers/
│   ├── organization/            # organizations, identity-center (management account only)
│   └── account/                 # account-baseline, cloudtrail, config, security-hub, guardduty, backup, shared ecr
├── organization/terragrunt.hcl  # unit: layers/organization
├── account/terragrunt.hcl       # unit: layers/account, after organization
├── dev/terragrunt.hcl           # unit: resources/ with dev inputs, after account
├── qa/terragrunt.hcl
└── prod/terragrunt.hcl
```

Each unit directory also holds the `.terraform.lock.hcl` Terragrunt writes back; commit it.

## `root.hcl`

```hcl
locals {
  application    = "<application>"
  account_id     = "<account-id>"
  primary_region = "<region>"
  state_bucket   = "<state-bucket>"
}

remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket                = local.state_bucket
    key                   = "${path_relative_to_include()}/terraform.tfstate"
    region                = local.primary_region
    encrypt               = true
    use_lockfile          = true
    disable_bucket_update = true
  }
}

inputs = {
  application = local.application
  account_id  = local.account_id
  region      = local.primary_region
}
```

- `use_lockfile` is the native S3 lock; no DynamoDB table.
- Create the state bucket (versioned, encrypted, public access blocked) outside these stacks. Terragrunt creates none
  without `--backend-bootstrap`, and `disable_bucket_update` stops it changing the bucket's settings.
- The state key is the unit's path, so `dev/` and `account/` never share state. Never rename a unit directory that
  already has state.

## Composition roots

`resources/` and every directory under `layers/` follow the same rules:

- module calls only, connected through their documented outputs ([how the modules connect](AWS.md#how-the-modules-connect));
- one `versions.tf` with minimum versions (the committed lock file pins the exact ones) and one `providers.tf`;
- variables for everything that differs by environment, outputs for what other units read.

```hcl
# resources/versions.tf
terraform {
  required_version = ">= 1.17.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.73.0"
    }
  }
}

# resources/providers.tf
provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]
}
```

One provider is enough: modules that work in another Region (CloudFront certificates and web ACLs in `us-east-1`,
backup copies, account settings across `regions`) take it as an input. `allowed_account_ids` stops a plan in the wrong
account. Governance tags come from the modules, so the provider needs no `default_tags`.

```hcl
# resources/network.tf
module "kms" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/kms?ref=<version>"

  application = var.application
  environment = var.environment
  name        = "primary"
}

module "vpc" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/vpc?ref=<version>"

  application = var.application
  environment = var.environment
  cidr_block  = var.vpc_cidr
  az_count    = var.az_count
  nat         = { mode = var.nat_mode }
  kms         = { key_id = module.kms.arn }
}
```

## Environment units

`environment.hcl` holds what every environment shares: the source, the environment name and the outputs read from the
account layer.

```hcl
# environment.hcl
locals {
  root     = read_terragrunt_config(find_in_parent_folders("root.hcl")).locals
  root_dir = dirname(find_in_parent_folders("root.hcl"))
  env      = basename(get_terragrunt_dir())
}

terraform {
  source = "${local.root_dir}/resources"
}

dependency "account" {
  config_path = "${local.root_dir}/account"

  mock_outputs = {
    ecr_repository_urls = { api = "${local.root.account_id}.dkr.ecr.${local.root.primary_region}.amazonaws.com/${local.root.application}-shared-api" }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan"]
}

inputs = {
  environment         = local.env
  ecr_repository_urls = dependency.account.outputs.ecr_repository_urls
}
```

```hcl
# dev/terragrunt.hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "environment" {
  path = find_in_parent_folders("environment.hcl")
}

inputs = {
  vpc_cidr          = "10.10.0.0/16"
  az_count          = 2
  nat_mode          = "single"
  db_instance_class = "db.t4g.micro"
  db_multi_az       = false
}
```

`prod/terragrunt.hcl` is the same file with prod values (`az_count = 3`, `nat_mode = "per_az"`, `db_multi_az = true`).
Mock outputs stand in only until the account layer is applied; never allow them for `apply`.

To promote one tested version of `resources/` from environment to environment, tag the live repository and point each
environment at a tag instead of the local path:
`source = "git::https://github.com/<organization>/<live-repository>.git//resources?ref=<live-version>"`.

## Account and organization layers

```hcl
# account/terragrunt.hcl
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "${get_parent_terragrunt_dir("root")}/layers/account"
}

dependencies {
  paths = ["../organization"]
}

inputs = {
  environment = "shared"
  regions     = [include.root.locals.primary_region, "us-east-1"]
}
```

- **One account for every environment:** `account/` runs once and the environments depend on it. Resources every
  environment shares (ECR repositories, a parent DNS zone) live here; each environment reads them through a
  `dependency`. Names carry the environment, so dev, qa and prod never collide in the one account.
- **An organization of accounts:** one account unit per account (`accounts/<account>/terragrunt.hcl`), each with that
  account's provider role, and the organization unit in the management account. The order is in
  [account layouts](AWS.md#account-layouts).

Run the whole repository in dependency order with `terragrunt run --all -- plan`; `terragrunt dag graph` prints the
order.

## Validation and offline plans

```bash
terragrunt hcl fmt --check
terragrunt hcl validate --inputs
terragrunt run --all -- init -backend=false
terragrunt run --all -- validate
```

A plan without AWS credentials runs as a `terraform test` under a mocked provider. Add one test file to each
composition root, give the data sources the modules read real-looking values, and skip the dependency outputs:

```hcl
# resources/tests/offline.tftest.hcl
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012", arn = "arn:aws:sts::123456789012:assumed-role/offline-plan/mock" }
  }
  mock_data "aws_region" {
    defaults = { region = "eu-west-1" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_availability_zones" {
    defaults = { names = ["eu-west-1a", "eu-west-1b", "eu-west-1c"], zone_ids = ["euw1-az1", "euw1-az2", "euw1-az3"] }
  }
}

run "offline_plan" {
  command = plan
}
```

```hcl
# environment.hcl, dependency "account"
skip_outputs                            = get_env("OFFLINE_PLAN", "false") == "true"
mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "test"]
```

```bash
OFFLINE_PLAN=true terragrunt run --all -- test -verbose
```

The test prints the full plan of every unit. Mocked values are not AWS's: unknown ARNs and IDs stay unknown, and
nothing proves the plan applies. A real plan with credentials is still reviewed before any apply.

The rules for sources, versions, state, providers and secrets are in [Consuming modules](consumption.md).

[Documentation index](../README.md#documentation)
