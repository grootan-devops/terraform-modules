# AWS EFS File System Module

Scope: `workload`

An encrypted EFS file system with one mount target per subnet, a mount target security group that admits NFS only
from the listed sources, a file system policy that enforces TLS and squashes root, and access points with an enforced
POSIX identity. Backups belong to [`storage/backup`](../backup).

## Architecture & Managed Resources

- `aws_efs_file_system.this`: `<application>-<environment>-<name>`, always encrypted; transitions to IA after 7 days,
  to Archive after 30 days and back to Standard on first access (`NONE` turns one off).
- `aws_efs_mount_target.this`: one per entry in `subnet_ids`.
- `module.security_group` ([`network/security-group`](../../network/security-group)): `<...>-efs`, TCP 2049 from
  `ingress_security_group_ids`, `ingress_cidr_blocks` and `ingress_prefix_list_ids`; no egress rule.
- `aws_efs_file_system_policy.this` via `module.policy` ([`core/policy-document`](../../core/policy-document)).
- `aws_efs_access_point.this`: one per `access_points` key.
- `aws_efs_backup_policy.this`: EFS automatic backups, `DISABLED` unless `backup.enabled`.
- `module.encryption` ([`core/encryption`](../../core/encryption)): AWS managed key, module key or your key.

## Security & Compliance Guardrails

- **Encryption at rest (EFS.1, EFS.8):** always on; `aws/elasticfilesystem` by default.
- **TLS:** the file system policy denies every request without TLS; mount with the EFS mount helper's `tls` option.
- **Root squash and no anonymous access:** clients may `ClientMount` and `ClientWrite` only through a mount target
  (`elasticfilesystem:AccessedViaMountTarget`); `ClientRootAccess` only with `client_access.root_access`.
  `client_access.principal_arns` limits clients to listed roles and `read_only` drops `ClientWrite`. Extra
  `policy_statements` follow and default to the file system ARN.
- **Access points (EFS.3, EFS.4):** every access point enforces a POSIX user and a root directory other than `/`,
  created with that owner and `permissions` (default `0750`).
- **Network (EFS.6):** ingress only on 2049, never from `0.0.0.0/0` or `::/0`; no egress. Use private subnets.
- **Backups (EFS.7):** recovery points come from `storage/backup`; turn `backup.enabled` on only without it.

EFS has no deletion protection argument. A key passed in `kms.key_id` must allow the principal that creates the file
system to `kms:CreateGrant` and `kms:DescribeKey`.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "efs" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/storage/efs?ref=<version>"

  application    = "core"
  environment    = "prod"
  name           = "shared"
  vpc_id         = "vpc-0a1b2c3d4e5f67890"
  subnet_ids     = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  security_group = { ingress_cidr_blocks = ["10.0.0.0/16"] }
}
```

### Complete Production Example

```hcl
module "efs" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/storage/efs?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "shared"
  kms         = { create = true }

  vpc_id         = module.vpc.vpc_id
  subnet_ids     = module.vpc.private_subnet_ids
  security_group = { ingress_security_group_ids = [module.ecs.security_group_id] }

  client_access = { principal_arns = [module.ecs.task_role_arns["api"]] }
  access_points = {
    api = { uid = 1000, gid = 1000, path = "/api" }
  }
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | **Required** | Yes |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `name` | File system name. | `string` | **Required** | Yes |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `vpc_id` | VPC ID. | `string` | **Required** | Yes |
| `subnet_ids` | Private subnet IDs, one mount target each. | `list(string)` | **Required** | Yes |
| `security_group` | Mount target security group: NFS sources and extra groups. | `object({...})` | `{}` | No |
| `kms` | Encryption: {} AWS managed key, create = true module key, key_id your key (ARN or ID). | `object({...})` | `{}` | No |
| `performance_mode` | generalPurpose or maxIO. | `string` | `"generalPurpose"` | No |
| `throughput` | Throughput mode and provisioned MiB/s. | `object({...})` | `{}` | No |
| `lifecycle_policy` | Storage class transitions; NONE turns one off. | `object({...})` | `{}` | No |
| `backup` | EFS automatic backups; storage/backup owns backups. | `object({...})` | `{}` | No |
| `client_access` | Mount target clients: principals, read only, root access. | `object({...})` | `{}` | No |
| `policy_statements` | Extra file system policy statements; resources default to the file system. | `list(object({...}))` | `[]` | No |
| `access_points` | Access points by key with an enforced POSIX user and root directory (EFS.3, EFS.4). | `map(object({...}))` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `id` | File system ID. | No |
| `arn` | File system ARN. | No |
| `name` | File system name. | No |
| `dns_name` | File system DNS name. | No |
| `security_group_id` | Mount target security group ID; null when not created. | No |
| `access_point_ids` | Access point IDs by key. | No |
| `access_point_arns` | Access point ARNs by key. | No |
| `kms_key_arn` | Key ARN in use; null for the AWS managed key. | No |
