module "cluster_role" {
  source = "../../security/iam-role"

  application              = var.application
  environment              = var.environment
  name                     = var.name
  purpose                  = "cluster"
  tags                     = var.tags
  path                     = var.iam_role.path
  permissions_boundary_arn = var.iam_role.permissions_boundary_arn
  managed_policy_arns      = ["${local.arn_prefix}:iam::aws:policy/AmazonEKSClusterPolicy"]
  trust = {
    services = ["eks.${local.dns_suffix}"]
    conditions = [
      { test = "StringEquals", variable = "aws:SourceAccount", values = [local.account_id] },
      { test = "ArnLike", variable = "aws:SourceArn", values = [local.cluster_arn] }
    ]
  }
}

module "node_role" {
  source = "../../security/iam-role"
  count  = var.iam_role.create && local.has_nodes ? 1 : 0

  application              = var.application
  environment              = var.environment
  name                     = var.name
  purpose                  = "node"
  tags                     = var.tags
  role_name                = var.iam_role.name
  path                     = var.iam_role.path
  permissions_boundary_arn = var.iam_role.permissions_boundary_arn
  managed_policy_arns      = local.node_managed_policy_arns
  policy_statements        = var.iam_role.policy_statements
  trust = {
    services = ["ec2.${local.dns_suffix}"]
  }
}

module "fargate_role" {
  source = "../../security/iam-role"
  count  = length(var.fargate_profiles) > 0 ? 1 : 0

  application              = var.application
  environment              = var.environment
  name                     = var.name
  purpose                  = "fargate"
  tags                     = var.tags
  path                     = var.iam_role.path
  permissions_boundary_arn = var.iam_role.permissions_boundary_arn
  managed_policy_arns      = ["${local.arn_prefix}:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"]
  trust = {
    services   = ["eks-fargate-pods.${local.dns_suffix}"]
    conditions = [{ test = "ArnLike", variable = "aws:SourceArn", values = ["${local.arn_prefix}:eks:${local.region}:${local.account_id}:fargateprofile/${local.cluster_name}/*"] }]
  }
}

module "addon_role" {
  source   = "../../security/iam-role"
  for_each = local.addons_enabled ? local.addon_roles : {}

  application              = var.application
  environment              = var.environment
  name                     = var.name
  purpose                  = each.key
  tags                     = var.tags
  path                     = var.iam_role.path
  permissions_boundary_arn = var.iam_role.permissions_boundary_arn
  managed_policy_arns      = each.value
  policy_documents         = contains(keys(local.addon_role_documents), each.key) ? [local.addon_role_documents[each.key]] : []
  trust = {
    services = ["pods.eks.${local.dns_suffix}"]
    actions  = ["sts:AssumeRole", "sts:TagSession"]
  }
}

module "lb_controller_role" {
  source = "../../security/iam-role"
  count  = local.addons_enabled ? 1 : 0

  application              = var.application
  environment              = var.environment
  name                     = var.name
  purpose                  = "lb-controller"
  tags                     = var.tags
  path                     = var.iam_role.path
  permissions_boundary_arn = var.iam_role.permissions_boundary_arn
  policy_documents         = [local.lb_controller_policy]
  trust = {
    services = ["pods.eks.${local.dns_suffix}"]
    actions  = ["sts:AssumeRole", "sts:TagSession"]
  }
}

module "workload_role" {
  source   = "../../security/iam-role"
  for_each = local.workload_roles

  application              = var.application
  environment              = var.environment
  name                     = var.name
  purpose                  = "${each.key}-pod"
  tags                     = var.tags
  path                     = var.iam_role.path
  permissions_boundary_arn = var.iam_role.permissions_boundary_arn
  managed_policy_arns      = each.value.managed_policy_arns
  policy_statements        = each.value.policy_statements
  trust = {
    services = ["pods.eks.${local.dns_suffix}"]
    actions  = ["sts:AssumeRole", "sts:TagSession"]
  }
}
