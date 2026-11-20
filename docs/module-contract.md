# Module contract

Every module here is a versioned public interface. The rules below are what a consumer may rely on and what a new
or changed module must satisfy. `tests/verify_modules.py` enforces the mechanical subset (`make verify`). Derive
inputs and outputs from the provider schema ([Provider schema](provider-schema.md)). Naming and tags are in
[Naming and tagging](naming-and-tagging.md); encryption, network and IAM defaults in
[Security baselines](security-baselines.md).

## Scope

Every AWS module declares one scope in its README, on the line after the title: `Scope: workload`,
`Scope: account` or `Scope: organization`.

| Scope | Called | Identity inputs | Examples |
| --- | --- | --- | --- |
| `workload` | Many times per account and Region | `application`, `environment`, `name` | lambda, sqs, vpc, alb, rds |
| `account` | Once per account; per-Region settings through a `regions` list | `environment`, `application` (default `"platform"`) | account-baseline, guardduty, security-hub, config, backup |
| `organization` | Once per organization, from the management or delegated administrator account | `environment`, `application` (default `"platform"`) | organizations, identity-center |
| `helper` | Composed by other modules under `modules/aws/core/` | none or `application`/`environment` | core/naming, core/policy-document |

A workload module never declares a resource that exists once per account or once per account and Region (a GuardDuty
detector, an account password policy, EBS encryption by default, the API Gateway account settings...).
`tests/verify_modules.py` holds the deny-list.

## Packaging

