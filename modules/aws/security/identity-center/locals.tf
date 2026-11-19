locals {
  instance_arn      = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]

  managed_policy_attachments = { for item in flatten([
    for ps, p in var.permission_sets : [
      for arn in distinct(p.managed_policy_arns) : { key = "${ps}/${arn}", permission_set = ps, arn = arn }
    ]
  ]) : item.key => item }

  customer_managed_policy_attachments = { for item in flatten([
    for ps, p in var.permission_sets : [
      for c in p.customer_managed_policies : { key = "${ps}/${c.path}${c.name}", permission_set = ps, name = c.name, path = c.path }
    ]
  ]) : item.key => item }

  inline_policies = { for ps, p in var.permission_sets : ps => p.policy_statements if length(p.policy_statements) > 0 }

  permissions_boundaries = { for ps, p in var.permission_sets : ps => p.permissions_boundary if p.permissions_boundary.enabled }

  group_memberships = { for item in flatten([
    for g, group in var.groups : [
      for member in distinct(group.member_ids) : { key = "${g}/${member}", group = g, member_id = member }
    ]
  ]) : item.key => item }

  assignments = { for item in flatten([
    for k, a in var.account_assignments : [
      for account in distinct(a.account_ids) : {
        key            = "${k}/${account}"
        permission_set = a.permission_set
        principal_type = a.principal_type
        principal_id   = a.principal_id
        group          = a.group
        account_id     = account
      }
    ]
  ]) : item.key => item }
}
