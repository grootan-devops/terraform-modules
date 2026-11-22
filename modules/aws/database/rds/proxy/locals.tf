locals {
  proxy_name     = module.naming.names.proxy
  log_group_name = "/aws/rds/proxy/${local.proxy_name}"
  engine_port    = { POSTGRESQL = 5432, MYSQL = 3306, SQLSERVER = 1433 }[var.engine_family]
  target_port    = coalesce(var.target.port, local.engine_port)
  role_arn       = var.iam_role.create ? module.role[0].arn : var.iam_role.arn

  role_statement_candidates = [
    {
      when = length(var.auth) > 0
      statement = {
        Sid      = "ReadSecrets"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = [for a in var.auth : a.secret_arn]
      }
    },
    {
      when = length(var.auth) > 0
      statement = {
        Sid       = "DecryptSecrets"
        Effect    = "Allow"
        Action    = ["kms:Decrypt"]
        Resource  = ["*"]
        Condition = { StringEquals = { "kms:ViaService" = "secretsmanager.${module.naming.region}.${module.naming.dns_suffix}" } }
      }
    }
  ]

  role_statements = [for c in local.role_statement_candidates : c.statement if c.when]

  ingress_rules = merge(
    { for i, sg in var.security_group.ingress_security_group_ids : "sg-${i}" => { description = "Clients from a security group", from_port = local.engine_port, to_port = local.engine_port, referenced_security_group_id = sg } },
    { for i, cidr in var.security_group.ingress_cidr_blocks : "cidr-${i}" => { description = "Clients from ${cidr}", from_port = local.engine_port, to_port = local.engine_port, cidr_ipv4 = strcontains(cidr, ":") ? null : cidr, cidr_ipv6 = strcontains(cidr, ":") ? cidr : null } },
    { for i, pl in var.security_group.ingress_prefix_list_ids : "pl-${i}" => { description = "Clients from a prefix list", from_port = local.engine_port, to_port = local.engine_port, prefix_list_id = pl } }
  )

  egress_rules = merge(
    { for i, sg in var.target.security_group_ids : "db-${i}" => { description = "Target database", ip_protocol = "tcp", from_port = local.target_port, to_port = local.target_port, referenced_security_group_id = sg } },
    { for i, cidr in var.security_group.egress_cidr_blocks : "https-${i}" => { description = "AWS APIs over HTTPS to ${cidr}", ip_protocol = "tcp", from_port = 443, to_port = 443, cidr_ipv4 = strcontains(cidr, ":") ? null : cidr, cidr_ipv6 = strcontains(cidr, ":") ? cidr : null } }
  )

  security_group_ids = concat(var.security_group.create ? [module.security_group[0].id] : [], var.security_group.additional_security_group_ids)
}
