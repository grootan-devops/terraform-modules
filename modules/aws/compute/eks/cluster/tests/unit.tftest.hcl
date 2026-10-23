mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      name   = "us-west-2"
      region = "us-west-2"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  # The provider validates ARN-typed arguments, so computed ARNs that feed
  # other resources need ARN-shaped mock values.
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/core-prod-k8s-mock"
    }
  }

  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/core-prod-k8s-mock"
    }
  }

  # certificate_authority is a computed list the outputs index into.
  mock_resource "aws_eks_cluster" {
    defaults = {
      arn      = "arn:aws:eks:us-west-2:123456789012:cluster/core-prod-k8s"
      endpoint = "https://0123456789ABCDEF0123456789ABCDEF.gr7.us-west-2.eks.amazonaws.com"
      certificate_authority = [
        {
          data = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t"
        }
      ]
      identity = [
        {
          oidc = [
            {
              issuer = "https://oidc.eks.us-west-2.amazonaws.com/id/0123456789ABCDEF0123456789ABCDEF"
            }
          ]
        }
      ]
    }
  }
}

variables {
  application = "core"
  environment = "prod"
  name        = "k8s"
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
  subnet_ids  = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
}

# ------------------------------------------------------------------------------
# Naming
# ------------------------------------------------------------------------------
run "verify_rendered_names" {
  command = plan

  assert {
    condition     = aws_eks_cluster.this.name == "core-prod-k8s"
    error_message = "EKS cluster name did not match <application>-<environment>-<name>."
  }

  assert {
    condition     = aws_cloudwatch_log_group.eks_cluster.name == "/aws/eks/core-prod-k8s/cluster"
    error_message = "Control plane log group must be /aws/eks/<cluster_name>/cluster so EKS writes into the managed group."
  }

  assert {
    condition     = aws_iam_role.eks_cluster.name == "core-prod-k8s-eks-cluster"
    error_message = "Cluster IAM role name did not match <rendered_name>-eks-cluster."
  }

  assert {
    condition = (
      aws_iam_role.eks_vpc_cni.name == "core-prod-k8s-eks-vpc-cni" &&
      aws_iam_role.ebs_csi.name == "core-prod-k8s-ebs-csi" &&
      aws_iam_role.efs_csi.name == "core-prod-k8s-efs-csi" &&
      aws_iam_role.efs_csi_node.name == "core-prod-k8s-efs-csi-node" &&
      aws_iam_role.s3_csi.name == "core-prod-k8s-s3-csi"
    )
    error_message = "Add-on Pod Identity role names did not match <rendered_name>-<addon>."
  }

  assert {
    condition     = aws_iam_policy.efs_csi_node.name == "core-prod-k8s-efs-csi-node-policy"
    error_message = "EFS CSI node policy name did not match <rendered_name>-efs-csi-node-policy."
  }

  assert {
    condition     = aws_iam_role.aws_lb_controller[0].name == "core-prod-k8s-aws-lb-controller" && aws_iam_policy.aws_lb_controller[0].name == "core-prod-k8s-aws-lb-controller"
    error_message = "Load Balancer Controller role and policy names did not match <rendered_name>-aws-lb-controller."
  }
}

run "verify_name_fallback_when_null" {
  command = plan

  variables {
    name = null
  }

  assert {
    condition     = aws_eks_cluster.this.name == "core-prod"
    error_message = "A null name must fall back to <application>-<environment>."
  }

  assert {
    condition     = aws_cloudwatch_log_group.eks_cluster.name == "/aws/eks/core-prod/cluster"
    error_message = "Log group name must use the fallback rendered name."
  }

  assert {
    condition     = aws_eks_cluster.this.tags["Name"] == "core-prod"
    error_message = "Name tag must use the fallback rendered name."
  }
}

run "verify_name_fallback_when_empty" {
  command = plan

  variables {
    name = ""
  }

  assert {
    condition     = aws_eks_cluster.this.name == "core-prod"
    error_message = "An empty name must fall back to <application>-<environment>."
  }

  assert {
    condition     = aws_iam_role.eks_cluster.name == "core-prod-eks-cluster"
    error_message = "Cluster IAM role name must use the fallback rendered name."
  }
}

