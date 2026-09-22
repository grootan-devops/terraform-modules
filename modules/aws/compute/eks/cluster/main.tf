resource "aws_eks_cluster" "this" {
  name = local.name_prefix

  version                       = var.cluster_version
  role_arn                      = aws_iam_role.eks_cluster.arn
  deletion_protection           = var.deletion_protection
  bootstrap_self_managed_addons = false
  enabled_cluster_log_types     = var.log_types

  vpc_config {
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.endpoint_public_access ? var.public_access_cidrs : []
    subnet_ids              = var.subnet_ids
    security_group_ids      = var.security_group_ids
  }

  access_config {
    authentication_mode                         = var.authentication_mode
    bootstrap_cluster_creator_admin_permissions = var.bootstrap_cluster_creator_admin_permissions
  }

  encryption_config {
    provider {
      key_arn = var.kms_key_arn
    }
    resources = ["secrets"]
  }

  upgrade_policy {
    support_type = var.upgrade_support_type
  }

  tags = local.tags

  depends_on = [
    aws_cloudwatch_log_group.eks_cluster,
    aws_iam_role_policy_attachment.eks_cluster
  ]
}
