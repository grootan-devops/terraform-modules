locals {
  default_public_nacl_rules = [
    { rule_no = 100, egress = false, protocol = "-1", action = "allow", cidr_block = aws_vpc.main.cidr_block, from_port = 0, to_port = 0 },
    { rule_no = 110, egress = false, protocol = "tcp", action = "allow", cidr_block = "0.0.0.0/0", from_port = 22, to_port = 22 },
    { rule_no = 112, egress = false, protocol = "tcp", action = "allow", cidr_block = "0.0.0.0/0", from_port = 80, to_port = 80 },
    { rule_no = 113, egress = false, protocol = "tcp", action = "allow", cidr_block = "0.0.0.0/0", from_port = 443, to_port = 443 },
    { rule_no = 116, egress = false, protocol = "tcp", action = "allow", cidr_block = "0.0.0.0/0", from_port = 53, to_port = 53 },
    { rule_no = 117, egress = false, protocol = "udp", action = "allow", cidr_block = "0.0.0.0/0", from_port = 53, to_port = 53 },
    { rule_no = 200, egress = false, protocol = "tcp", action = "allow", cidr_block = "0.0.0.0/0", from_port = 1024, to_port = 65535 },
    { rule_no = 100, egress = true, protocol = "-1", action = "allow", cidr_block = "0.0.0.0/0", from_port = 0, to_port = 0 },
  ]
  default_private_nacl_rules = local.default_public_nacl_rules
  default_intra_nacl_rules = [
    { rule_no = 100, egress = false, protocol = "-1", action = "allow", cidr_block = aws_vpc.main.cidr_block, from_port = 0, to_port = 0 },
    { rule_no = 100, egress = true, protocol = "-1", action = "allow", cidr_block = aws_vpc.main.cidr_block, from_port = 0, to_port = 0 },
  ]

  public_nacl_rules       = { for r in concat(local.default_public_nacl_rules, lookup(var.nacl, "public", [])) : "${lookup(r, "egress", false) ? "egress" : "ingress"}-${r.rule_no}" => r... }
  public_nacl_rules_final = { for k, v in local.public_nacl_rules : k => v[length(v) - 1] }

  private_nacl_rules       = { for r in concat(local.default_private_nacl_rules, lookup(var.nacl, "private", [])) : "${lookup(r, "egress", false) ? "egress" : "ingress"}-${r.rule_no}" => r... }
  private_nacl_rules_final = { for k, v in local.private_nacl_rules : k => v[length(v) - 1] }

  intra_nacl_rules       = { for r in concat(local.default_intra_nacl_rules, lookup(var.nacl, "intra", [])) : "${lookup(r, "egress", false) ? "egress" : "ingress"}-${r.rule_no}" => r... }
  intra_nacl_rules_final = { for k, v in local.intra_nacl_rules : k => v[length(v) - 1] }
}

resource "aws_default_network_acl" "default" {
  default_network_acl_id = aws_vpc.main.default_network_acl_id

  tags = merge(local.tags, {
    Name = "${local.rendered_name}-default-deny-all"
  })
}

resource "aws_network_acl" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${local.rendered_name}-public"
    Tier = "public"
  })
}

resource "aws_network_acl_rule" "public" {
  for_each = local.public_nacl_rules_final

  network_acl_id = aws_network_acl.public.id

  rule_number     = each.value.rule_no
  egress          = lookup(each.value, "egress", false)
  protocol        = each.value.protocol
  rule_action     = each.value.action
  cidr_block      = lookup(each.value, "cidr_block", null)
  ipv6_cidr_block = lookup(each.value, "ipv6_cidr_block", null)
  from_port       = each.value.from_port
  to_port         = each.value.to_port
  icmp_type       = lookup(each.value, "icmp_type", null)
  icmp_code       = lookup(each.value, "icmp_code", null)
}

resource "aws_network_acl_association" "public" {
  for_each = aws_subnet.public

  network_acl_id = aws_network_acl.public.id
  subnet_id      = each.value.id
}

resource "aws_network_acl" "private" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${local.rendered_name}-private"
    Tier = "private"
  })
}

resource "aws_network_acl_rule" "private" {
  for_each = local.private_nacl_rules_final

  network_acl_id = aws_network_acl.private.id

  rule_number     = each.value.rule_no
  egress          = lookup(each.value, "egress", false)
  protocol        = each.value.protocol
  rule_action     = each.value.action
  cidr_block      = lookup(each.value, "cidr_block", null)
  ipv6_cidr_block = lookup(each.value, "ipv6_cidr_block", null)
  from_port       = each.value.from_port
  to_port         = each.value.to_port
  icmp_type       = lookup(each.value, "icmp_type", null)
  icmp_code       = lookup(each.value, "icmp_code", null)
}

resource "aws_network_acl_association" "private" {
  for_each = aws_subnet.private

  network_acl_id = aws_network_acl.private.id
  subnet_id      = each.value.id
}

resource "aws_network_acl" "intra" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${local.rendered_name}-intra"
    Tier = "intra"
  })
}

resource "aws_network_acl_rule" "intra" {
  for_each = local.intra_nacl_rules_final

  network_acl_id = aws_network_acl.intra.id

  rule_number     = each.value.rule_no
  egress          = lookup(each.value, "egress", false)
  protocol        = each.value.protocol
  rule_action     = each.value.action
  cidr_block      = lookup(each.value, "cidr_block", null)
  ipv6_cidr_block = lookup(each.value, "ipv6_cidr_block", null)
  from_port       = each.value.from_port
  to_port         = each.value.to_port
  icmp_type       = lookup(each.value, "icmp_type", null)
  icmp_code       = lookup(each.value, "icmp_code", null)
}

resource "aws_network_acl_association" "intra" {
  for_each = aws_subnet.intra

  network_acl_id = aws_network_acl.intra.id
  subnet_id      = each.value.id
}
