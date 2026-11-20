module "endpoint_security_group" {
  source = "../../network/security-group"
  count  = length(local.interface_endpoints) > 0 ? 1 : 0

  application = var.application
  environment = var.environment
  name        = var.name
  purpose     = "endpoints"
  tags        = var.tags
  vpc_id      = aws_vpc.this.id
  description = "${local.base} interface endpoints"
  ingress_rules = {
    vpc = { description = "HTTPS from the VPC", ip_protocol = "tcp", from_port = 443, to_port = 443, cidr_ipv4 = var.cidr_block }
  }
}

module "endpoint_policy" {
  source   = "../../core/policy-document"
  for_each = local.endpoint_policies

  default_resources = ["*"]
  allow_public      = true
  statements        = [for s in each.value.policy_statements : merge(s, { principals = length(s.principals) > 0 ? s.principals : { AWS = ["*"] } })]
}

resource "aws_vpc_endpoint" "this" {
  for_each = var.vpc_endpoints

  vpc_id              = aws_vpc.this.id
  service_name        = coalesce(each.value.service_name, "com.amazonaws.${module.naming.region}.${each.key}")
  vpc_endpoint_type   = each.value.type
  route_table_ids     = each.value.type == "Gateway" ? local.gateway_route_table_ids : null
  subnet_ids          = each.value.type == "Interface" ? [for k, s in local.subnets : aws_subnet.this[k].id if s.tier == each.value.subnet_tier] : null
  security_group_ids  = each.value.type == "Interface" ? module.endpoint_security_group[*].id : null
  private_dns_enabled = each.value.type == "Interface" ? each.value.private_dns_enabled : null
  policy              = try(module.endpoint_policy[each.key].json, null)

  tags = merge(module.naming.tags, { Name = "${local.base}-${each.key}" })
}
