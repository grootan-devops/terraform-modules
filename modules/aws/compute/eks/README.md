# AWS EKS Unified Module

The `eks` module provides an enterprise-grade Kubernetes control plane orchestrating managed node groups, Pod Identity add-ons, and KMS envelope encryption.

## Architecture & Managed Resources

- Invokes `modules/eks/cluster` for the hardened control plane.
- Invokes `modules/eks/node_group` for launch template-backed worker pools.
- Integrates VPC CNI, EBS CSI Driver, EFS CSI Driver, and CoreDNS.

### Security & Compliance Guardrails

- **KMS Secrets Envelope Encryption**: Kubernetes secrets encrypted with `kms_key_arn`.
- **IMDSv2 Enforced**: Node groups enforce `http_tokens = "required"`.
- **Private API Endpoints**: Supports private-only or restricted CIDR public access.

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
module "eks" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/compute/eks?ref=1.0.0"

  application = "core"
  environment = "prod"
  name        = "k8s"

  cluster_version           = "1.30"
  vpc_id                    = "vpc-0a1b2c3d4e5f67890"
  control_plane_subnet_ids  = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  kms_key_arn               = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
}
```

### Complete Production Example

```hcl
module "eks" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/compute/eks?ref=1.0.0"

  application = "platform"
  environment = "prod"
  name        = "production-cluster"

  cluster_version          = "1.30"
  vpc_id                   = "vpc-0a1b2c3d4e5f67890"
  control_plane_subnet_ids = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  kms_key_arn              = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"

  endpoint_private_access = true
  endpoint_public_access  = false

  node_groups = {
    system = {
      subnet_ids     = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
      instance_types = ["m7g.large"]
      min_size       = 3
      max_size       = 6
      desired_size   = 3
      disk_size      = 50
    },
    workload = {
      subnet_ids     = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
      instance_types = ["m7g.xlarge"]
      min_size       = 3
      max_size       = 15
      desired_size   = 5
      disk_size      = 100
      labels = {
        tier = "apps"
      }
    }
  }

  tags = {
    ClusterRole = "PrimaryWorkload"
  }
}
```

---

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | :---: |
| `application` | Logical application or product name used for resource naming and tagging. | `string` | **Required** | Yes |
| `environment` | Deployment environment name (e.g. dev, staging, prod) used for isolation and tagging. | `string` | **Required** | Yes |
| `name` | Optional additional identifier appended to the cluster name. | `string` | `null` | No |
| `tags` | A map of additional tags to apply to all resources created by this module. | `map(string)` | `{}` | No |
| `kms_key_arn` | ARN of the customer-managed KMS key used for Kubernetes secrets envelope encryption and EBS root volume encryption. | `string` | **Required** | Yes |
| `cluster_version` | Kubernetes version for the EKS cluster control plane. | `string` | `"1.30"` | No |
| `control_plane_subnet_ids` | List of private subnet IDs for the EKS control plane ENIs. | `list(string)` | **Required** | Yes |
| `security_group_ids` | Additional security group IDs to associate with the cluster control plane. | `list(string)` | `[]` | No |
| `endpoint_public_access` | Whether the Amazon EKS public API server endpoint is enabled. Defaults to false for enterprise security baseline. | `bool` | `false` | No |
| `public_access_cidrs` | List of CIDR blocks permitted to access the public API server endpoint when endpoint_public_access is true. | `list(string)` | `[]` | No |
| `node_groups` | Configuration map of managed node groups to create. | `map(object({...}))` | `{}` | No |

---

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | :---: |
| `cluster_name` | Name of the EKS cluster. | No |
| `cluster_arn` | ARN of the EKS cluster. | No |
| `cluster_endpoint` | Endpoint URL for the Kubernetes API server. | No |
| `cluster_certificate_authority_data` | Base64-encoded certificate data required to communicate with the cluster. | No |
| `cluster_security_group_id` | Security group ID created by AWS EKS for cluster-to-node communication. | No |
| `cluster_role_arn` | IAM role ARN used by the EKS control plane. | No |
| `node_group_arns` | Map of node group keys to their resource ARNs. | No |
| `node_group_ids` | Map of node group keys to their resource IDs. | No |
| `node_role_arn` | ARN of the IAM role used by the worker nodes. | No |
