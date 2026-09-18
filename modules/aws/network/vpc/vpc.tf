resource "aws_vpc" "main" {
  cidr_block                           = var.cidr_block
  instance_tenancy                     = "default"
  enable_dns_support                   = lookup(var.dns, "enable_dns_support", true)
  enable_network_address_usage_metrics = false
  enable_dns_hostnames                 = lookup(var.dns, "enable_dns_hostnames", true)

  tags = local.tags
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.main.id

  tags = local.tags
}
