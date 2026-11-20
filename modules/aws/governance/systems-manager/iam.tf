module "dhmc_role" {
  source = "../../security/iam-role"
  count  = local.dhmc_enabled ? 1 : 0

  application              = var.application
  environment              = var.environment
  purpose                  = "ssm-dhmc"
  tags                     = var.tags
  path                     = "/service-role/"
  permissions_boundary_arn = var.permissions_boundary_arn
  managed_policy_arns      = local.dhmc_managed_policy_arns
  policy_documents         = local.dhmc_policy_documents
  trust = {
    services = ["ssm.amazonaws.com"]
  }
}

module "patch_administration_role" {
  source = "../../security/iam-role"
  count  = local.patching_enabled ? 1 : 0

  application              = var.application
  environment              = var.environment
  purpose                  = "ssm-patch-admin"
  tags                     = var.tags
  permissions_boundary_arn = var.permissions_boundary_arn
  policy_documents         = [local.patch_administration_policy_json]
  trust = {
    services = ["cloudformation.amazonaws.com"]
    conditions = [
      { test = "StringEquals", variable = "aws:SourceAccount", values = [local.account_id] },
      { test = "ArnLike", variable = "aws:SourceArn", values = ["arn:${local.partition}:cloudformation:*:${local.account_id}:stackset/AWS-QuickSetup-*"] },
    ]
  }
}

module "patch_execution_role" {
  source = "../../security/iam-role"
  count  = local.patching_enabled ? 1 : 0

  application              = var.application
  environment              = var.environment
  purpose                  = "ssm-patch-exec"
  tags                     = var.tags
  permissions_boundary_arn = var.permissions_boundary_arn
  managed_policy_arns      = ["arn:${local.partition}:iam::aws:policy/AWSQuickSetupPatchPolicyDeploymentRolePolicy"]
  trust = {
    aws_principals = [module.patch_administration_role[0].arn]
  }
}
