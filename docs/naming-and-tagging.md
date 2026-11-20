# Naming and tagging

The bounds for providers other than AWS are in [Other providers](other-providers.md).

## Deterministic, collision-free names

Every AWS module derives its names through [`core/naming`](../modules/aws/core/naming). The base is
`<application>-<environment>[-<name>]`. What gets appended depends on the namespace the name has to be unique in:

| Namespace | Resources | Rule | Example |
| --- | --- | --- | --- |
| Account and Region (`uniqueness = "region"`, default) | Most resources: functions, queues, tables, clusters, log groups, security groups | `<base>[-<suffix>]` | `core-prod-orders` |
| Account, created by a regional module (`uniqueness = "account"`) | IAM roles, policies and instance profiles | `<base>[-<suffix>]-<region>` | `core-prod-orders-exec-eu-west-1` |
| Global (`uniqueness = "global"`) | S3 buckets, Cognito prefix domains | `<base>[-<suffix>]-<account-id>-<region>` | `core-prod-assets-123456789012-eu-west-1` |

So the same application and environment can be deployed in a second Region or account without a name clash, and two
instances of a module in one environment differ by `name`, which is required on every module that is normally
instantiated more than once (see [Module contract](module-contract.md#identity-and-tags)).

Names never carry a project, company or customer label; everything flows from `application`, `environment` and
`name`. Account and organization modules create singletons and use `uniqueness = "region"` for them.

An exact name is accepted only where something outside Terraform depends on it: `bucket_name` on `storage/s3`,
`iam_role.name` on modules that create a role. Even then the length limit is validated.

## Length limits and truncation

Each name is cut to its resource's limit. When the full name is longer, the module keeps the first characters and
appends `-` and the first 6 hex characters of the MD5 of the **full** name, so two long names that share a prefix still
differ:

```hcl
locals {
  full      = "core-prod-orders-reconciliation-exec-ap-southeast-2"
  max       = 32
  truncated = length(local.full) <= local.max ? local.full : "${trimsuffix(substr(local.full, 0, local.max - 7), "-")}-${substr(md5(local.full), 0, 6)}"
}
```

| Resource | Limit |
| --- | :---: |
| `aws_lb`, `aws_lb_target_group` | 32 |
| `aws_elasticache_replication_group` | 40 |
| `aws_backup_vault` | 50 |
| `aws_s3_bucket`, `aws_db_instance`, `aws_db_proxy`, `aws_ecr_repository` (none shorter than 256, kept short) | 63 |
| `aws_iam_role`, `aws_iam_instance_profile`, IAM policy names | 64 |
| `aws_sqs_queue`, `aws_sfn_state_machine` | 80 |
| `aws_lambda_function` | 64 |
| `aws_cloudwatch_metric_alarm` | 255 |

## Governance tags and merge precedence

Four tags are reserved for cost allocation, ownership and audit:

| Tag | Value |
| --- | --- |
| `Application` | `var.application` (`"platform"` by default on account and organization modules) |
| `Environment` | `var.environment` |
| `Name` | the resource's rendered name |
| `ManagedBy` | `"Terraform"` |

Caller tags are merged first and governance tags last, so a caller can add metadata (`Owner`, `CostCenter`,
`DataClassification`) but cannot overwrite the tags an audit depends on:

```hcl
tags = merge(var.tags, module.naming.governance_tags)
```

A resource with its own name overrides only `Name`:

```hcl
tags = merge(module.naming.tags, { Name = module.naming.names.role })
```

No resource ignores tag changes, and tags are never set on a resource whose schema has no `tags` argument. The
`REQUIRED_TAGS` rule in [`security/config`](../modules/aws/security/config) checks the four governance keys.

[Documentation index](../README.md#documentation)
