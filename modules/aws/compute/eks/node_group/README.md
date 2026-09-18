# AWS EKS Node Group Submodule

Standalone Amazon EKS Managed Node Group submodule providing EC2 launch templates with IMDSv2 enforcement, KMS-encrypted EBS volumes, and node autoscaling.

### Architecture & Managed Resources
- `aws_eks_node_group.this`: Managed node group instance pool.
- `aws_launch_template.this`: EC2 launch template enforcing IMDSv2 and EBS encryption.
- `aws_iam_role.node`: Worker node IAM role.

### Security & Compliance Guardrails
- **IMDSv2 Enforced**: `http_tokens = "required"`, `http_put_response_hop_limit = 1`.
- **Encrypted Storage**: Root volumes encrypted with `kms_key_arn`.

---

## Requirements & Providers

| Requirement | Version |
|---|---|
| `terraform` | `>= 1.5.0` |
| `aws` | `>= 6.0.0, < 7.0.0` |

---

## Usage Examples

### Minimal Working Example
```hcl
module "eks_node_group" {
  source = "git::https://github.com/organization/terraform-modules.git//modules/aws/compute/eks/node_group?ref=v1.0.0"

  application  = "core"
  environment  = "prod"
  name         = "default-workers"
  cluster_name = "core-prod-k8s"
  subnet_ids   = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  kms_key_arn  = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
}
```

### Complete Production Example
```hcl
module "eks_node_group" {
  source = "git::https://github.com/organization/terraform-modules.git//modules/aws/compute/eks/node_group?ref=v1.0.0"

  application  = "platform"
  environment  = "prod"
  name         = "compute-workers"
  cluster_name = "platform-prod-cluster"
  subnet_ids   = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  kms_key_arn  = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"

  instance_types = ["m7g.xlarge"]
  capacity_type  = "ON_DEMAND"
  disk_size      = 100

  scaling_config = {
    desired_size = 5
    max_size     = 15
    min_size     = 3
  }

  labels = {
    workload = "production"
  }

  tags = {
    NodeRole = "Worker"
  }
}
```

---

## Inputs Specification

| Name | Description | Type | Default | Required |
|---|---|---|---|:---:|
| `application` | Logical application or product name used for resource naming and tagging. | `string` | **Required** | Yes |
| `environment` | Deployment environment name (e.g. dev, staging, prod) used for isolation and tagging. | `string` | **Required** | Yes |
| `name` | Optional additional identifier appended to node group resources. | `string` | `null` | No |
| `tags` | A map of additional tags to apply to all resources created by this module. | `map(string)` | `{}` | No |
| `cluster_name` | Name of the target EKS cluster to attach managed node groups to. | `string` | **Required** | Yes |
| `kms_key_arn` | ARN of the customer-managed KMS key used to encrypt node group EBS root volumes. | `string` | **Required** | Yes |
| `node_groups` | Configuration map of managed node groups to create. | `map(object({...}))` | **Required** | Yes |


---

## Outputs Specification

| Name | Description | Sensitive |
|---|---|:---:|
| `node_group_arns` | Map of node group keys to their resource ARNs. | No |
| `node_group_ids` | Map of node group keys to their resource IDs. | No |
| `node_role_arn` | ARN of the IAM role used by the worker nodes. | No |
| `launch_template_ids` | Map of launch template IDs created for the node groups. | No |

