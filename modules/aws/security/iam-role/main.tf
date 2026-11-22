module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags
  names = {
    role = {
      suffix     = var.purpose
      uniqueness = var.include_region_in_name ? "account" : "region"
      max_length = 64
    }
  }
}

module "policy" {
  source = "../../core/policy-document"

  statements       = var.policy_statements
  source_documents = var.policy_documents
}

resource "aws_iam_role" "this" {
  name                 = local.role_name
  path                 = var.path
  description          = coalesce(var.description, "${local.role_name} role")
  assume_role_policy   = local.trust_policy
  max_session_duration = var.max_session_duration
  permissions_boundary = var.permissions_boundary_arn

  tags = merge(module.naming.tags, { Name = local.role_name })
}

resource "aws_iam_role_policy" "this" {
  count = local.has_inline_policy ? 1 : 0

  name   = "inline"
  role   = aws_iam_role.this.id
  policy = module.policy.json
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = { for index, arn in var.managed_policy_arns : tostring(index) => arn }

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_role_policies_exclusive" "this" {
  role_name    = aws_iam_role.this.name
  policy_names = aws_iam_role_policy.this[*].name
}

resource "aws_iam_role_policy_attachments_exclusive" "this" {
  role_name   = aws_iam_role.this.name
  policy_arns = [for a in values(aws_iam_role_policy_attachment.this) : a.policy_arn]
}

resource "aws_iam_instance_profile" "this" {
  count = var.instance_profile.enabled ? 1 : 0

  name = local.role_name
  path = var.path
  role = aws_iam_role.this.name

  tags = merge(module.naming.tags, { Name = local.role_name })
}
