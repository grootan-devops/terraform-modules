# AWS EKS Module

Scope: `workload`

An EKS cluster with managed node groups, optional Fargate profiles, access entries, EKS Pod Identity for workloads,
the default add-ons with their own Pod Identity roles, a Load Balancer Controller role and a control plane log group.
Kubernetes resources (Helm releases, namespaces, the Load Balancer Controller itself) are deployed outside this module.

## Architecture & Managed Resources

- `aws_eks_cluster.this`: `<application>-<environment>[-<name>]`, private endpoint, `API` authentication mode,
  deletion protection, `bootstrap_self_managed_addons = false`.
- `module.cluster_role` ([`security/iam-role`](../../security/iam-role)): trusted by EKS for this cluster only.
- `aws_launch_template.this`, `aws_eks_node_group.this`: one per `node_groups` key, `<base>-<key>-<suffix>`
  (create before destroy), shared `module.node_role` (`<base>-node-<region>`).
- `aws_eks_fargate_profile.this` and `module.fargate_role`: only with `fargate_profiles`.
- `aws_eks_access_entry.this`, `aws_eks_access_policy_association.this`: `access_entries`; a policy is an access
  policy name (`AmazonEKSClusterAdminPolicy`) or ARN, scoped to `namespaces` when given.
- `aws_eks_pod_identity_association.this`, `module.workload_role`: `pod_identities`; `policy_statements` or
  `managed_policy_arns` create `<base>-<key>-pod-<region>`, `role_arn` uses your role.
- `aws_eks_addon.before_compute` (vpc-cni, kube-proxy, eks-pod-identity-agent) and `aws_eks_addon.this` (coredns,
  EBS CSI, EFS CSI, snapshot controller, S3 CSI with bucket ARNs, CloudWatch Observability with
  `container_insights.enabled`), `module.addon_role`, `module.lb_controller_role` and
  `aws_eks_pod_identity_association.lb_controller`: only with `addons.enabled` (default).
- `module.log_group` ([`observability/log-group`](../../observability/log-group)): `/aws/eks/<cluster>/cluster`, only
  with `cloudwatch_logs.log_types`.
- `module.insights_log_group` ([`observability/log-group`](../../observability/log-group)):
  `/aws/containerinsights/<cluster>/{application,dataplane,host,performance}`, only with `container_insights.enabled`.
- `module.security_group` ([`network/security-group`](../../network/security-group)): extra control plane group with
  HTTPS (443) ingress from the listed sources; EKS also creates its own cluster security group.