# ------------------------------------------------------------------------------
# Tags
# ------------------------------------------------------------------------------
run "verify_governance_and_caller_tags" {
  command = plan

  variables {
    tags = {
      CostCenter = "platform"
      Owner      = "platform-team"
    }
  }

  assert {
    condition = alltrue([
      for t in concat(
        [aws_eks_cluster.this.tags, aws_cloudwatch_log_group.eks_cluster.tags],
        [for addon in aws_eks_addon.this : addon.tags],
      ) :
      t["Application"] == "core" && t["Environment"] == "prod" && t["Name"] == "core-prod-k8s"
    ])
    error_message = "The cluster, log group and add-ons must carry the Application, Environment and Name governance tags."
  }

  assert {
    condition = alltrue([
      for t in concat(
        [aws_eks_cluster.this.tags, aws_cloudwatch_log_group.eks_cluster.tags],
        [for addon in aws_eks_addon.this : addon.tags],
      ) :
      t["CostCenter"] == "platform" && t["Owner"] == "platform-team"
    ])
    error_message = "Caller tags from var.tags must be preserved on the cluster, log group and add-ons."
  }
}

# ------------------------------------------------------------------------------
# Security and shipped defaults
# ------------------------------------------------------------------------------
run "verify_security_defaults" {
  command = plan

  variables {
    # Must be ignored while the public endpoint is disabled.
    public_access_cidrs = ["203.0.113.0/24"]
  }

  assert {
    condition     = aws_eks_cluster.this.encryption_config[0].provider[0].key_arn == "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
    error_message = "Kubernetes secrets must be envelope-encrypted with var.kms_key_arn."
  }

  assert {
    condition     = aws_eks_cluster.this.encryption_config[0].resources == toset(["secrets"])
    error_message = "Envelope encryption must cover the secrets resource."
  }

  assert {
    condition     = aws_cloudwatch_log_group.eks_cluster.kms_key_id == "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
    error_message = "Control plane log group must be encrypted with var.kms_key_arn."
  }

  assert {
    condition     = aws_cloudwatch_log_group.eks_cluster.retention_in_days == 90
    error_message = "Control plane log retention must default to 90 days."
  }

  assert {
    condition     = aws_cloudwatch_log_group.eks_cluster.deletion_protection_enabled == true
    error_message = "Control plane log group must have deletion protection enabled."
  }

  assert {
    condition     = aws_eks_cluster.this.deletion_protection == true
    error_message = "Cluster deletion protection must default to true."
  }

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_private_access == true
    error_message = "The private API endpoint must always be enabled."
  }

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_public_access == false
    error_message = "The public API endpoint must be disabled by default."
  }

  assert {
    condition     = length(aws_eks_cluster.this.vpc_config[0].public_access_cidrs) == 0
    error_message = "public_access_cidrs must be ignored while the public endpoint is disabled."
  }

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].subnet_ids == toset(["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"])
    error_message = "Control plane ENIs must be placed in var.subnet_ids."
  }

  assert {
    condition     = aws_eks_cluster.this.access_config[0].bootstrap_cluster_creator_admin_permissions == false
    error_message = "The cluster creator must not be granted admin permissions by default."
  }

  assert {
    condition     = aws_eks_cluster.this.enabled_cluster_log_types == toset(["api", "audit", "authenticator", "controllerManager", "scheduler"])
    error_message = "All five control plane log types must be enabled by default."
  }

  assert {
    condition     = aws_eks_cluster.this.bootstrap_self_managed_addons == false
    error_message = "Self-managed add-ons must not be bootstrapped; add-ons are EKS-managed."
  }

  assert {
    condition     = jsondecode(aws_iam_role.eks_cluster.assume_role_policy).Statement[0].Principal.Service == "eks.amazonaws.com"
    error_message = "The cluster role must only be assumable by eks.amazonaws.com."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.eks_cluster.policy_arn == "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
    error_message = "The cluster role must have AmazonEKSClusterPolicy attached."
  }

  assert {
    condition = alltrue([
      for role in [aws_iam_role.eks_vpc_cni, aws_iam_role.ebs_csi, aws_iam_role.efs_csi, aws_iam_role.efs_csi_node, aws_iam_role.s3_csi, aws_iam_role.aws_lb_controller[0]] :
      jsondecode(role.assume_role_policy).Statement[0].Principal.Service == "pods.eks.amazonaws.com" &&
      toset(jsondecode(role.assume_role_policy).Statement[0].Action) == toset(["sts:AssumeRole", "sts:TagSession"])
    ])
    error_message = "Add-on roles must only be assumable through EKS Pod Identity."
  }

  assert {
    condition     = jsondecode(aws_iam_policy.efs_csi_node.policy).Statement[0].Resource == "arn:aws:elasticfilesystem:us-west-2:123456789012:file-system/*"
    error_message = "The EFS CSI node policy must be scoped to file systems in the current account and region."
  }

  assert {
    condition = (
      toset(jsondecode(aws_iam_policy.efs_csi_node.policy).Statement[0].Action) == toset(["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"]) &&
      jsondecode(aws_iam_policy.efs_csi_node.policy).Statement[0].Condition.Bool["elasticfilesystem:AccessedViaMountTarget"] == "true"
    )
    error_message = "The EFS CSI node policy must only allow mount and write through a mount target."
  }
}

