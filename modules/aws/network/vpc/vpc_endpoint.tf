locals {
  endpoints_enabled = lookup(var.vpc_endpoints, "enabled", false)
  endpoint_services = local.endpoints_enabled ? lookup(var.vpc_endpoints, "services", []) : []
  s3_buckets        = local.endpoints_enabled ? lookup(var.vpc_endpoints, "s3_buckets", []) : []

  create_s3_gateway = local.endpoints_enabled && length(local.s3_buckets) > 0

  gateway_tiers = lookup(var.vpc_endpoints, "gateway_route_table_tiers", ["public", "private", "intra"])
  gateway_rt_ids = flatten([
    contains(local.gateway_tiers, "public") ? [aws_route_table.public.id] : [],
    contains(local.gateway_tiers, "private") ? [for rt in aws_route_table.private : rt.id] : [],
    contains(local.gateway_tiers, "intra") ? [aws_route_table.intra.id] : []
  ])

  create_dynamodb_gateway = local.endpoints_enabled && lookup(var.vpc_endpoints, "dynamodb_gateway", false)

  interface_tier = lookup(var.vpc_endpoints, "interface_subnet_tier", "private")
  _all_interface_subnets = local.interface_tier == "public" ? [for s in aws_subnet.public : s.id] : (
    local.interface_tier == "private" ? [for s in aws_subnet.private : s.id] : [for s in aws_subnet.intra : s.id]
  )
  interface_subnet_ids = lookup(var.vpc_endpoints, "subnet_indices", null) != null ? [
    for idx in var.vpc_endpoints.subnet_indices : local._all_interface_subnets[idx]
  ] : local._all_interface_subnets
}

resource "aws_security_group" "vpc_endpoints" {
  count = local.endpoints_enabled && length(local.endpoint_services) > 0 ? 1 : 0

  name        = "${local.rendered_name}-vpc-endpoints"
  description = "Security group for VPC Interface Endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  tags = merge(local.tags, {
    Name = "${local.rendered_name}-vpc-endpoints-sg"
  })
}

resource "aws_vpc_endpoint" "s3_gateway" {
  count = local.create_s3_gateway ? 1 : 0

  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.gateway_rt_ids

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowBucketLevelOperations"
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts"
        ]
        Resource = flatten([
          for bucket in local.s3_buckets : [
            "arn:aws:s3:::${bucket}",
            "arn:aws:s3:::${bucket}/*"
          ]
        ])
      }
    ]
  })

  tags = merge(local.tags, {
    Name = "${local.rendered_name}-s3-gateway-endpoint"
  })
}

resource "aws_vpc_endpoint" "dynamodb_gateway" {
  count = local.create_dynamodb_gateway ? 1 : 0

  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = local.gateway_rt_ids

  tags = merge(local.tags, {
    Name = "${local.rendered_name}-dynamodb-gateway-endpoint"
  })
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.endpoints_enabled && local.endpoint_services != null ? toset(local.endpoint_services) : toset([])

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.interface_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = lookup(var.vpc_endpoints, "private_dns_enabled", true)

  policy = lookup(lookup(var.vpc_endpoints, "policies", {}), each.value, null)

  tags = merge(local.tags, {
    Name = "${local.rendered_name}-${each.value}-endpoint"
  })
}
