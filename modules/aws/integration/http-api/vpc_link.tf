module "vpc_link_security_group" {
  source = "../../network/security-group"
  count  = local.vpc_link_security_group ? 1 : 0

  application  = var.application
  environment  = var.environment
  name         = var.name
  purpose      = "vpclink"
  tags         = var.tags
  vpc_id       = var.vpc_link.vpc_id
  egress_rules = local.vpc_link_egress_rules
}

resource "aws_apigatewayv2_vpc_link" "this" {
  count = var.vpc_link.enabled ? 1 : 0

  name               = local.api_name
  subnet_ids         = var.vpc_link.subnet_ids
  security_group_ids = local.vpc_link_security_group_ids

  tags = merge(module.naming.tags, { Name = local.api_name })
}