run "verify_shipped_defaults" {
  command = plan

  assert {
    condition     = aws_eks_cluster.this.version == "1.30"
    error_message = "Cluster version must default to 1.30."
  }

  assert {
    condition     = aws_eks_cluster.this.access_config[0].authentication_mode == "API_AND_CONFIG_MAP"
    error_message = "Authentication mode must default to API_AND_CONFIG_MAP."
  }

  assert {
    condition     = aws_eks_cluster.this.upgrade_policy[0].support_type == "STANDARD"
    error_message = "Upgrade support type must default to STANDARD."
  }

  assert {
    condition     = length(aws_eks_cluster.this.vpc_config[0].security_group_ids) == 0
    error_message = "No additional control plane security groups should be attached by default."
  }

  assert {
    condition = keys(aws_eks_addon.this) == [
      "aws-ebs-csi-driver",
      "aws-efs-csi-driver",
      "coredns",
      "eks-pod-identity-agent",
      "kube-proxy",
      "snapshot-controller",
      "vpc-cni",
    ]
    error_message = "The seven default managed add-ons must be installed by default."
  }

  assert {
    condition = alltrue([
      for addon in aws_eks_addon.this :
      addon.cluster_name == "core-prod-k8s" &&
      addon.resolve_conflicts_on_create == "OVERWRITE" &&
      addon.resolve_conflicts_on_update == "OVERWRITE"
    ])
    error_message = "Add-ons must target the module cluster and resolve conflicts with OVERWRITE."
  }

  assert {
    condition     = jsondecode(aws_eks_addon.this["vpc-cni"].configuration_values).env.ENABLE_PREFIX_DELEGATION == "true"
    error_message = "VPC CNI must enable prefix delegation."
  }

  assert {
    condition     = jsondecode(aws_eks_addon.this["coredns"].configuration_values).replicaCount == 2
    error_message = "CoreDNS must run two replicas."
  }

  assert {
    condition = (
      length(aws_eks_pod_identity_association.vpc_cni) == 1 &&
      length(aws_eks_pod_identity_association.ebs_csi) == 1 &&
      length(aws_eks_pod_identity_association.efs_csi) == 1 &&
      length(aws_eks_pod_identity_association.efs_csi_node) == 1 &&
      length(aws_eks_pod_identity_association.aws_lb_controller) == 1
    )
    error_message = "Pod Identity associations must be created for the default add-ons and the Load Balancer Controller."
  }

  assert {
    condition = (
      aws_eks_pod_identity_association.vpc_cni[0].service_account == "aws-node" &&
      aws_eks_pod_identity_association.ebs_csi[0].service_account == "ebs-csi-controller-sa" &&
      aws_eks_pod_identity_association.efs_csi[0].service_account == "efs-csi-controller-sa" &&
      aws_eks_pod_identity_association.efs_csi_node[0].service_account == "efs-csi-node-sa" &&
      aws_eks_pod_identity_association.aws_lb_controller[0].service_account == "aws-load-balancer-controller"
    )
    error_message = "Pod Identity associations must bind the expected service accounts."
  }

  assert {
    condition = alltrue([
      for a in [
        aws_eks_pod_identity_association.vpc_cni[0],
        aws_eks_pod_identity_association.ebs_csi[0],
        aws_eks_pod_identity_association.efs_csi[0],
        aws_eks_pod_identity_association.efs_csi_node[0],
        aws_eks_pod_identity_association.aws_lb_controller[0],
      ] : a.namespace == "kube-system" && a.cluster_name == "core-prod-k8s"
    ])
    error_message = "Pod Identity associations must target kube-system on the module cluster."
  }

  assert {
    condition = (
      aws_iam_role_policy_attachment.eks_vpc_cni.policy_arn == "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy" &&
      aws_iam_role_policy_attachment.ebs_csi.policy_arn == "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy" &&
      aws_iam_role_policy_attachment.efs_csi.policy_arn == "arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"
    )
    error_message = "Add-on roles must have their AWS managed driver policies attached."
  }

  assert {
    condition     = length(aws_iam_role.aws_lb_controller) == 1 && length(aws_iam_policy.aws_lb_controller) == 1 && length(aws_iam_role_policy_attachment.aws_lb_controller) == 1
    error_message = "The Load Balancer Controller role and policy must be created by default."
  }
}

