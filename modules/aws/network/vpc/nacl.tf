resource "aws_network_acl" "this" {
  for_each = toset(local.tiers)

  vpc_id = aws_vpc.this.id

  tags = merge(module.naming.tags, { Name = "${local.base}-${each.key}", Tier = each.key })
}

resource "aws_network_acl_rule" "this" {
  for_each = local.nacl_rules

  network_acl_id  = aws_network_acl.this[each.value.tier].id
  rule_number     = each.value.rule_number
  egress          = each.value.egress
  protocol        = each.value.protocol
  rule_action     = each.value.action
  cidr_block      = each.value.cidr_block
  ipv6_cidr_block = each.value.ipv6_cidr_block
  from_port       = each.value.from_port
  to_port         = each.value.to_port
  icmp_type       = each.value.icmp_type
  icmp_code       = each.value.icmp_code
}

resource "aws_network_acl_association" "this" {
  for_each = local.subnets

  network_acl_id = aws_network_acl.this[each.value.tier].id
  subnet_id      = aws_subnet.this[each.key].id
}
