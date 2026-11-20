data "aws_availability_zones" "available" {
  count = length(var.azs) == 0 ? 1 : 0

  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags
}

module "encryption" {
  source = "../../core/encryption"

  application        = var.application
  environment        = var.environment
  name               = var.name
  purpose            = "vpc"
  tags               = var.tags
  kms                = var.kms
  service_statements = local.kms_service_statements
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  instance_tenancy     = "default"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = module.naming.tags
}

resource "aws_default_security_group" "this" {
  vpc_id  = aws_vpc.this.id
  ingress = []
  egress  = []

  tags = merge(module.naming.tags, { Name = "${local.base}-default" })
}

resource "aws_default_network_acl" "this" {
  default_network_acl_id = aws_vpc.this.default_network_acl_id

  tags = merge(module.naming.tags, { Name = "${local.base}-default" })
}

resource "aws_default_route_table" "this" {
  default_route_table_id = aws_vpc.this.default_route_table_id
  route                  = []

  tags = merge(module.naming.tags, { Name = "${local.base}-default" })
}

resource "aws_internet_gateway" "this" {
  count = var.public_subnets.enabled ? 1 : 0

  vpc_id = aws_vpc.this.id

  tags = module.naming.tags
}

resource "aws_subnet" "this" {
  for_each = local.subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false

  tags = merge(module.naming.tags, { Name = "${local.base}-${each.value.tier}-${each.value.az}", Tier = each.value.tier })
}

resource "aws_route_table" "this" {
  for_each = local.route_tables

  vpc_id = aws_vpc.this.id

  tags = merge(module.naming.tags, { Name = "${local.base}-${each.key}", Tier = each.value })
}

resource "aws_route_table_association" "this" {
  for_each = local.subnets

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.this[each.value.route_table].id
}

resource "aws_route" "internet" {
  count = var.public_subnets.enabled ? 1 : 0

  route_table_id         = aws_route_table.this["public"].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

resource "aws_eip" "nat" {
  for_each = toset(local.nat_keys)

  domain = "vpc"

  tags = merge(module.naming.tags, { Name = "${local.base}-nat-${local.azs[tonumber(each.key)]}" })
}

resource "aws_nat_gateway" "this" {
  for_each = toset(local.nat_keys)

  allocation_id     = aws_eip.nat[each.key].id
  subnet_id         = aws_subnet.this["public-${each.key}"].id
  connectivity_type = "public"

  tags = merge(module.naming.tags, { Name = "${local.base}-nat-${local.azs[tonumber(each.key)]}" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route" "nat" {
  for_each = var.nat.mode == "none" ? {} : { for rt, tier in local.route_tables : rt => trimprefix(rt, "private-") if tier == "private" }

  route_table_id         = aws_route_table.this[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[var.nat.mode == "per_az" ? each.value : "0"].id
}

resource "aws_route" "this" {
  for_each = local.routes

  route_table_id              = aws_route_table.this[each.value.route_table].id
  destination_cidr_block      = each.value.destination_cidr_block
  destination_ipv6_cidr_block = each.value.destination_ipv6_cidr_block
  destination_prefix_list_id  = each.value.destination_prefix_list_id
  transit_gateway_id          = each.value.transit_gateway_id
  vpc_peering_connection_id   = each.value.vpc_peering_connection_id
  network_interface_id        = each.value.network_interface_id
  vpc_endpoint_id             = each.value.vpc_endpoint_id
  gateway_id                  = each.value.gateway_id
  core_network_arn            = each.value.core_network_arn
}

resource "aws_vpc_dhcp_options" "this" {
  count = var.dhcp_options.enabled ? 1 : 0

  domain_name          = var.dhcp_options.domain_name
  domain_name_servers  = var.dhcp_options.domain_name_servers
  ntp_servers          = var.dhcp_options.ntp_servers
  netbios_name_servers = var.dhcp_options.netbios_name_servers
  netbios_node_type    = var.dhcp_options.netbios_node_type

  tags = module.naming.tags
}

resource "aws_vpc_dhcp_options_association" "this" {
  count = var.dhcp_options.enabled ? 1 : 0

  vpc_id          = aws_vpc.this.id
  dhcp_options_id = aws_vpc_dhcp_options.this[0].id
}
