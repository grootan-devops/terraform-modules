# Naming and tagging

The bounds for providers other than AWS are in [Other providers](other-providers.md).

## Deterministic naming

Every module resolves its resource names through one local:

```hcl
locals {
  rendered_name = var.name != null && var.name != "" ? "${var.application}-${var.environment}-${var.name}" : "${var.application}-${var.environment}"
}
```

Names are never hardcoded and never carry a project, company, or customer label. Everything
flows through `var.application`, `var.environment`, and `var.name`, so the same module is
reusable across tenants.

## Length limits and deterministic truncation

AWS enforces a different length and character set per resource, and most of them recreate
destructively when a name changes. Blind concatenation is therefore unsafe on the short
ones:

| Resource | Limit | Valid characters | Mitigation |
| --- | :---: | --- | --- |
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

> **Current state:** no module implements this. `modules/aws/network/alb` passes
> `local.rendered_name` to `aws_lb` unguarded, so an `application`/`environment`/`name`
> triple longer than 32 characters fails at apply with a provider validation error.

## Governance tags and merge precedence

Four tags are reserved for cost allocation, ownership, and audit:

| Tag | Value |
| --- | --- |
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

> **Current state:** 23 of the 24 AWS modules do the opposite — they merge
> `var.tags` last, so a caller passing `tags = { Environment = "prod" }` silently overwrites
> the governance value, and none of them emit `ManagedBy`.
> [`modules/aws/security/secrets-manager`](../modules/aws/security/secrets-manager) is the only
> module on the standard above. Reversing the order on the rest changes tag values on live
> resources, which is an in-place update rather than a replacement, but it is a visible
> behavioural change and needs an entry in [MIGRATION.md](../MIGRATION.md).

A sub-resource with a distinct role overrides only `Name`:

```hcl
tags = merge(local.tags, { Name = "${local.rendered_name}-public-${each.key}" })
```

Tags are never forced onto a resource whose provider schema has no `tags` argument.

[Documentation index](../README.md#documentation)