A module is one service plus the private resources that service needs to work: its IAM role and policies, security
group, log groups, an optional customer managed key, its resource policy, invoke permissions and event source
mappings, and the CloudWatch alarms for its own metrics (see [Alarms](#alarms)). It never creates another
first-class service: queues, topics, buses, buckets, tables, functions and certificates are separate modules and come
in as ARNs or IDs. The side that depends on a resource owns the link:
`alb`, `api-gateway` and `cloudfront` take `web_acl_arn`; `lambda` takes queue and stream ARNs for its event source
mappings; `eventbridge` takes target ARNs and creates the role that invokes them.

Shared building blocks are composed with relative sources inside the repository:

| Building block | Used for |
| --- | --- |
| [`core/naming`](../modules/aws/core/naming) | Names, governance tags, account ID, Region, partition |
| [`core/policy-document`](../modules/aws/core/policy-document) | Rendering typed `policy_statements` to JSON |
| [`core/encryption`](../modules/aws/core/encryption) | The three `kms` modes |
| [`security/kms`](../modules/aws/security/kms) | Module-owned customer managed keys (`kms.create = true`) |
| [`security/iam-role`](../modules/aws/security/iam-role) | Every IAM role a module creates; its policies are exclusive |
| [`network/security-group`](../modules/aws/network/security-group) | Every security group a module creates; its rules are exclusive (`self = true` for intra-group rules) |
| [`observability/log-group`](../modules/aws/observability/log-group) | Every CloudWatch log group a module creates |
| [`observability/cloudwatch-alarms`](../modules/aws/observability/cloudwatch-alarms) | Built-in alarms: the module's own preset behind the `alarms` input |

## Standard inputs

The same concept has the same name and shape in every AWS module.

### Identity and tags

```hcl
variable "application" {
  description = "Application name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,23}$", var.application))
    error_message = "application: 2-24 chars, a-z 0-9 -, starts with a letter."
  }
}

variable "environment" {
  description = "Environment name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,11}$", var.environment))
    error_message = "environment: 2-12 chars, a-z 0-9 -, starts with a letter."
  }
}

variable "name" {
  description = "Instance name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,31}$", var.name))
    error_message = "name: 1-32 chars, a-z 0-9 -."
  }
}

variable "tags" {
  description = "Extra tags; governance tags win."
  type        = map(string)
  default     = {}
  nullable    = false
}
```

`name` is required on modules that are normally instantiated several times per application and environment (lambda,
sqs, dynamodb, s3, ecr, step-functions, secrets-manager, kms, iam-role, security-group, log-group, efs, rds, valkey,
sns). It is optional (`default = null`) on modules that usually exist once per environment (vpc, eks, ecs, alb,
api-gateway, cognito, cloudfront, waf, route53, eventbridge). Account and organization modules take no `name`.

### Encryption

```hcl
variable "kms" {
  description = "Encryption: {} AWS managed key, create = true module key, key_id your key (ARN or ID)."
  type = object({
    key_id                  = optional(string)
    create                  = optional(bool, false)
    deletion_window_in_days = optional(number, 30)
    policy_statements       = optional(list(object({ ... })), [])
  })
  default  = {}
  nullable = false
}
```

Every module passes it to [`core/encryption`](../modules/aws/core/encryption) with a `purpose` (one service word, part
of the key alias, so two modules with the same name never share an alias) and the key policy statements its services
need, and uses `module.encryption.key_arn`:

- Empty (default): the service's AWS managed key or service-owned encryption. Nothing is stored unencrypted.
- `create = true`: a key owned by the module (`security/kms`): rotation on, key policy granting only this module's
  service principals with `aws:SourceArn`/`aws:SourceAccount` or encryption-context conditions, plus
  `policy_statements`.
- `key_id`: the caller's key, as a key ARN or key ID (an ID becomes the ARN in the provider's account and Region).
  Its key policy must grant the principals listed in the module README.
- `create` with `key_id` is rejected. The module outputs `kms_key_arn` (`null` for the AWS managed key).
- Where an AWS managed key cannot work, the module defaults to `create = true` and its README says why (for example
  `alarm-routing`: CloudWatch alarms cannot publish to a topic encrypted with `aws/sns`).

Inside feature objects a key override is `kms_key_arn` and falls back to the module key.

### Network

```hcl
variable "vpc_id" { ... }
variable "subnet_ids" { ... }

variable "security_group" {
  description = "Security group rules and extra groups."
  type = object({
    create                        = optional(bool, true)
    ingress_security_group_ids    = optional(list(string), [])
    ingress_cidr_blocks           = optional(list(string), [])
    ingress_prefix_list_ids       = optional(list(string), [])
    egress_cidr_blocks            = optional(list(string), [])
    additional_security_group_ids = optional(list(string), [])
  })
  default  = {}
  nullable = false
}
```

The module opens only its own port(s) to the listed sources, through `network/security-group` (separate
`aws_vpc_security_group_ingress_rule` and `egress_rule` resources). Ingress from `0.0.0.0/0` or `::/0` is rejected,
except on internet-facing load balancers. Each module documents its default `egress_cidr_blocks`; it is empty unless
the service starts its own connections. The module outputs `security_group_id`.

### IAM role

```hcl
variable "iam_role" {
  description = "Service role: extend it or bring your own."
  type = object({
    create                   = optional(bool, true)
    arn                      = optional(string)
    name                     = optional(string)
    path                     = optional(string, "/")
    permissions_boundary_arn = optional(string)
    managed_policy_arns      = optional(list(string), [])
    policy_statements        = optional(list(object({ ... })), [])
  })
  default  = {}
  nullable = false
}
```

The module grants only what its service needs. The caller adds permissions with `managed_policy_arns` or
`policy_statements`, or sets `create = false` and `arn` to bring a role. The module outputs `role_arn` and `role_name`.

### Logs

```hcl
variable "cloudwatch_logs" {
  description = "CloudWatch log group."
  type = object({
    enabled                     = optional(bool, true)
    retention_in_days           = optional(number, 365)
    log_group_class             = optional(string, "STANDARD")
    deletion_protection_enabled = optional(bool, true)
    kms_key_arn                 = optional(string)
  })
  default  = {}
  nullable = false
}
```

`kms_key_arn` falls back to the module key. 365 days meets PCI DSS 10.5.1 and Security Hub CloudWatch.16. Logs that
go to S3 use `access_logs = { enabled, bucket, prefix }`. Outputs: `log_group_name`, `log_group_arn`.

### Alarms

A module whose service publishes CloudWatch metrics builds in the matching preset of
[`observability/cloudwatch-alarms`](../modules/aws/observability/cloudwatch-alarms):

```hcl
variable "alarms" {
  description = "Built-in CloudWatch alarms: switch, topics by severity, per-alarm overrides."
  type = object({
    enabled    = optional(bool, true)
    topic_arns = optional(map(string), {})
    overrides = optional(object({
      error_rate = optional(object({ enabled = optional(bool), threshold = optional(number), evaluation_periods = optional(number), datapoints_to_alarm = optional(number), period = optional(number), severity = optional(string) }), {})
    }), {})
  })
  default  = {}
  nullable = false
}
```

- **On by default.** `enabled = false` creates no alarms. The module calls `cloudwatch-alarms` with
  `count = var.alarms.enabled ? 1 : 0` and the same `application`, `environment`, `name` and `tags`, so alarm names
  are `<base name>-<preset>-<key>-<alarm>`.
- **Routing.** `topic_arns` maps a severity to an SNS topic, normally
  `module.alarm_routing.topic_arns["<region>"]` from
  [`observability/alarm-routing`](../modules/aws/observability/alarm-routing). Topics are in the module's Region
  (us-east-1 for CloudFront and `CLOUDFRONT`-scope WAF). With no topics, the alarms have no actions.
- **Tuning.** `overrides` has one entry per alarm of the preset, with the same keys and fields as the preset's
  `alarms` object but no defaults: a field left out keeps the preset default, so thresholds, severities and opt-in
  alarms are defined once, in `cloudwatch-alarms`. Modules with two presets nest them (`eventbridge`:
  `rules`/`schedules`; `eks`: `cluster`/`node_groups`).
- **Settings.** The module maps its own settings into the preset where a threshold depends on them (Lambda `timeout`,
  ALB `idle_timeout`, RDS `storage.allocated_storage`, EFS throughput and performance modes, ECS and EKS Container
  Insights).
- **Plan-time keys.** Preset entries are keyed by constants or input map keys; IDs and ARN suffixes are only dimension
  values. A module whose preset would need a key known only after apply (ElastiCache member clusters) has no built-in
  alarms and documents the standalone `cloudwatch-alarms` call instead.
- **Outputs.** `alarm_arns` and `alarm_names`, by alarm key.

`cloudwatch-alarms` stays public for custom alarms, log metric filters, the CIS filters and alarms that span modules.

### Policy statements

Every input that adds to a policy uses one typed shape, rendered by `core/policy-document`:

```hcl
policy_statements = optional(list(object({
  sid        = optional(string)
  effect     = optional(string, "Allow")
  actions    = list(string)
  resources  = optional(list(string))
  principals = optional(map(list(string)), {})
  conditions = optional(list(object({
    test     = string
    variable = string
    values   = list(string)
  })), [])
})), [])
```

In a resource policy, `resources = null` means the resource itself. The module's guard statements (TLS only,
confused-deputy conditions) are always included and come first. A caller statement never overwrites a `Resource`.

