# Terraform Modules Library

Release `1.0.0` · [Compatibility](https://github.com/grootan-devops/ai-skills/blob/main/COMPATIBILITY.md) · [Security](./SECURITY.md) · [Contributing](./CONTRIBUTING.md)

Production-grade, modular Terraform library for provisioning secure, compliant cloud infrastructure.

---

## 1. Repository Layout

Modules are grouped by cloud provider and domain under `modules/`:

```text
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
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/storage/s3?ref=1.0.0"

  application = "core"
  environment = "prod"
  name        = "assets"
  kms_key_arn = module.kms.key_arn
}

```

---

## 3. Terragrunt Architecture (Plainr Pattern)

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
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/kms?ref=1.0.0"

  application             = var.application
  environment             = var.environment
  name                    = "primary"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

# resources/vpc.tf
module "vpc" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/vpc?ref=1.0.0"

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
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/database/rds/postgres?ref=1.0.0"

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

---

## 4. Module Contract

Every module here is a versioned public interface. The rules below are what a consumer may
rely on and what a new or changed module must satisfy. `tests/verify_modules.py` enforces
the mechanical subset of them — run it with `make verify`.

### 4.1. Variables

| Attribute | Status | Rule |
|---|:---:|---|
| `description` | **Mandatory** | States purpose and operational impact. Never empty, never a restatement of the name. |
| `type` | **Mandatory** | An explicit constraint: `string`, `number`, `bool`, `list(…)`, `map(…)`, `set(…)`, `object(…)`. Bare `any` only as a documented escape hatch. |
| `default` | Conditional | On optional variables only; omitted on mandatory ones. Never a password, token, key, or placeholder credential. |
| `sensitive` | Conditional | `true` only when the value is a secret. Never write `sensitive = false`. |
| `nullable` | Conditional | `nullable = false` when `null` would crash a downstream expression or silently select a cloud default. Omit when `null` is a valid opt-out. |
| `ephemeral` | Conditional | `true` only for values consumed by write-only or ephemeral resources. Requires Terraform `>= 1.10.0`. |
| `validation` | Conditional | Only for genuine domain boundaries the provider does not reject cleanly. |

`application` and `environment` are required on every module; `tests/verify_modules.py`
fails the build if either is missing.

Related settings are grouped into one strongly-typed object rather than scattered across
flat variables:

```hcl
variable "cloudwatch_logs" {
  description = "CloudWatch logging configuration for the resource."
  type = object({
    retention_in_days = optional(number, 90)
    kms_key_arn       = optional(string, null)
    log_group_class   = optional(string, "STANDARD")
  })
  default = {}
}
```

`lookup()` against such an object is banned: `optional()` has already declared the default,
and `lookup()` re-opens the type hole it closed. It stays legitimate on an open-ended map
whose keys are unknown at authoring time. For layered defaults use `coalesce()`.

```hcl
# Banned — the object is typed and the default is already declared:
retention = lookup(var.cloudwatch_logs, "retention_in_days", 90)

# Legitimate — caller-defined keys:
header = lookup(var.custom_headers, "X-Custom-Auth", null)

# Layered default:
kms_key_id = coalesce(var.cloudwatch_logs.kms_key_arn, var.kms_key_arn)
```

### 4.2. Outputs

Outputs are the consumption surface, so they are curated rather than exhaustive:

- Export identifiers, ARNs, endpoints, and well-typed summary maps.
- Do **not** export a whole resource (`value = aws_s3_bucket.this`). It couples callers to
  the provider schema, exposes computed internals, and freezes the module's internal
  structure against refactoring.
- `sensitive = true` only when the value is a secret. Never write `sensitive = false`.

### 4.3. Provider configuration

Every module here is a child module. It never declares `provider "aws" {}`, never hardcodes
a region, and never carries credentials — the calling stack owns all three.
`configuration_aliases` is declared only when a module genuinely needs a second provider
instance, such as cross-region key replication:

```hcl
required_providers {
  aws = {
    source                = "hashicorp/aws"
    version               = ">= 6.0.0"
    configuration_aliases = [aws.replica]
  }
}
```

### 4.4. Version constraints

The standard for a reusable child module is a **minimum bound only**. An upper bound such as
`< 7.0.0` cannot stop a breaking provider release from being published; it only forces a
dependency conflict on consumer stacks that have already moved past it.

> **Current state at `1.0.0`:** 23 of the 24 modules ship `version = ">= 6.0.0, < 7.0.0"`.
> Only [`modules/aws/security/secrets-manager`](modules/aws/security/secrets-manager) meets
> the standard, at `>= 6.64.0`. Dropping the cap is a MINOR change — it needs no `moved`
> block — but it changes resolution for callers, so it belongs in `CHANGELOG.md`.

`required_version` is derived from the features a module actually uses: `>= 1.5.0` as the
baseline, `>= 1.6.0` once it ships `*.tftest.hcl`, `>= 1.10.0` for `ephemeral`, `>= 1.11.0`
for write-only (`*_wo`) arguments. Today `secrets-manager` is the single module at
`>= 1.11.0`; the other 23 declare `>= 1.5.0`.

---

## 5. Naming & Tagging Standards

### 5.1. Deterministic naming

Every module resolves its resource names through one local:

```hcl
locals {
  rendered_name = var.name != null && var.name != "" ? "${var.application}-${var.environment}-${var.name}" : "${var.application}-${var.environment}"
}
```

Names are never hardcoded and never carry a project, company, or customer label. Everything
flows through `var.application`, `var.environment`, and `var.name`, so the same module is
reusable across tenants.

### 5.2. Length limits and deterministic truncation

AWS enforces a different length and character set per resource, and most of them recreate
destructively when a name changes. Blind concatenation is therefore unsafe on the short
ones:

| Resource | Limit | Valid characters | Mitigation |
|---|:---:|---|---|
| `aws_lb`, `aws_lb_target_group` | 1–32 | `^[a-zA-Z0-9-]+$`, no leading/trailing hyphen | Truncate to 27 chars + `-` + 4-char MD5 of the full name |
| `aws_s3_bucket` | 3–63 | lowercase, digits, hyphen, period | Global namespace — use `bucket_name_override`, or append a deterministic account/region hash |
| `aws_iam_role` | 1–64 | `^[a-zA-Z0-9+=,.@_-]+$` | Truncate to 58 chars + 5-char hash |
| `aws_db_instance` | 1–63 | lowercase, digits, hyphen | Truncate to 57 chars + 5-char hash |
| `aws_kms_key` alias | 1–256 | `^[a-zA-Z0-9:/_-]+$`, `alias/` prefix | None needed; rename is non-destructive |

Truncation keeps a readable prefix and appends a stable hash, so two names that share a
prefix cannot collide:

```hcl
locals {
  alb_name_hash      = substr(md5(local.rendered_name), 0, 4)
  alb_truncated_name = length(local.rendered_name) > 32 ? "${substr(local.rendered_name, 0, 27)}-${local.alb_name_hash}" : local.rendered_name
}
```

> **Current state at `1.0.0`:** no module implements this. `modules/aws/network/alb` passes
> `local.rendered_name` to `aws_lb` unguarded, so an `application`/`environment`/`name`
> triple longer than 32 characters fails at apply with a provider validation error.

### 5.3. Governance tags and merge precedence

Four tags are reserved for cost allocation, ownership, and audit:

| Tag | Value |
|---|---|
| `Application` | `var.application` |
| `Environment` | `var.environment`, validated against `^[a-z0-9-]+$` |
| `Name` | `local.rendered_name`, or the sub-resource name |
| `ManagedBy` | the literal `"Terraform"` |

Consumer tags are merged **first** and governance tags **last**, so a caller can add
metadata but cannot overwrite the tags an audit depends on:

```hcl
locals {
  governance_tags = {
    Application = var.application
    Environment = var.environment
    Name        = local.rendered_name
    ManagedBy   = "Terraform"
  }

  tags = merge(var.tags, local.governance_tags)
}
```

> **Current state at `1.0.0`:** 23 of the 24 modules do the opposite — they merge
> `var.tags` last, so a caller passing `tags = { Environment = "prod" }` silently overwrites
> the governance value, and none of them emit `ManagedBy`.
> [`modules/aws/security/secrets-manager`](modules/aws/security/secrets-manager) is the only
> module on the standard above. Reversing the order on the rest changes tag values on live
> resources, which is an in-place update rather than a replacement, but it is a visible
> behavioural change and needs an entry in [MIGRATION.md](./MIGRATION.md).

A sub-resource with a distinct role overrides only `Name`:

```hcl
tags = merge(local.tags, { Name = "${local.rendered_name}-public-${each.key}" })
```

Tags are never forced onto a resource whose provider schema has no `tags` argument.

---

## 6. Security Baselines

### 6.1. Capability-aware controls

Security is matched to what the cloud API actually supports, rather than applied as a
blanket mandate. Every control on every resource resolves to one of six statuses:

| Status | Meaning | What a module does |
|---|---|---|
| `required` | Natively supported and non-negotiable. | Enforce it, with a production default. |
| `recommended` | Best practice with a real cost or operational trade-off. | Secure default, caller may override. |
| `optional` | Advanced or niche. | Opt-in sub-block, disabled by default. |
| `provider_managed` | The cloud already does it by default. | Add nothing; a redundant block is noise. |
| `not_supported` | Absent from the provider schema. | Never invent a synthetic argument for it. |
| `not_applicable` | Semantically meaningless here (KMS on an IAM role). | Omit entirely. |

The resolved AWS matrix — which control applies to which service — is in
**[docs/AWS.md](docs/AWS.md)**.

### 6.2. Cryptographic key governance

1. **Explicit customer-managed keys only.** Every module encrypting data at rest takes a
   mandatory `kms_key_arn` / `kms_key_id` with no default. Silent fallback to an AWS managed
   key (`aws/s3`, `aws/rds`, `aws/sqs`) is prohibited.
2. **Annual rotation.** Keys from `modules/aws/security/kms` set `enable_key_rotation = true`.
3. **No key evasion.** SQS sets `kms_master_key_id` and `sqs_managed_sse_enabled = false`.
4. **Bucket keys.** S3 sets `bucket_key_enabled = true` to cut KMS request cost.
5. **Encrypted logs.** Every CloudWatch log group a module creates sets `kms_key_id`.

### 6.3. Transport, exposure, and durability

- TLS 1.2 or higher on every endpoint and bucket policy.
- IMDSv2 required (`http_tokens = "required"`) on every launch template.
- Databases and compute land in private or intra subnets by default.
- Deletion protection on by default for stateful databases and storage.

### 6.4. Credential handling

No module ever declares a default password, token, or key. `sensitive = true` masks a value
in CLI output and plan diffs — **it does not encrypt it in `terraform.tfstate`**, so a secret
passed as an ordinary input is stored in cleartext in state. In order of preference:

1. **Write-only arguments** (`password_wo`, `secret_string_wo`) where the provider offers
   them; the value never reaches state. Requires Terraform `>= 1.11.0`.
2. **External secret management** — reference an existing Secrets Manager secret, or let the
   service generate the credential.
3. **IAM authentication** (`iam_database_authentication_enabled = true`) in place of a static
   username and password.

IAM policies are composed with `data "aws_iam_policy_document"`, and avoid `Action = ["*"]`,
service-wide prefixes (`s3:*`), and `Resource = ["*"]` wherever the action can be scoped.

---

## 7. Module Documentation Standard

Every module ships a `README.md` with these sections, in this order. The API tables are
generated from source, so they are kept in dedicated sections that tooling can refresh
without touching the hand-written narrative around them.

```text
# <Provider> <Resource> Module
<what it provisions, its operational role — no marketing, no project names>

### Architecture & Managed Resources     hand-written
### Security & Compliance Guardrails     hand-written
## Requirements & Providers              generated from versions.tf
## Usage Examples                        hand-written
### Minimal Working Example
### Complete Production Example
## Inputs Specification                  generated from variables.tf
## Outputs Specification                 generated from outputs.tf
```

Table conventions:

- **Inputs** — a mandatory variable sets `Default` to `**Required**` and `Required` to `Yes`;
  an optional one shows the literal default and `No`. Structural types are written compactly
  (`object({...})`, `list(object({...}))`).
- **Outputs** — the `Sensitive` column is `Yes` or `No`, never blank.

Modules needing more than this append sections; they do not drop any. Migration notes,
ownership and lifecycle boundaries, and known caveats are the common additions.

Every usage example must reference the public Git source pinned to a release tag —
`tests/verify_modules.py` rejects a module README whose examples use a relative path.

---

## 8. Versioning & Release Contract

Modules follow [Semantic Versioning 2.0.0](https://semver.org/) as one library: the
repository tag is the version, and every module moves with it.

| Level | Triggers | Examples |
|:---:|---|---|
| **PATCH** `x.y.Z` | Fixes and internal refactors with zero behavioural or state change for callers. | Documentation fix; `terraform fmt`; a local expression rewritten. |
| **MINOR** `x.Y.0` | Backward-compatible additions. | A new optional variable with a safe default; a new output; dropping an artificial upper version bound. |
| **MAJOR** `X.0.0` | Any break in the public surface. | Renaming or removing a variable or output; changing a default that alters live infrastructure; moving a resource address without a `moved` block; raising the minimum provider to an incompatible major. |

Anything at MAJOR — and any MINOR that changes observable behaviour — requires an entry in
[MIGRATION.md](./MIGRATION.md) before release. Release notes go in
[CHANGELOG.md](./CHANGELOG.md).

---

## 9. Development & Testing

```bash
make verify      # contract checks + fmt + init + validate + terraform test
make contracts   # contract checks only, no Terraform binary required
make validate    # full run (same as verify's second half)
```

`tests/verify_modules.py` is the gate. For every module it asserts:

- `required_version >= 1.5.0` and a `hashicorp/aws` provider requirement.
- `application` and `environment` variables are declared.
- A `locals` block carrying naming and tag governance exists.
- A `README.md` exists whose examples use the public Git source pinned to the release tag.
- No Markdown anywhere in the repository points a module `source` at a relative path.
- `terraform fmt -check -recursive`, `terraform init -backend=false`, and
  `terraform validate` all pass, and `terraform test` runs wherever a `*.tftest.hcl` exists.

Individual commands, run inside a module directory:

```bash
terraform fmt -recursive .
terraform init -backend=false
terraform validate
terraform test          # requires tests/*.tftest.hcl and Terraform >= 1.6
```

### 9.1. Test levels

| Level | What it covers | State today |
|:---:|---|---|
| 0 | `fmt`, `validate`, contract checks | Enforced by `make verify` on all 24 modules |
| 1 | Static security and secret scanning | Not wired into this repository |
| 2 | `terraform test` with `mock_provider`, no credentials | `modules/aws/security/secrets-manager/tests/unit.tftest.hcl` only |
| 3 | Plan analysis for unexpected `delete` actions | Not wired in; no `examples/` fixtures exist |
| 4 | Terratest apply/idempotency/destroy against real cloud | Not wired in |
| 5 | Upgrade tests across a `moved` block | Not wired in |
| 6 | Terraform core and provider version matrix | Not wired in |

Level 2 is the cheapest to extend and the one to add with any new module: it runs offline in
seconds and `make verify` picks it up automatically.

Detailed AWS resource catalogs and baseline specifications are documented in
**[docs/AWS.md](docs/AWS.md)**.

---

## License

Copyright 2026 Grootan Technologies Pvt Ltd.

Licensed under the [GNU Affero General Public License v3.0](./LICENSE.md)
(`AGPL-3.0-only`). External contributions are not accepted; see
[CONTRIBUTING.md](./CONTRIBUTING.md) for bug and security reporting.
