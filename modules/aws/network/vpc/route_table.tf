resource "aws_default_route_table" "default" {
  default_route_table_id = aws_vpc.main.default_route_table_id

  route = []

  tags = merge(local.tags, {
    Name = "${local.rendered_name}-default-deny"
  })
}

# PUBLIC
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${local.rendered_name}-public"
    Tier = "public"
  })
}

resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# PRIVATE
resource "aws_route_table" "private" {
  for_each = aws_subnet.private

  vpc_id = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${local.rendered_name}-private-${var.aws_availability_zone_names[each.key]}"
    Tier = "private"
  })
}

resource "aws_route" "private_nat_gateway" {
  for_each = local.nat_enabled && !var.private_subnet_internet_gateway ? aws_subnet.private : {}

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = local.create_region ? aws_nat_gateway.regional[0].id : (local.create_single ? aws_nat_gateway.single[0].id : aws_nat_gateway.per_az[var.aws_availability_zone_names[each.key]].id)
}

resource "aws_route" "private_internet_gateway" {
  for_each = var.private_subnet_internet_gateway ? aws_subnet.private : {}

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

# INTRA
resource "aws_route_table" "intra" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.tags, {
    Name = "${local.rendered_name}-intra"
    Tier = "intra"
  })
}

resource "aws_route_table_association" "intra" {
  for_each = aws_subnet.intra

  subnet_id      = each.value.id
  route_table_id = aws_route_table.intra.id
}

resource "aws_route" "intra_internet_gateway" {
  count = var.intra_subnet_internet_gateway ? 1 : 0

  route_table_id         = aws_route_table.intra.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

# ADDITIONAL ROUTES
locals {
  public_routes = { for r in lookup(var.additional_routes, "public", []) : coalesce(lookup(r, "destination_cidr_block", null), lookup(r, "destination_ipv6_cidr_block", null), "null") => r }

  private_routes_flat = flatten([
    for idx, subnet in aws_subnet.private : [
      for r in lookup(var.additional_routes, "private", []) : merge(r, {
        key            = "${idx}-${coalesce(lookup(r, "destination_cidr_block", null), lookup(r, "destination_ipv6_cidr_block", null), "null")}"
        route_table_id = aws_route_table.private[idx].id
      })
    ]
  ])
  private_routes = { for r in local.private_routes_flat : r.key => r }

  intra_routes = { for r in lookup(var.additional_routes, "intra", []) : coalesce(lookup(r, "destination_cidr_block", null), lookup(r, "destination_ipv6_cidr_block", null), "null") => r }
}

resource "aws_route" "public_additional" {
  for_each = local.public_routes

  route_table_id              = aws_route_table.public.id
  destination_cidr_block      = lookup(each.value, "destination_cidr_block", null)
  destination_ipv6_cidr_block = lookup(each.value, "destination_ipv6_cidr_block", null)

  carrier_gateway_id        = lookup(each.value, "carrier_gateway_id", null)
  core_network_arn          = lookup(each.value, "core_network_arn", null)
  egress_only_gateway_id    = lookup(each.value, "egress_only_gateway_id", null)
  gateway_id                = lookup(each.value, "gateway_id", null)
  nat_gateway_id            = lookup(each.value, "nat_gateway_id", null)
  local_gateway_id          = lookup(each.value, "local_gateway_id", null)
  network_interface_id      = lookup(each.value, "network_interface_id", null)
  transit_gateway_id        = lookup(each.value, "transit_gateway_id", null)
  vpc_endpoint_id           = lookup(each.value, "vpc_endpoint_id", null)
  vpc_peering_connection_id = lookup(each.value, "vpc_peering_connection_id", null)
}

resource "aws_route" "private_additional" {
  for_each = local.private_routes

  route_table_id              = each.value.route_table_id
  destination_cidr_block      = lookup(each.value, "destination_cidr_block", null)
  destination_ipv6_cidr_block = lookup(each.value, "destination_ipv6_cidr_block", null)

  carrier_gateway_id        = lookup(each.value, "carrier_gateway_id", null)
  core_network_arn          = lookup(each.value, "core_network_arn", null)
  egress_only_gateway_id    = lookup(each.value, "egress_only_gateway_id", null)
  gateway_id                = lookup(each.value, "gateway_id", null)
  nat_gateway_id            = lookup(each.value, "nat_gateway_id", null)
  local_gateway_id          = lookup(each.value, "local_gateway_id", null)
  network_interface_id      = lookup(each.value, "network_interface_id", null)
  transit_gateway_id        = lookup(each.value, "transit_gateway_id", null)
  vpc_endpoint_id           = lookup(each.value, "vpc_endpoint_id", null)
  vpc_peering_connection_id = lookup(each.value, "vpc_peering_connection_id", null)
}

resource "aws_route" "intra_additional" {
  for_each = local.intra_routes

  route_table_id              = aws_route_table.intra.id
  destination_cidr_block      = lookup(each.value, "destination_cidr_block", null)
  destination_ipv6_cidr_block = lookup(each.value, "destination_ipv6_cidr_block", null)

  carrier_gateway_id        = lookup(each.value, "carrier_gateway_id", null)
  core_network_arn          = lookup(each.value, "core_network_arn", null)
  egress_only_gateway_id    = lookup(each.value, "egress_only_gateway_id", null)
  gateway_id                = lookup(each.value, "gateway_id", null)
  nat_gateway_id            = lookup(each.value, "nat_gateway_id", null)
  local_gateway_id          = lookup(each.value, "local_gateway_id", null)
  network_interface_id      = lookup(each.value, "network_interface_id", null)
  transit_gateway_id        = lookup(each.value, "transit_gateway_id", null)
  vpc_endpoint_id           = lookup(each.value, "vpc_endpoint_id", null)
  vpc_peering_connection_id = lookup(each.value, "vpc_peering_connection_id", null)
}