- `module.encryption` ([`core/encryption`](../../core/encryption)): secrets, node volumes and logs.
- `module.alarms` ([`observability/cloudwatch-alarms`](../../observability/cloudwatch-alarms)): built-in alarms, on by
  default; see [Built-in Alarms](#built-in-alarms).

## Security & Compliance Guardrails

- **Endpoint (EKS.1):** private only; `endpoint_public_access_cidrs` opens the public endpoint to those CIDRs, and
  `/0` is rejected.
- **Version (EKS.2, EKS.9):** `cluster_version` is required; node groups follow it unless `release_version` is set.
- **Audit logging (EKS.8):** all five control plane log types by default, kept 365 days with deletion protection.
- **Secrets:** with `kms.create` or `kms.key_id`, Kubernetes secrets are envelope-encrypted with that key; without
  it, EKS encrypts all Kubernetes API data with an AWS owned key (Kubernetes 1.28+), the reason for the Trivy
  suppression `AVD-AWS-0039`.
- **Nodes:** IMDSv2 with hop limit 2, encrypted gp3 volumes (module key or the AWS managed EBS key), governance tags
  on instances and volumes. The node role has `AmazonEKSWorkerNodePolicy` and `AmazonEC2ContainerRegistryPullOnly`;
  `AmazonEKS_CNI_Policy` moves to the VPC CNI Pod Identity role when add-ons are on.
- **Access:** access entries only; `bootstrap_cluster_creator_admin_permissions` (default `true`) gives the creating
  principal admin access so the cluster is usable; set it to `false` with an admin access entry.
- **Pod Identity:** every add-on, controller and workload role trusts `pods.eks.amazonaws.com` (`sts:AssumeRole`,
  `sts:TagSession`). The S3 CSI role reads and writes only the listed buckets and decrypts only through S3; the EFS
  node role mounts only through mount targets; the CloudWatch agent role has `CloudWatchAgentServerPolicy`. Fargate
  pods cannot use Pod Identity.
- **Tags (EKS.6):** caller tags first, governance tags last, on every taggable resource.

A key passed in `kms.key_id` must allow the cluster role (`kms:Encrypt`, `kms:Decrypt`, `kms:ListGrants`,
`kms:DescribeKey`, `kms:CreateGrant`), `logs.<region>.amazonaws.com` (encryption context `aws:logs:arn`) and EBS use
through `ec2.<region>.amazonaws.com` by the account's principals (the Auto Scaling service-linked role launches
nodes).

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "eks" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/compute/eks?ref=<version>"

  application     = "core"
  environment     = "prod"
  cluster_version = "1.37"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids

  node_groups = {
    general = { instance_types = ["m7i.large"], min_size = 2, max_size = 6 }
  }
}
```

### Complete Production Example

```hcl
module "eks" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/compute/eks?ref=<version>"

  application     = "core"
  environment     = "prod"
  name            = "apps"
  cluster_version = "1.37"
  kms             = { create = true }
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids

  bootstrap_cluster_creator_admin_permissions = false
  security_group = { ingress_security_group_ids = [module.ci_runners.security_group_id] }

  access_entries = {
    admins = {
      principal_arn       = module.platform_admin_role.arn
      policy_associations = { admin = { policy = "AmazonEKSClusterAdminPolicy" } }
    }
    orders = {
      principal_arn       = module.orders_team_role.arn
      policy_associations = { edit = { policy = "AmazonEKSEditPolicy", namespaces = ["orders"] } }
    }
  }

  node_groups = {
    general = { instance_types = ["m7i.large"], min_size = 3, max_size = 9 }
    spot    = { instance_types = ["c7i.large", "c6i.large"], capacity_type = "SPOT", max_size = 20, taints = [{ key = "spot", value = "true", effect = "NO_SCHEDULE" }] }
  }

  addons = { s3_csi_bucket_arns = [module.models_bucket.arn] }

  pod_identities = {
    orders = {
      namespace         = "orders"
      service_account   = "orders-api"
      policy_statements = [{ sid = "ReadOrders", actions = ["dynamodb:GetItem", "dynamodb:Query"], resources = [module.orders_table.arn] }]
    }
  }
}
```

### Container Insights

`container_insights = { enabled = true }` installs the `amazon-cloudwatch-observability` add-on after the nodes,
with a Pod Identity role (`<base>-cloudwatch-agent-<region>`, `CloudWatchAgentServerPolicy`) for the `cloudwatch-agent`
service account. It is off by default: CloudWatch charges for the metrics, logs and observations it sends. It needs
`addons.enabled`; `addons.versions` and `addons.configuration_values` take the add-on name. The module creates the
agent's log groups first (`/aws/containerinsights/<cluster>/` `application`, `dataplane`, `host` and `performance`)
with the `cloudwatch_logs` retention, class, deletion protection and key, so the agent never creates unencrypted
groups that keep logs forever.

### Built-in Alarms

The `auto_scaling_groups` preset of [`observability/cloudwatch-alarms`](../../observability/cloudwatch-alarms) is on
by default, one set per `node_groups` key on the node group's Auto Scaling group: `asg-<key>-cpu` (80 %) and
`asg-<key>-status-check-failed` (critical). The `eks_clusters` preset follows `container_insights`:
`eks-cluster-node-cpu` and `eks-cluster-node-memory` (80 %) and `eks-cluster-failed-nodes` (critical), only while it
is enabled. No alarm is opt-in. Without `topic_arns` the alarms have no actions; `alarms = { enabled = false }`
creates none.

```hcl
module "alarm_routing" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/observability/alarm-routing?ref=<version>"

  environment = "prod"
}

