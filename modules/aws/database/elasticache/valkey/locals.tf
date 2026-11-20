locals {
  replication_group_id = module.naming.names.replication_group
  kms_key_arn          = module.encryption.key_arn
  family               = "valkey${split(".", var.engine_version)[0]}"
  multi_az             = var.num_cache_clusters > 1

  log_types       = var.cloudwatch_logs.enabled ? toset(var.cloudwatch_logs.log_types) : toset([])
  log_group_names = { for t in local.log_types : t => "/aws/elasticache/${local.replication_group_id}/${t}" }

  kms_statement_candidates = [
    {
      when = true
      statement = {
        sid        = "AllowElastiCache"
        actions    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:CreateGrant", "kms:ListGrants", "kms:DescribeKey"]
        principals = { AWS = ["*"] }
        conditions = [
          { test = "StringEquals", variable = "kms:CallerAccount", values = [module.naming.account_id] },
          { test = "StringEquals", variable = "kms:ViaService", values = ["elasticache.${module.naming.region}.${module.naming.dns_suffix}"] }
        ]
      }
    },
    {
      when = var.cloudwatch_logs.enabled
      statement = {
        sid        = "AllowCloudWatchLogs"
        actions    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
        principals = { Service = ["logs.${module.naming.region}.${module.naming.dns_suffix}"] }
        conditions = [{
          test     = "ArnLike"
          variable = "kms:EncryptionContext:aws:logs:arn"
          values   = ["arn:${module.naming.partition}:logs:${module.naming.region}:${module.naming.account_id}:log-group:/aws/elasticache/${local.replication_group_id}/*"]
        }]
      }
    }
  ]

  kms_service_statements = [for c in local.kms_statement_candidates : c.statement if c.when]

  ingress_rules = merge(
    { for i, sg in var.security_group.ingress_security_group_ids : "sg-${i}" => { description = "Valkey from a security group", from_port = var.port, to_port = var.port, referenced_security_group_id = sg } },
    { for i, cidr in var.security_group.ingress_cidr_blocks : "cidr-${i}" => { description = "Valkey from ${cidr}", from_port = var.port, to_port = var.port, cidr_ipv4 = strcontains(cidr, ":") ? null : cidr, cidr_ipv6 = strcontains(cidr, ":") ? cidr : null } },
    { for i, pl in var.security_group.ingress_prefix_list_ids : "pl-${i}" => { description = "Valkey from a prefix list", from_port = var.port, to_port = var.port, prefix_list_id = pl } }
  )

  security_group_ids = concat(var.security_group.create ? [module.security_group[0].id] : [], var.security_group.additional_security_group_ids)
}
