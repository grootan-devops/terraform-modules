locals {
  rendered_name = var.name != null && var.name != "" ? "${var.application}-${var.environment}-${var.name}" : "${var.application}-${var.environment}"
  name_prefix   = local.rendered_name

  tags = merge(
    {
      Application = var.application
      Environment = var.environment
      Name        = local.rendered_name
    },
    var.tags
  )

  eks_addons = {
    snapshot-controller = {
      addon_version = var.addon_versions.snapshot_controller
    }
    eks-pod-identity-agent = {
      addon_version = var.addon_versions.pod_identity_agent
    }
    aws-ebs-csi-driver = {
      addon_version = var.addon_versions.ebs_csi_driver
      configuration_values = jsonencode({
        controller = {
          replicaCount = 1
        }
      })
    }
    vpc-cni = {
      addon_version = var.addon_versions.vpc_cni
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
          WARM_IP_TARGET           = "5"
        }
      })
    }
    coredns = {
      addon_version = var.addon_versions.coredns
      configuration_values = jsonencode({
        replicaCount = 2
      })
    }
    kube-proxy = {
      addon_version = var.addon_versions.kube_proxy
    }
    aws-efs-csi-driver = {
      addon_version = var.addon_versions.efs_csi_driver
      configuration_values = jsonencode({
        controller = {
          replicaCount = 1
        }
      })
    }
  }
}
