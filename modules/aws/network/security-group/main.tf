module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags
  names = {
    group = { suffix = var.purpose, max_length = 248 }
  }
}

resource "aws_security_group" "this" {
  name_prefix = "${module.naming.names.group}-"
  description = coalesce(var.description, "${module.naming.names.group} security group")
  vpc_id      = var.vpc_id

  tags = merge(module.naming.tags, { Name = module.naming.names.group })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = var.ingress_rules

  security_group_id            = aws_security_group.this.id
  description                  = each.value.description
  ip_protocol                  = each.value.ip_protocol
  from_port                    = each.value.ip_protocol == "-1" ? null : each.value.from_port
  to_port                      = each.value.ip_protocol == "-1" ? null : each.value.to_port
  cidr_ipv4                    = each.value.cidr_ipv4
  cidr_ipv6                    = each.value.cidr_ipv6
  prefix_list_id               = each.value.prefix_list_id
  referenced_security_group_id = each.value.self ? aws_security_group.this.id : each.value.referenced_security_group_id

  tags = merge(module.naming.tags, { Name = "${module.naming.names.group}-${each.key}" })
}

resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = var.egress_rules

  security_group_id            = aws_security_group.this.id
  description                  = each.value.description
  ip_protocol                  = each.value.ip_protocol
  from_port                    = each.value.ip_protocol == "-1" ? null : each.value.from_port
  to_port                      = each.value.ip_protocol == "-1" ? null : each.value.to_port
  cidr_ipv4                    = each.value.cidr_ipv4
  cidr_ipv6                    = each.value.cidr_ipv6
  prefix_list_id               = each.value.prefix_list_id
  referenced_security_group_id = each.value.self ? aws_security_group.this.id : each.value.referenced_security_group_id

  tags = merge(module.naming.tags, { Name = "${module.naming.names.group}-${each.key}" })
}

resource "aws_vpc_security_group_rules_exclusive" "this" {
  security_group_id = aws_security_group.this.id
  ingress_rule_ids  = [for r in values(aws_vpc_security_group_ingress_rule.this) : r.security_group_rule_id]
  egress_rule_ids   = [for r in values(aws_vpc_security_group_egress_rule.this) : r.security_group_rule_id]
}
