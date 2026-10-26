# Module contract

Every module here is a versioned public interface. The rules below are what a consumer may
rely on and what a new or changed module must satisfy. `tests/verify_modules.py` enforces
the mechanical subset of them — run it with `make verify`. Derive inputs and outputs from the
provider schema ([Provider schema](provider-schema.md)).

## Variables

| Attribute | Status | Rule |
| --- | :---: | --- |
| `description` | **Mandatory** | States purpose and operational impact. Never empty, never a restatement of the name. |
| `type` | **Mandatory** | An explicit constraint: `string`, `number`, `bool`, `list(…)`, `map(…)`, `set(…)`, `object(…)`. Bare `any` only as a documented escape hatch. |
| `default` | Conditional | On optional variables only; omitted on mandatory ones. Never a password, token, key, or placeholder credential. |
| `sensitive` | Conditional | `true` only when the value is a secret. Never write `sensitive = false`. |
| `nullable` | Conditional | `nullable = false` when `null` would crash a downstream expression or silently select a cloud default. Omit when `null` is a valid opt-out. |
| `ephemeral` | Conditional | `true` only for values consumed by write-only or ephemeral resources. Requires Terraform `>= 1.10.0`. |
| `validation` | Conditional | Only for genuine domain boundaries the provider does not reject cleanly. |

`application` and `environment` are required on every AWS module; `tests/verify_modules.py`
fails the build if either is missing. A OneUptime module declares `application`, which
becomes the label everything it creates carries ([Other providers](other-providers.md#oneuptime)).

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

## Outputs

Outputs are the consumption surface, so they are curated rather than exhaustive:

- Export identifiers, ARNs, endpoints, and well-typed summary maps.
- Do **not** export a whole resource (`value = aws_s3_bucket.this`). It couples callers to
  the provider schema, exposes computed internals, and freezes the module's internal
  structure against refactoring.
- `sensitive = true` only when the value is a secret. Never write `sensitive = false`.

## Provider configuration

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

## Version constraints

The standard for a reusable child module is a **minimum bound only**. An upper bound such as
`< 7.0.0` cannot stop a breaking provider release from being published; it only forces a
dependency conflict on consumer stacks that have already moved past it.

> **Current state:** 23 of the 24 AWS modules ship `version = ">= 6.0.0, < 7.0.0"`.
> Only [`modules/aws/security/secrets-manager`](../modules/aws/security/secrets-manager) meets
> the standard, at `>= 6.64.0`. Dropping the cap is a MINOR change — it needs no `moved`
> block — but it changes resolution for callers, so it belongs in `CHANGELOG.md`.

`required_version` is derived from the features a module actually uses: `>= 1.9.0` as the
baseline, because validations compare one input against another, `>= 1.10.0` for `ephemeral`,
`>= 1.11.0` for write-only (`*_wo`) arguments. Test files do not raise it: `*.tftest.hcl`
loads only under `terraform test`, which runs in the CI toolkit image, never in a consumer's
plan. Today `secrets-manager` is the single module at `>= 1.11.0`; every other module, AWS and
OneUptime, declares `>= 1.9.0`, and `tests/verify_modules.py` rejects anything lower.

> **OneUptime:** [`modules/oneuptime`](../modules/oneuptime) and its submodules declare
> `oneuptime/oneuptime` `>= 13.0.6, < 14.0.0`. The upper bound is deliberate: 14.x removes the
> `name` argument of the `oneuptime_domain` data source the module looks domains up by.

[Documentation index](../README.md#documentation)