run "verify_addons_and_lb_controller_can_be_disabled" {
  command = plan

  variables {
    enable_default_addons     = false
    enable_lb_controller_role = false
  }

  assert {
    condition     = length(aws_eks_addon.this) == 0
    error_message = "No managed add-ons should be installed when enable_default_addons is false."
  }

  assert {
    condition = (
      length(aws_eks_pod_identity_association.vpc_cni) == 0 &&
      length(aws_eks_pod_identity_association.ebs_csi) == 0 &&
      length(aws_eks_pod_identity_association.efs_csi) == 0 &&
      length(aws_eks_pod_identity_association.efs_csi_node) == 0 &&
      length(aws_eks_pod_identity_association.aws_lb_controller) == 0
    )
    error_message = "No Pod Identity associations should be created when add-ons and the Load Balancer Controller are disabled."
  }

  assert {
    condition = (
      length(aws_iam_role.aws_lb_controller) == 0 &&
      length(aws_iam_policy.aws_lb_controller) == 0 &&
      length(aws_iam_role_policy_attachment.aws_lb_controller) == 0
    )
    error_message = "No Load Balancer Controller IAM resources should be created when enable_lb_controller_role is false."
  }
}

# ------------------------------------------------------------------------------
# Parameter overrides
# ------------------------------------------------------------------------------
run "verify_optional_inputs_flow_through" {
  command = plan

  variables {
    cluster_version                             = "1.31"
    endpoint_public_access                      = true
    public_access_cidrs                         = ["203.0.113.0/24"]
    security_group_ids                          = ["sg-0123456789abcdef0"]
    log_types                                   = ["api", "audit"]
    log_retention_in_days                       = 365
    deletion_protection                         = false
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
    upgrade_support_type                        = "EXTENDED"

    addon_versions = {
      vpc_cni = "v1.19.0-eksbuild.1"
      coredns = "v1.11.3-eksbuild.2"
    }
  }

  assert {
    condition     = aws_eks_cluster.this.version == "1.31"
    error_message = "cluster_version did not flow through."
  }

  assert {
    condition = (
      aws_eks_cluster.this.vpc_config[0].endpoint_public_access == true &&
      aws_eks_cluster.this.vpc_config[0].public_access_cidrs == toset(["203.0.113.0/24"])
    )
    error_message = "Public endpoint access must be limited to public_access_cidrs when enabled."
  }

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].endpoint_private_access == true
    error_message = "The private API endpoint must stay enabled when the public endpoint is enabled."
  }

  assert {
    condition     = aws_eks_cluster.this.vpc_config[0].security_group_ids == toset(["sg-0123456789abcdef0"])
    error_message = "security_group_ids did not flow through."
  }

  assert {
    condition     = aws_eks_cluster.this.enabled_cluster_log_types == toset(["api", "audit"])
    error_message = "log_types did not flow through."
  }

  assert {
    condition     = aws_cloudwatch_log_group.eks_cluster.retention_in_days == 365
    error_message = "log_retention_in_days did not flow through."
  }

  assert {
    condition     = aws_eks_cluster.this.deletion_protection == false
    error_message = "deletion_protection override did not flow through."
  }

  assert {
    condition = (
      aws_eks_cluster.this.access_config[0].authentication_mode == "API" &&
      aws_eks_cluster.this.access_config[0].bootstrap_cluster_creator_admin_permissions == true
    )
    error_message = "Access config overrides did not flow through."
  }

  assert {
    condition     = aws_eks_cluster.this.upgrade_policy[0].support_type == "EXTENDED"
    error_message = "upgrade_support_type did not flow through."
  }

  assert {
    condition = (
      aws_eks_addon.this["vpc-cni"].addon_version == "v1.19.0-eksbuild.1" &&
      aws_eks_addon.this["coredns"].addon_version == "v1.11.3-eksbuild.2"
    )
    error_message = "addon_versions did not flow through to the add-ons."
  }
}

