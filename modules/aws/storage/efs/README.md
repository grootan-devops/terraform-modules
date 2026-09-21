# AWS EFS File System Module

The `efs` module provisions scalable Amazon Elastic File System (EFS) resources with POSIX compliance, in-transit transport encryption policies, and automated AWS Backup integration.

## Architecture & Managed Resources

- `aws_efs_file_system.this`: Encrypted primary file system.
- `aws_efs_mount_target.this`: Network mount targets placed across VPC private subnets.
- `aws_efs_file_system_policy.this`: Enforces mandatory TLS for all client mount connections.
- `aws_efs_backup_policy.this`: Native automated daily backups via AWS Backup.
- `aws_security_group.this`: Dedicated security group controlling inbound NFS (TCP 2049) traffic.

### Security & Compliance Guardrails

- **Mandatory KMS CMK**: File system encryption at rest is strictly enforced (`encrypted = true`, `kms_key_id = var.kms_key_arn`).
- **In-Transit TLS Deny Policy**: Resource policy explicitly denies all NFS actions when `aws:SecureTransport = false`.
- **Private Subnet Isolation**: Mount targets are strictly restricted to internal VPC subnets.

---

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.5.0` |
| `aws` | `>= 6.0.0, < 7.0.0` |

---

## Usage Examples

### Minimal Working Example

```hcl
module "efs" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/storage/efs?ref=1.0.0"

  application = "core"
  environment = "prod"
  name        = "shared"

  vpc_id      = "vpc-0a1b2c3d4e5f67890"
  subnet_ids  = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
}
```

### Complete Production Example

```hcl
module "efs" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/storage/efs?ref=1.0.0"

  application = "enterprise"
  environment = "prod"
  name        = "k8s-pv"

  vpc_id      = "vpc-0a1b2c3d4e5f67890"
  subnet_ids  = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"

  performance_mode                = "generalPurpose"
  throughput_mode                 = "bursting"
  transition_to_ia                = ["AFTER_30_DAYS"]
  transition_to_primary_storage_class = ["AFTER_1_ACCESS"]
  enable_backup_policy            = true

  allowed_security_group_ids = ["sg-0123456789abcdef0"]
  allowed_cidr_blocks        = ["10.0.0.0/16"]

  tags = {
    StorageClass = "SharedPOSIX"
    Workload     = "EKS-PersistentVolumes"
  }
}
```

---

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | :---: |
| `application` | Logical application or product name used for resource naming and tagging. | `string` | **Required** | Yes |
| `environment` | Deployment environment name (e.g. dev, staging, prod) used for isolation and tagging. | `string` | **Required** | Yes |
| `name` | Optional additional identifier appended to the resource name. | `string` | `null` | No |
| `tags` | A map of additional tags to apply to all resources created by this module. | `map(string)` | `{}` | No |
| `vpc_id` | VPC ID where the EFS mount targets and security groups are provisioned. | `string` | **Required** | Yes |
| `subnet_ids` | List of private subnet IDs to create mount targets in. | `list(string)` | **Required** | Yes |
| `kms_key_arn` | ARN of the customer-managed KMS key used to encrypt the EFS file system at rest. | `string` | **Required** | Yes |
| `performance_mode` | EFS performance mode: generalPurpose or maxIO. | `string` | `"generalPurpose"` | No |
| `throughput_mode` | EFS throughput mode: elastic, bursting, or provisioned. | `string` | `"elastic"` | No |
| `provisioned_throughput_in_mibps` | Provisioned throughput in MiB/s; only used when throughput_mode is provisioned. | `number` | `null` | No |
| `transition_to_ia` | Number of days before transitioning files to Infrequent Access storage. | `string` | `"AFTER_7_DAYS"` | No |
| `transition_to_archive` | Number of days before transitioning files to Archive storage class (null to disable). | `string` | `"AFTER_30_DAYS"` | No |
| `enable_backup` | Whether to enable AWS Backup automatic policy for EFS. | `bool` | `true` | No |
| `security_group_ids` | Optional list of existing security group IDs to associate with mount targets. If empty, a default SG is created. | `list(string)` | `[]` | No |
| `allowed_security_group_ids` | List of security group IDs permitted to connect to EFS on port 2049. | `list(string)` | `[]` | No |
| `allowed_cidr_blocks` | List of CIDR blocks permitted to connect to EFS on port 2049. | `list(string)` | `[]` | No |
| `allowed_client_role_arns` | List of IAM role ARNs allowed to mount and write to the file system. | `list(string)` | `[]` | No |
| `access_points` | Map of access point configurations to create for this file system. | `map(object({...}))` | `{}` | No |

---

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | :---: |
| `id` | ID of the EFS file system. | No |
| `arn` | ARN of the EFS file system. | No |
| `dns_name` | DNS name of the EFS file system. | No |
| `mount_target_ids` | Map of subnet IDs to mount target IDs. | No |
| `security_group_id` | ID of the created EFS security group (if created). | No |
| `access_points` | Map of created EFS access points. | No |
