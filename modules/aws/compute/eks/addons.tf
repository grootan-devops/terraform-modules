resource "aws_eks_addon" "before_compute" {
  for_each = local.addons_before_compute

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  addon_version               = try(var.addons.versions[each.key], null)
  configuration_values        = try(local.addon_configuration[each.key], null)
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  dynamic "pod_identity_association" {
    for_each = try(local.addon_associations[each.key], {})
    content {
      service_account = pod_identity_association.key
      role_arn        = module.addon_role[pod_identity_association.value].arn
    }
  }

  tags = merge(module.naming.tags, { Name = "${local.cluster_name}-${each.key}" })
}

resource "aws_eks_addon" "this" {
  for_each = local.addons_after_compute

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  addon_version               = try(var.addons.versions[each.key], null)
  configuration_values        = try(local.addon_configuration[each.key], null)
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  dynamic "pod_identity_association" {
    for_each = try(local.addon_associations[each.key], {})
    content {
      service_account = pod_identity_association.key
      role_arn        = module.addon_role[pod_identity_association.value].arn
    }
  }

  tags = merge(module.naming.tags, { Name = "${local.cluster_name}-${each.key}" })

  depends_on = [aws_eks_node_group.this, aws_eks_fargate_profile.this]
}

resource "aws_eks_pod_identity_association" "lb_controller" {
  count = local.addons_enabled ? 1 : 0

  cluster_name    = aws_eks_cluster.this.name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = module.lb_controller_role[0].arn

  tags = merge(module.naming.tags, { Name = "${local.cluster_name}-lb-controller" })
}

resource "aws_eks_pod_identity_association" "this" {
  for_each = var.pod_identities

  cluster_name    = aws_eks_cluster.this.name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = contains(keys(local.workload_roles), each.key) ? module.workload_role[each.key].arn : each.value.role_arn

  tags = merge(module.naming.tags, { Name = "${local.cluster_name}-${each.key}" })
}