module "eks" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/compute/eks?ref=<version>"

  application        = "core"
  environment        = "prod"
  cluster_version    = "1.37"
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.private_subnet_ids
  container_insights = { enabled = true }

  node_groups = {
    general = { instance_types = ["m7i.large"], min_size = 2, max_size = 6 }
  }

  alarms = {
    topic_arns = module.alarm_routing.topic_arns["eu-west-1"]
    overrides = {
      cluster     = { node_cpu = { threshold = 90 } }
      node_groups = { status_check_failed = { enabled = false } }
    }
  }
}
```

`overrides.cluster` and `overrides.node_groups` take each preset's alarm keys and fields (`enabled`, `threshold`,
`evaluation_periods`, `datapoints_to_alarm`, `period`, `severity`); `node_groups` applies to every node group, and a
field left out keeps the preset default.

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | **Required** | Yes |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `name` | Cluster name. | `string` | `null` | No |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `cluster_version` | Kubernetes minor version, e.g. 1.37. | `string` | **Required** | Yes |
| `upgrade_support_type` | STANDARD or EXTENDED support. | `string` | `"STANDARD"` | No |
| `deletion_protection` | Block cluster deletion. | `bool` | `true` | No |
| `vpc_id` | VPC ID. | `string` | **Required** | Yes |
| `subnet_ids` | Private subnet IDs for the control plane and, by default, the nodes. | `list(string)` | **Required** | Yes |
| `endpoint_public_access_cidrs` | CIDRs allowed to the public API endpoint. Empty: private endpoint only. | `list(string)` | `[]` | No |
| `security_group` | Extra control plane security group: API (443) ingress sources and extra groups. | `object({...})` | `{}` | No |
| `bootstrap_cluster_creator_admin_permissions` | Admin access entry for the cluster creator. | `bool` | `true` | No |
| `access_entries` | Access entries by key: principal, Kubernetes groups and access policies. | `map(object({...}))` | `{}` | No |
| `kms` | Encryption: {} AWS managed key, create = true module key, key_id your key (ARN or ID). | `object({...})` | `{}` | No |
| `cloudwatch_logs` | Control plane log types and their log group. | `object({...})` | `{}` | No |
| `iam_role` | Node role: extend it or bring your own. | `object({...})` | `{}` | No |
| `node_groups` | Managed node groups by key. | `map(object({...}))` | `{}` | No |
| `fargate_profiles` | Fargate profiles by key: selectors and optional subnets. | `map(object({...}))` | `{}` | No |
| `addons` | Default add-ons with Pod Identity roles, Load Balancer Controller role and S3 CSI driver. | `object({...})` | `{}` | No |
| `container_insights` | Container Insights through the CloudWatch Observability add-on. | `object({...})` | `{}` | No |
| `pod_identities` | Workload Pod Identity associations by key: role_arn, or statements for a module role. | `map(object({...}))` | `{}` | No |
| `alarms` | Built-in CloudWatch alarms: switch, topics by severity, per-alarm overrides. | `object({...})` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `name` | Cluster name. | No |
| `arn` | Cluster ARN. | No |
| `endpoint` | Kubernetes API endpoint. | No |
| `certificate_authority_data` | Base64 cluster CA certificate. | No |
| `oidc_issuer_url` | OIDC issuer URL. | No |
| `cluster_security_group_id` | EKS-managed cluster security group ID. | No |
| `security_group_id` | Module API security group ID; null without one. | No |
| `cluster_role_arn` | Cluster role ARN. | No |
| `node_role_arn` | Node role ARN; null without node groups. | No |
| `node_role_name` | Node role name; null for a role brought by the caller. | No |
| `node_group_names` | Node group names by key. | No |
| `autoscaling_group_names` | Auto Scaling group names by node group key. | No |
| `launch_template_ids` | Launch template IDs by node group key. | No |
| `fargate_role_arn` | Fargate pod execution role ARN; null without profiles. | No |
| `pod_identity_role_arns` | Workload Pod Identity role ARNs by key. | No |
| `log_group_name` | Control plane log group name; null without log types. | No |
| `log_group_arn` | Control plane log group ARN; null without log types. | No |
| `kms_key_arn` | Key ARN in use; null for the AWS managed key. | No |
| `alarm_arns` | Alarm ARN by key. | No |
| `alarm_names` | Alarm name by key. | No |
