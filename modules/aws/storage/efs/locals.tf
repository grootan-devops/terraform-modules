locals {
  name        = module.naming.names.file_system
  kms_key_arn = module.encryption.key_arn

  transitions = { for k, v in var.lifecycle_policy : k => v if v != "NONE" }

  security_group_ids = concat(var.security_group.create ? [module.security_group[0].id] : [], var.security_group.additional_security_group_ids)

  ingress_rules = merge(
    { for i, sg in var.security_group.ingress_security_group_ids : "sg-${i}" => { description = "NFS from a security group", from_port = 2049, to_port = 2049, referenced_security_group_id = sg } },
    { for i, cidr in var.security_group.ingress_cidr_blocks : "cidr-${i}" => { description = "NFS from ${cidr}", from_port = 2049, to_port = 2049, cidr_ipv4 = strcontains(cidr, ":") ? null : cidr, cidr_ipv6 = strcontains(cidr, ":") ? cidr : null } },
    { for i, pl in var.security_group.ingress_prefix_list_ids : "pl-${i}" => { description = "NFS from a prefix list", from_port = 2049, to_port = 2049, prefix_list_id = pl } }
  )

  client_actions = concat(
    ["elasticfilesystem:ClientMount"],
    var.client_access.read_only ? [] : ["elasticfilesystem:ClientWrite"],
    var.client_access.root_access ? ["elasticfilesystem:ClientRootAccess"] : []
  )

  guard_statements = [
    {
      sid        = "DenyInsecureTransport"
      effect     = "Deny"
      actions    = ["*"]
      principals = { AWS = ["*"] }
      conditions = [{ test = "Bool", variable = "aws:SecureTransport", values = ["false"] }]
    },
    {
      sid        = "AllowClientAccessThroughMountTargets"
      effect     = "Allow"
      actions    = local.client_actions
      principals = { AWS = length(var.client_access.principal_arns) > 0 ? var.client_access.principal_arns : ["*"] }
      conditions = [{ test = "Bool", variable = "elasticfilesystem:AccessedViaMountTarget", values = ["true"] }]
    }
  ]
}
