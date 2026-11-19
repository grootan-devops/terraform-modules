data "aws_ssoadmin_instances" "this" {
  lifecycle {
    postcondition {
      condition     = length(self.arns) > 0
      error_message = "No IAM Identity Center instance in this Region."
    }
  }
}

module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  tags        = var.tags
  names = merge(
    { for k in keys(var.permission_sets) : "ps-${k}" => { suffix = k, max_length = 32 } },
    { for k in keys(var.groups) : "group-${k}" => { suffix = k, max_length = 1024 } },
  )
}

module "inline_policy" {
  source   = "../../core/policy-document"
  for_each = local.inline_policies

  statements = each.value
}

resource "aws_ssoadmin_permission_set" "this" {
  for_each = var.permission_sets

  instance_arn     = local.instance_arn
  name             = module.naming.names["ps-${each.key}"]
  description      = coalesce(each.value.description, "${module.naming.names["ps-${each.key}"]} permission set")
  session_duration = each.value.session_duration
  relay_state      = each.value.relay_state

  tags = merge(module.naming.tags, { Name = module.naming.names["ps-${each.key}"] })
}

resource "aws_ssoadmin_managed_policy_attachment" "this" {
  for_each = local.managed_policy_attachments

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set].arn
  managed_policy_arn = each.value.arn
}

resource "aws_ssoadmin_customer_managed_policy_attachment" "this" {
  for_each = local.customer_managed_policy_attachments

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set].arn

  customer_managed_policy_reference {
    name = each.value.name
    path = each.value.path
  }
}

resource "aws_ssoadmin_managed_policy_attachments_exclusive" "this" {
  for_each = var.permission_sets

  instance_arn        = local.instance_arn
  permission_set_arn  = aws_ssoadmin_permission_set.this[each.key].arn
  managed_policy_arns = [for k, a in aws_ssoadmin_managed_policy_attachment.this : a.managed_policy_arn if local.managed_policy_attachments[k].permission_set == each.key]
}

resource "aws_ssoadmin_customer_managed_policy_attachments_exclusive" "this" {
  for_each = var.permission_sets

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.key].arn

  dynamic "customer_managed_policy_reference" {
    for_each = { for k, a in aws_ssoadmin_customer_managed_policy_attachment.this : k => a.customer_managed_policy_reference[0] if local.customer_managed_policy_attachments[k].permission_set == each.key }

    content {
      name = customer_managed_policy_reference.value.name
      path = customer_managed_policy_reference.value.path
    }
  }
}

resource "aws_ssoadmin_permission_set_inline_policy" "this" {
  for_each = local.inline_policies

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.key].arn
  inline_policy      = module.inline_policy[each.key].json
}

resource "aws_ssoadmin_permissions_boundary_attachment" "this" {
  for_each = local.permissions_boundaries

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.key].arn

  permissions_boundary {
    managed_policy_arn = each.value.managed_policy_arn

    dynamic "customer_managed_policy_reference" {
      for_each = each.value.customer_managed_policy == null ? [] : [each.value.customer_managed_policy]

      content {
        name = customer_managed_policy_reference.value.name
        path = customer_managed_policy_reference.value.path
      }
    }
  }
}

resource "aws_identitystore_group" "this" {
  for_each = var.groups

  identity_store_id = local.identity_store_id
  display_name      = module.naming.names["group-${each.key}"]
  description       = each.value.description
}

resource "aws_identitystore_group_membership" "this" {
  for_each = local.group_memberships

  identity_store_id = local.identity_store_id
  group_id          = aws_identitystore_group.this[each.value.group].group_id
  member_id         = each.value.member_id
}

resource "aws_ssoadmin_account_assignment" "this" {
  for_each = local.assignments

  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set].arn
  principal_type     = each.value.principal_type
  principal_id       = each.value.group == null ? each.value.principal_id : aws_identitystore_group.this[each.value.group].group_id
  target_type        = "AWS_ACCOUNT"
  target_id          = each.value.account_id

  depends_on = [
    aws_ssoadmin_managed_policy_attachment.this,
    aws_ssoadmin_customer_managed_policy_attachment.this,
    aws_ssoadmin_managed_policy_attachments_exclusive.this,
    aws_ssoadmin_customer_managed_policy_attachments_exclusive.this,
    aws_ssoadmin_permission_set_inline_policy.this,
    aws_ssoadmin_permissions_boundary_attachment.this,
  ]
}