# ------------------------------------------------------------------------------
# Wiring and outputs (needs computed values)
# ------------------------------------------------------------------------------
run "verify_role_wiring_and_outputs" {
  command   = apply
  state_key = "verify_role_wiring_and_outputs"

  override_resource {
    target = aws_iam_role.eks_cluster
    values = {
      arn = "arn:aws:iam::123456789012:role/core-prod-k8s-eks-cluster"
    }
  }

  override_resource {
    target = aws_iam_role.eks_vpc_cni
    values = {
      arn = "arn:aws:iam::123456789012:role/core-prod-k8s-eks-vpc-cni"
    }
  }

  override_resource {
    target = aws_iam_role.ebs_csi
    values = {
      arn = "arn:aws:iam::123456789012:role/core-prod-k8s-ebs-csi"
    }
  }

  override_resource {
    target = aws_iam_policy.efs_csi_node
    values = {
      arn = "arn:aws:iam::123456789012:policy/core-prod-k8s-efs-csi-node-policy"
    }
  }

  assert {
    condition     = aws_eks_cluster.this.role_arn == "arn:aws:iam::123456789012:role/core-prod-k8s-eks-cluster"
    error_message = "The cluster must use the module-created cluster role."
  }

  assert {
    condition     = aws_eks_pod_identity_association.vpc_cni[0].role_arn == "arn:aws:iam::123456789012:role/core-prod-k8s-eks-vpc-cni"
    error_message = "The VPC CNI Pod Identity association must use the VPC CNI role."
  }

  assert {
    condition     = aws_eks_pod_identity_association.ebs_csi[0].role_arn == "arn:aws:iam::123456789012:role/core-prod-k8s-ebs-csi"
    error_message = "The EBS CSI Pod Identity association must use the EBS CSI role."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.efs_csi_node.policy_arn == "arn:aws:iam::123456789012:policy/core-prod-k8s-efs-csi-node-policy"
    error_message = "The EFS CSI node role must have the module EFS CSI node policy attached."
  }

  assert {
    condition     = output.cluster_name == "core-prod-k8s"
    error_message = "cluster_name output must expose the rendered cluster name."
  }

  assert {
    condition     = output.cluster_arn == "arn:aws:eks:us-west-2:123456789012:cluster/core-prod-k8s"
    error_message = "cluster_arn output must expose the cluster ARN."
  }

  assert {
    condition     = output.cluster_endpoint == "https://0123456789ABCDEF0123456789ABCDEF.gr7.us-west-2.eks.amazonaws.com"
    error_message = "cluster_endpoint output must expose the cluster endpoint."
  }

  assert {
    condition     = output.cluster_certificate_authority_data == "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t"
    error_message = "cluster_certificate_authority_data output must expose the cluster CA data."
  }

  assert {
    condition     = output.cluster_role_arn == "arn:aws:iam::123456789012:role/core-prod-k8s-eks-cluster"
    error_message = "cluster_role_arn output must expose the cluster role ARN."
  }

  assert {
    condition     = output.cluster_security_group_id == aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
    error_message = "cluster_security_group_id output must expose the EKS-managed cluster security group."
  }
}

# ------------------------------------------------------------------------------
# Validation
# ------------------------------------------------------------------------------
run "verify_invalid_application_fails" {
  command = plan

  variables {
    application = "Core_App"
  }

  expect_failures = [var.application]
}

run "verify_invalid_environment_fails" {
  command = plan

  variables {
    environment = "sandbox"
  }

  expect_failures = [var.environment]
}

run "verify_invalid_kms_key_arn_fails" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:s3:::core-prod-bucket"
  }

  expect_failures = [var.kms_key_arn]
}

run "verify_kms_alias_arn_is_accepted" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:us-west-2:123456789012:alias/core-prod-eks"
  }

  assert {
    condition     = aws_eks_cluster.this.encryption_config[0].provider[0].key_arn == "arn:aws:kms:us-west-2:123456789012:alias/core-prod-eks"
    error_message = "A KMS alias ARN must pass validation and flow through to envelope encryption."
  }
}
