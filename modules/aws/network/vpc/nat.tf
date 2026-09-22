locals {
  nat_enabled   = lookup(var.nat, "enabled", true)
  nat_mode      = lookup(var.nat, "mode", "regional")
  create_single = local.nat_enabled && local.nat_mode == "single_az"
  create_per_az = local.nat_enabled && local.nat_mode == "per_az"
  create_region = local.nat_enabled && local.nat_mode == "regional"

  nat_azs = local.create_per_az || local.create_region ? var.aws_availability_zone_names : (local.create_single && length(var.aws_availability_zone_names) > 0 ? [var.aws_availability_zone_names[0]] : [])

  eips_to_create = { for az in local.nat_azs : az => az if !contains(keys(lookup(var.nat, "eip_allocation_ids", {})), az) }
}

resource "aws_eip" "nat" {
  for_each = local.eips_to_create

  domain           = "vpc"
  public_ipv4_pool = "amazon"

  tags = merge(local.tags, {
    Name = "${local.rendered_name}-nat-${each.key}"
  })
}

locals {
  nat_allocation_ids = { for az in local.nat_azs : az => lookup(lookup(var.nat, "eip_allocation_ids", {}), az, lookup(aws_eip.nat, az, null) != null ? aws_eip.nat[az].id : null) }
}

resource "aws_nat_gateway" "regional" {
  count = local.create_region ? 1 : 0

  availability_mode = "regional"
  connectivity_type = "public"
  vpc_id            = aws_vpc.main.id

  dynamic "availability_zone_address" {
    for_each = local.nat_azs
    content {
      allocation_ids    = [local.nat_allocation_ids[availability_zone_address.value]]
      availability_zone = availability_zone_address.value
    }
  }

  tags = merge(local.tags, {
    Name = "${local.rendered_name}-regional-nat"
  })
}

resource "aws_nat_gateway" "single" {
  count = local.create_single ? 1 : 0

  availability_mode = "zonal"
  connectivity_type = "public"
  subnet_id         = aws_subnet.public["0"].id
  allocation_id     = local.nat_allocation_ids[local.nat_azs[0]]

  tags = merge(local.tags, {
    Name = "${local.rendered_name}-single-nat"
  })
}

resource "aws_nat_gateway" "per_az" {
  for_each = local.create_per_az ? toset(local.nat_azs) : toset([])

  availability_mode = "zonal"
  connectivity_type = "public"
  subnet_id         = aws_subnet.public[tostring(index(var.aws_availability_zone_names, each.value))].id
  allocation_id     = local.nat_allocation_ids[each.value]

  tags = merge(local.tags, {
    Name = "${local.rendered_name}-nat-${each.value}"
  })
}
