resource "aws_subnet" "private" {
  for_each = {
    for idx, cidr in var.private_subnet_cidrs :
    idx => cidr
  }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = var.aws_availability_zone_names[each.key]
  map_public_ip_on_launch = false

  tags = merge(local.tags, {
    Name = "${local.rendered_name}-private-${var.aws_availability_zone_names[each.key]}"
    Tier = "private"
  })
}

resource "aws_subnet" "public" {
  for_each = {
    for idx, cidr in var.public_subnet_cidrs :
    idx => cidr
  }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = var.aws_availability_zone_names[each.key]
  map_public_ip_on_launch = false

  tags = merge(local.tags, {
    Name = "${local.rendered_name}-public-${var.aws_availability_zone_names[each.key]}"
    Tier = "public"
  })
}

resource "aws_subnet" "intra" {
  for_each = {
    for idx, cidr in var.intra_subnet_cidrs :
    idx => cidr
  }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = var.aws_availability_zone_names[each.key]
  map_public_ip_on_launch = false

  tags = merge(local.tags, {
    Name = "${local.rendered_name}-intra-${var.aws_availability_zone_names[each.key]}"
    Tier = "intra"
  })
}
