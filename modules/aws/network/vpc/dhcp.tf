resource "aws_vpc_dhcp_options" "this" {
  count = lookup(var.dhcp_options, "enabled", false) ? 1 : 0

  domain_name          = lookup(var.dhcp_options, "domain_name", null)
  domain_name_servers  = lookup(var.dhcp_options, "domain_name_servers", ["AmazonProvidedDNS"])
  ntp_servers          = lookup(var.dhcp_options, "ntp_servers", [])
  netbios_name_servers = lookup(var.dhcp_options, "netbios_name_servers", [])
  netbios_node_type    = lookup(var.dhcp_options, "netbios_node_type", null)

  tags = merge(local.tags, {
    Name = "${local.rendered_name}-dhcp"
  })
}

resource "aws_vpc_dhcp_options_association" "this" {
  count = lookup(var.dhcp_options, "enabled", false) ? 1 : 0

  vpc_id          = aws_vpc.main.id
  dhcp_options_id = aws_vpc_dhcp_options.this[0].id
}
