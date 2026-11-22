locals {
  identifier          = module.naming.names.instance
  kms_key_arn         = module.encryption.key_arn
  family              = "postgres${split(".", var.engine_version)[0]}"
  arn_prefix          = "arn:${module.naming.partition}"
  db_arn              = "${local.arn_prefix}:rds:${module.naming.region}:${module.naming.account_id}:db:${local.identifier}"
  log_group_prefix    = "/aws/rds/instance/${local.identifier}"
  log_group_names     = { for e in var.cloudwatch_logs.exports : e => "${local.log_group_prefix}/${e}" }
  monitoring_role_arn = var.iam_role.create ? module.monitoring_role[0].arn : var.iam_role.arn
  secret_kms_key_arn  = var.credential.manage_master_user_password ? try(coalesce(var.credential.kms_key_arn, local.kms_key_arn), null) : null

  via_service_statement = {
    actions    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:CreateGrant", "kms:ListGrants", "kms:DescribeKey"]
    principals = { AWS = ["*"] }
  }

  kms_statement_candidates = [
    {
      when = true
      statement = merge(local.via_service_statement, {
        sid = "AllowRDS"
        conditions = [
          { test = "StringEquals", variable = "kms:CallerAccount", values = [module.naming.account_id] },
          { test = "StringEquals", variable = "kms:ViaService", values = ["rds.${module.naming.region}.${module.naming.dns_suffix}"] }
        ]
      })
    },
    {
      when = var.credential.manage_master_user_password
      statement = merge(local.via_service_statement, {
        sid = "AllowSecretsManager"
        conditions = [
          { test = "StringEquals", variable = "kms:CallerAccount", values = [module.naming.account_id] },
          { test = "StringEquals", variable = "kms:ViaService", values = ["secretsmanager.${module.naming.region}.${module.naming.dns_suffix}"] }
        ]
      })
    },
    {
      when = true
      statement = {
        sid        = "AllowCloudWatchLogs"
        actions    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
        principals = { Service = ["logs.${module.naming.region}.${module.naming.dns_suffix}"] }
        conditions = [{
          test     = "ArnLike"
          variable = "kms:EncryptionContext:aws:logs:arn"
          values   = ["${local.arn_prefix}:logs:${module.naming.region}:${module.naming.account_id}:log-group:${local.log_group_prefix}/*"]
        }]
      }
    }
  ]

  kms_service_statements = [for c in local.kms_statement_candidates : c.statement if c.when]

  ingress_rules = merge(
    { for i, sg in var.security_group.ingress_security_group_ids : "sg-${i}" => { description = "PostgreSQL from a security group", from_port = var.port, to_port = var.port, referenced_security_group_id = sg } },
    { for i, cidr in var.security_group.ingress_cidr_blocks : "cidr-${i}" => { description = "PostgreSQL from ${cidr}", from_port = var.port, to_port = var.port, cidr_ipv4 = strcontains(cidr, ":") ? null : cidr, cidr_ipv6 = strcontains(cidr, ":") ? cidr : null } },
    { for i, pl in var.security_group.ingress_prefix_list_ids : "pl-${i}" => { description = "PostgreSQL from a prefix list", from_port = var.port, to_port = var.port, prefix_list_id = pl } }
  )

  egress_rules = { for i, cidr in var.security_group.egress_cidr_blocks : "cidr-${i}" => { description = "Outbound to ${cidr}", ip_protocol = "-1", cidr_ipv4 = strcontains(cidr, ":") ? null : cidr, cidr_ipv6 = strcontains(cidr, ":") ? cidr : null } }

  security_group_ids = concat(var.security_group.create ? [module.security_group[0].id] : [], var.security_group.additional_security_group_ids)

  event_subscriptions = var.event_subscription.enabled ? {
    instance = {
      source_type = "db-instance"
      source_id   = aws_db_instance.this.identifier
      categories  = var.event_subscription.event_categories
    }
    parameter-group = {
      source_type = "db-parameter-group"
      source_id   = aws_db_parameter_group.this.name
      categories  = ["configuration change"]
    }
  } : {}
}
