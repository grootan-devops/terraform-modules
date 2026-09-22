resource "aws_eks_addon" "this" {
  for_each = var.enable_default_addons ? local.eks_addons : {}

  cluster_name = aws_eks_cluster.this.name
  addon_name   = each.key

  addon_version               = each.value.addon_version
  configuration_values        = try(each.value.configuration_values, null)
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = local.tags
}

resource "aws_eks_pod_identity_association" "vpc_cni" {
  count           = var.enable_default_addons ? 1 : 0
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "aws-node"
  role_arn        = aws_iam_role.eks_vpc_cni.arn
}

resource "aws_eks_pod_identity_association" "ebs_csi" {
  count           = var.enable_default_addons ? 1 : 0
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi.arn
}

resource "aws_eks_pod_identity_association" "efs_csi" {
  count           = var.enable_default_addons ? 1 : 0
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "efs-csi-controller-sa"
  role_arn        = aws_iam_role.efs_csi.arn
}

resource "aws_eks_pod_identity_association" "efs_csi_node" {
  count           = var.enable_default_addons ? 1 : 0
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "efs-csi-node-sa"
  role_arn        = aws_iam_role.efs_csi_node.arn
}

resource "aws_eks_pod_identity_association" "aws_lb_controller" {
  count           = var.enable_lb_controller_role ? 1 : 0
  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.aws_lb_controller[0].arn
}
