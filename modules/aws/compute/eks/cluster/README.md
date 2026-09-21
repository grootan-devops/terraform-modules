# AWS EKS Cluster Submodule

Standalone Amazon Elastic Kubernetes Service (EKS) control plane submodule managing API endpoints, KMS envelope encryption for secrets, and CloudWatch audit logs.

## Architecture & Managed Resources

- `aws_eks_cluster.this`: Primary EKS control plane.
- `aws_cloudwatch_log_group.this`: KMS-encrypted control plane audit log group.
- `aws_iam_role.cluster`: EKS cluster administrative IAM role.
- `aws_eks_addon`: Core Kubernetes add-ons with Pod Identity roles.

### Security & Compliance Guardrails

- **Envelope Encryption**: Secrets encrypted with `kms_key_arn`.
- **Encrypted Logging**: CloudWatch log group encrypted with `kms_key_arn` and 90-day retention.

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
module "eks_cluster" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/compute/eks/cluster?ref=1.0.0"

  application = "core"
  environment = "prod"
  name        = "control-plane"

  cluster_version = "1.30"
  subnet_ids      = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  kms_key_arn     = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
}
```

### Complete Production Example

```hcl
module "eks_cluster" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/compute/eks/cluster?ref=1.0.0"

  application = "platform"
  environment = "prod"
  name        = "control-plane"

  cluster_version         = "1.30"
  subnet_ids              = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  kms_key_arn             = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
  endpoint_private_access = true
  endpoint_public_access  = false

  tags = {
    Tier = "K8sControlPlane"
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
| `kms_key_arn` | ARN of the customer-managed KMS key used for Kubernetes secrets envelope encryption and CloudWatch log group encryption. | `string` | **Required** | Yes |
| `cluster_version` | Kubernetes version for the EKS cluster control plane. | `string` | `"1.30"` | No |
| `subnet_ids` | List of private subnet IDs for the EKS control plane ENIs. | `list(string)` | **Required** | Yes |
| `security_group_ids` | Additional security group IDs to associate with the cluster control plane. | `list(string)` | `[]` | No |
| `endpoint_public_access` | Whether the Amazon EKS public API server endpoint is enabled. Defaults to false for enterprise security baseline. | `bool` | `false` | No |
| `public_access_cidrs` | List of CIDR blocks permitted to access the public API server endpoint when endpoint_public_access is true. | `list(string)` | `[]` | No |
| `log_types` | Control plane log types to enable for auditing and operational observability. | `list(string)` | `[...]` | No |
| `log_retention_in_days` | Number of days to retain EKS control plane logs in CloudWatch. | `number` | `90` | No |
| `deletion_protection` | Whether to enable deletion protection on the EKS cluster. | `bool` | `true` | No |
| `authentication_mode` | Authentication mode for the cluster (API, CONFIG_MAP, or API_AND_CONFIG_MAP). | `string` | `"API_AND_CONFIG_MAP"` | No |
| `bootstrap_cluster_creator_admin_permissions` | Whether to grant the IAM entity that creates the cluster administrative permissions. | `bool` | `false` | No |
| `upgrade_support_type` | Support type for the cluster upgrade policy (STANDARD or EXTENDED). | `string` | `"STANDARD"` | No |
| `enable_default_addons` | Whether to install standard managed add-ons (VPC CNI, CoreDNS, Kube-Proxy, EBS CSI, EFS CSI). | `bool` | `true` | No |
| `enable_lb_controller_role` | Whether to create IAM role and policy for AWS Load Balancer Controller. | `bool` | `true` | No |
| `addon_versions` | Explicit versions for EKS addons. When null, AWS default compatible versions are resolved. | `object({...})` | `{}` | No |

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
| `oidc_provider_arn` | ARN of the OIDC provider associated with the cluster (if configured). | No |