### Plan-time safety

ARNs and IDs that come from other modules are unknown until apply, and the AWS provider does not mark them as non-null.
So `count`, `for_each` and the length of any list that feeds them depend only on booleans, literal strings, map keys
and list lengths, never on whether an ARN or ID input is null (`count = var.key_arn != null ? 1 : 0` fails at plan).
Module-built IAM statements go to `security/iam-role` as one JSON document (`policy_documents`), so their content can
be unknown. Every module has a plan-mode test with `kms = { create = true }` and with ARNs from unknown resources.

### Switches and protection

- An optional feature is an object with `enabled`: `logging = { enabled = true, ... }`. There are no `create_*`,
  `enable_*` or `is_enabled` variables and no "null object means off" inputs.
- Stateful resources take `deletion_protection` (`bool`, default `true`); buckets never set `force_destroy`.
- Cross-module references use IDs and ARNs: `vpc_id`, `subnet_ids`, `security_group_ids`, `*_arn`.
- An optional link to another module that decides whether a resource exists is an object with `enabled`:
  `waf = { enabled = true, web_acl_arn = module.waf.arn }`, never a bare ARN tested for null.

## Variables

| Attribute | Status | Rule |
| --- | :---: | --- |
| `description` | **Mandatory** | One short phrase. Rationale goes in the README. |
| `type` | **Mandatory** | Explicit. No `any`, `list(any)` or `map(any)`; objects use `optional()` with defaults. |
| `default` | Conditional | Only on optional variables. Never a credential. |
| `nullable` | Conditional | `false` on every collection and object input, and wherever `null` would break an expression. |
| `sensitive` | Conditional | `true` only for secrets. Never `sensitive = false`. |
| `ephemeral` | Conditional | Only for values consumed by write-only arguments. |
| `validation` | Conditional | For real domain limits, with a short `error_message` (`"name: 1-32 chars, a-z 0-9 -."`); every validation has an `expect_failures` run in the tests. |

Block order: in a variable, `description`, `type`, `default`, `nullable`, `sensitive`, then `validation` blocks; in a
resource, `count`/`for_each`, arguments, `tags`, `depends_on`, `lifecycle`.
`lookup()` is not used on typed objects; `optional()` already declares the default and `coalesce()` layers defaults.

## Outputs

- The primary resource is `id`, `arn` and `name`.
- Everything a neighbouring module consumes is exported: `security_group_id`, `role_arn`, `role_name`,
  `log_group_name`, `log_group_arn`, `kms_key_arn`, `endpoint`, `port`, `dns_name`, `zone_id`, subnet IDs and CIDRs, and
  the IDs alarms need.
- No output echoes an input, duplicates another output, or exports a whole resource.
- Modules with built-in alarms export `alarm_arns` and `alarm_names`.
- Building blocks (`security/iam-role`, `network/security-group`, `observability/log-group`,
  `observability/cloudwatch-alarms`) also output their rendered documents, rule IDs and effective settings, so the
  modules that compose them can test the wiring.
- `sensitive = true` only for secrets.

## Providers and versions

- No `provider` blocks and no `configuration_aliases`. A resource in another Region uses the resource-level `region`
  argument of provider 6.x (KMS replicas, RDS backup replication, us-east-1 certificates and CloudFront logs).
- Every AWS module declares `required_version = ">= 1.17.0"` and `hashicorp/aws` `>= 6.73.0`: one floor for the whole
  library, the release it is tested against.
- Minimum bounds only, never upper bounds.

> **OneUptime:** [`modules/oneuptime`](../modules/oneuptime) and its submodules declare `oneuptime/oneuptime`
> `>= 13.0.6, < 14.0.0` and Terraform `>= 1.9.0`. The upper bound is deliberate: 14.x removes the `name` argument of
> the `oneuptime_domain` data source the module looks domains up by. A OneUptime module declares `application`, which
> becomes the label everything it creates carries ([Other providers](other-providers.md#oneuptime)).

## Files

`versions.tf`, `variables.tf`, `locals.tf`, `main.tf` (plus one file per feature), `outputs.tf`, `README.md`
([README standard](module-readme.md)) and `tests/unit.tftest.hcl` ([Testing](testing.md)). No prose comments in `.tf`
files; only scanner directives, each registered in [scanner suppressions](compliance/scanner-suppressions.md).

[Documentation index](../README.md#documentation)
