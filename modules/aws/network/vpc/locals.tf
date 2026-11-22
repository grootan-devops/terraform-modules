locals {
  base     = module.naming.name
  az_count = length(var.azs) > 0 ? length(var.azs) : var.az_count
  azs      = length(var.azs) > 0 ? var.azs : slice(data.aws_availability_zones.available[0].names, 0, var.az_count)
  indexes  = range(local.az_count)

  tier_inputs = {
    public  = var.public_subnets
    private = var.private_subnets
    intra   = var.intra_subnets
  }

  tiers = [for t in ["public", "private", "intra"] : t if local.tier_inputs[t].enabled]

  subnets = merge([
    for t in local.tiers : {
      for i in local.indexes : "${t}-${i}" => {
        tier        = t
        index       = i
        az          = local.azs[i]
        route_table = t == "private" ? "private-${i}" : t
        cidr = length(local.tier_inputs[t].cidrs) > 0 ? local.tier_inputs[t].cidrs[i] : (
          t == "private" ? cidrsubnet(var.cidr_block, 4, i) : cidrsubnet(cidrsubnet(var.cidr_block, 4, t == "public" ? 15 : 14), 4, i)
        )
      }
    }
  ]...)

  route_tables = merge(
    var.public_subnets.enabled ? { public = "public" } : {},
    var.private_subnets.enabled ? { for i in local.indexes : "private-${i}" => "private" } : {},
    var.intra_subnets.enabled ? { intra = "intra" } : {}
  )

  nat_keys = var.nat.mode == "per_az" ? [for i in local.indexes : tostring(i)] : (var.nat.mode == "single" ? ["0"] : [])

  default_nacl_rules = {
    public = [
      { rule_number = 100, egress = false, protocol = "-1", cidr_block = var.cidr_block, from_port = 0, to_port = 0 },
      { rule_number = 110, egress = false, protocol = "tcp", cidr_block = "0.0.0.0/0", from_port = 80, to_port = 80 },
      { rule_number = 120, egress = false, protocol = "tcp", cidr_block = "0.0.0.0/0", from_port = 443, to_port = 443 },
      { rule_number = 130, egress = false, protocol = "tcp", cidr_block = "0.0.0.0/0", from_port = 1024, to_port = 3388 },
      { rule_number = 140, egress = false, protocol = "tcp", cidr_block = "0.0.0.0/0", from_port = 3390, to_port = 65535 },
      { rule_number = 150, egress = false, protocol = "udp", cidr_block = "0.0.0.0/0", from_port = 1024, to_port = 3388 },
      { rule_number = 160, egress = false, protocol = "udp", cidr_block = "0.0.0.0/0", from_port = 3390, to_port = 65535 },
      { rule_number = 100, egress = true, protocol = "-1", cidr_block = "0.0.0.0/0", from_port = 0, to_port = 0 },
    ]
    private = [
      { rule_number = 100, egress = false, protocol = "-1", cidr_block = var.cidr_block, from_port = 0, to_port = 0 },
      { rule_number = 130, egress = false, protocol = "tcp", cidr_block = "0.0.0.0/0", from_port = 1024, to_port = 3388 },
      { rule_number = 140, egress = false, protocol = "tcp", cidr_block = "0.0.0.0/0", from_port = 3390, to_port = 65535 },
      { rule_number = 150, egress = false, protocol = "udp", cidr_block = "0.0.0.0/0", from_port = 1024, to_port = 3388 },
      { rule_number = 160, egress = false, protocol = "udp", cidr_block = "0.0.0.0/0", from_port = 3390, to_port = 65535 },
      { rule_number = 100, egress = true, protocol = "-1", cidr_block = "0.0.0.0/0", from_port = 0, to_port = 0 },
    ]
    intra = [
      { rule_number = 100, egress = false, protocol = "-1", cidr_block = var.cidr_block, from_port = 0, to_port = 0 },
      { rule_number = 100, egress = true, protocol = "-1", cidr_block = var.cidr_block, from_port = 0, to_port = 0 },
    ]
  }

  nacl_rules = merge(
    {
      for r in flatten([
        for t in local.tiers : [
          for d in local.default_nacl_rules[t] : {
            tier            = t
            rule_number     = d.rule_number
            egress          = d.egress
            protocol        = d.protocol
            action          = "allow"
            cidr_block      = d.cidr_block
            ipv6_cidr_block = null
            from_port       = d.from_port
            to_port         = d.to_port
            icmp_type       = null
            icmp_code       = null
          }
        ]
      ]) : "${r.tier}-${r.egress ? "egress" : "ingress"}-${r.rule_number}" => r
    },
    { for r in values(var.nacl_rules) : "${r.tier}-${r.egress ? "egress" : "ingress"}-${r.rule_number}" => r if contains(local.tiers, r.tier) }
  )

  routes = merge([
    for k, r in var.routes : {
      for rt, tier in local.route_tables : "${k}-${rt}" => merge(r, { route_table = rt }) if contains(r.tiers, tier)
    }
  ]...)

  flow_logs_to_cloudwatch = var.flow_logs.enabled && var.flow_logs.destination == "cloudwatch"
  log_group_name          = "/aws/vpc/${local.base}/flow-logs"
  log_group_arn           = "arn:${module.naming.partition}:logs:${module.naming.region}:${module.naming.account_id}:log-group:${local.log_group_name}"
  kms_key_arn             = module.encryption.key_arn
  flow_log_role_arn       = var.iam_role.create ? one(module.role[*].arn) : var.iam_role.arn

  kms_service_statements = [{
    sid        = "AllowCloudWatchLogs"
    actions    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    principals = { Service = ["logs.${module.naming.region}.${module.naming.dns_suffix}"] }
    conditions = [{ test = "ArnLike", variable = "kms:EncryptionContext:aws:logs:arn", values = [local.log_group_arn] }]
  }]

  flow_log_statements = [
    {
      Sid      = "WriteFlowLogs"
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
      Resource = ["${local.log_group_arn}:*"]
    },
    {
      Sid      = "DescribeLogGroups"
      Effect   = "Allow"
      Action   = ["logs:DescribeLogGroups"]
      Resource = ["arn:${module.naming.partition}:logs:${module.naming.region}:${module.naming.account_id}:log-group:*"]
    }
  ]

  interface_endpoints = { for k, e in var.vpc_endpoints : k => e if e.type == "Interface" }
  endpoint_policies   = { for k, e in var.vpc_endpoints : k => e if length(e.policy_statements) > 0 }
  gateway_route_table_ids = [
    for rt, tier in local.route_tables : aws_route_table.this[rt].id if tier != "public"
  ]
}
