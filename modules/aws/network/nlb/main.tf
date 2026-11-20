module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags
  names = merge(
    { lb = { suffix = "nlb", max_length = 32 } },
    { for k in keys(var.target_groups) : "tg-${k}" => { suffix = "nlb-${k}", max_length = 32 } }
  )
}

data "aws_vpc" "this" {
  count = local.egress_to_vpc && length(local.target_traffic) > 0 ? 1 : 0

  id = var.vpc_id
}

module "security_group" {
  source = "../../network/security-group"

  application          = var.application
  environment          = var.environment
  name                 = var.name
  purpose              = "nlb"
  tags                 = var.tags
  vpc_id               = var.vpc_id
  description          = "${module.naming.names.lb} network load balancer"
  allow_public_ingress = !var.internal
  ingress_rules        = local.ingress_rules
  egress_rules         = local.egress_rules
}

resource "aws_lb" "this" {
  name                                                         = module.naming.names.lb
  internal                                                     = var.internal
  load_balancer_type                                           = "network"
  security_groups                                              = local.security_group_ids
  subnets                                                      = local.static_ips ? null : var.subnet_ids
  ip_address_type                                              = var.ip_address_type
  enable_deletion_protection                                   = var.deletion_protection
  enable_cross_zone_load_balancing                             = var.cross_zone_load_balancing
  enable_zonal_shift                                           = var.zonal_shift
  dns_record_client_routing_policy                             = var.dns_record_client_routing_policy
  enforce_security_group_inbound_rules_on_private_link_traffic = var.enforce_security_group_inbound_rules_on_private_link_traffic

  dynamic "subnet_mapping" {
    for_each = local.static_ips ? range(length(var.subnet_ids)) : []
    content {
      subnet_id     = var.subnet_ids[subnet_mapping.value]
      allocation_id = var.static_ips.allocation_ids[subnet_mapping.value]
    }
  }

  dynamic "access_logs" {
    for_each = var.access_logs.enabled ? [1] : []
    content {
      enabled = true
      bucket  = var.access_logs.bucket
      prefix  = var.access_logs.prefix
    }
  }

  tags = merge(module.naming.tags, { Name = module.naming.names.lb })
}

resource "aws_lb_target_group" "this" {
  for_each = var.target_groups

  name                   = module.naming.names["tg-${each.key}"]
  target_type            = each.value.target_type
  port                   = each.value.port
  protocol               = each.value.protocol
  vpc_id                 = var.vpc_id
  deregistration_delay   = each.value.deregistration_delay
  preserve_client_ip     = each.value.target_type == "alb" || each.value.preserve_client_ip == null ? null : tostring(each.value.preserve_client_ip)
  proxy_protocol_v2      = each.value.target_type != "alb" && contains(["TCP", "TLS"], each.value.protocol) ? each.value.proxy_protocol_v2 : null
  connection_termination = each.value.target_type == "alb" ? null : each.value.connection_termination

  health_check {
    enabled             = true
    protocol            = local.health_check_protocols[each.key]
    port                = each.value.health_check.port
    path                = local.health_check_protocols[each.key] == "TCP" ? null : each.value.health_check.path
    matcher             = local.health_check_protocols[each.key] == "TCP" ? null : each.value.health_check.matcher
    interval            = each.value.health_check.interval
    timeout             = each.value.health_check.timeout
    healthy_threshold   = each.value.health_check.healthy_threshold
    unhealthy_threshold = each.value.health_check.unhealthy_threshold
  }

  tags = merge(module.naming.tags, { Name = module.naming.names["tg-${each.key}"] })
}

resource "aws_lb_target_group_attachment" "this" {
  for_each = local.targets

  target_group_arn  = aws_lb_target_group.this[each.value.target_group].arn
  target_id         = each.value.id
  port              = each.value.port
  availability_zone = each.value.availability_zone
}

resource "aws_lb_listener" "this" {
  for_each = var.listeners

  load_balancer_arn        = aws_lb.this.arn
  port                     = each.value.port
  protocol                 = each.value.protocol
  certificate_arn          = each.value.certificate_arn
  ssl_policy               = each.value.protocol == "TLS" ? each.value.ssl_policy : null
  alpn_policy              = each.value.alpn_policy
  tcp_idle_timeout_seconds = each.value.tcp_idle_timeout_seconds

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.value.target_group].arn
  }

  tags = merge(module.naming.tags, { Name = "${module.naming.names.lb}-${each.key}" })
}

resource "aws_lb_listener_certificate" "this" {
  for_each = local.listener_certificates

  listener_arn    = aws_lb_listener.this[each.value.listener].arn
  certificate_arn = each.value.certificate_arn
}

resource "aws_vpc_endpoint_service" "this" {
  count = var.endpoint_service.enabled ? 1 : 0

  acceptance_required        = var.endpoint_service.acceptance_required
  allowed_principals         = var.endpoint_service.allowed_principals
  network_load_balancer_arns = [aws_lb.this.arn]
  private_dns_name           = var.endpoint_service.private_dns_name
  supported_regions          = length(var.endpoint_service.supported_regions) > 0 ? var.endpoint_service.supported_regions : null

  tags = merge(module.naming.tags, { Name = module.naming.names.lb })
}
