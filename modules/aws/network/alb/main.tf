module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags
  names = merge(
    { lb = { max_length = 32 } },
    { for k in keys(var.target_groups) : "tg-${k}" => { suffix = k, max_length = 32 } }
  )
}

data "aws_vpc" "this" {
  count = var.security_group.create && local.egress_to_vpc && length(local.target_ports) > 0 ? 1 : 0

  id = var.vpc_id
}

module "security_group" {
  source = "../../network/security-group"
  count  = var.security_group.create ? 1 : 0

  application          = var.application
  environment          = var.environment
  name                 = var.name
  purpose              = "alb"
  tags                 = var.tags
  vpc_id               = var.vpc_id
  description          = "${module.naming.names.lb} load balancer"
  allow_public_ingress = !var.internal
  ingress_rules        = local.ingress_rules
  egress_rules         = local.egress_rules
}

#trivy:ignore:AVD-AWS-0053
resource "aws_lb" "this" {
  name                       = module.naming.names.lb
  internal                   = var.internal
  load_balancer_type         = "application"
  security_groups            = local.security_group_ids
  subnets                    = var.subnet_ids
  enable_deletion_protection = var.deletion_protection
  drop_invalid_header_fields = true
  desync_mitigation_mode     = var.desync_mitigation_mode
  enable_waf_fail_open       = var.waf.fail_open
  enable_http2               = true
  idle_timeout               = var.idle_timeout

  dynamic "access_logs" {
    for_each = var.access_logs.enabled ? [1] : []
    content {
      enabled = true
      bucket  = var.access_logs.bucket
      prefix  = var.access_logs.prefix
    }
  }

  dynamic "connection_logs" {
    for_each = var.access_logs.enabled && var.access_logs.connection_logs ? [1] : []
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

  name                 = module.naming.names["tg-${each.key}"]
  target_type          = each.value.target_type
  port                 = each.value.target_type == "lambda" ? null : each.value.port
  protocol             = each.value.target_type == "lambda" ? null : each.value.protocol
  vpc_id               = each.value.target_type == "lambda" ? null : var.vpc_id
  deregistration_delay = each.value.deregistration_delay

  health_check {
    enabled             = true
    path                = each.value.health_check.path
    protocol            = each.value.target_type == "lambda" ? null : coalesce(each.value.health_check.protocol, each.value.protocol)
    port                = each.value.target_type == "lambda" ? null : each.value.health_check.port
    matcher             = each.value.health_check.matcher
    interval            = each.value.health_check.interval
    timeout             = each.value.health_check.timeout
    healthy_threshold   = each.value.health_check.healthy_threshold
    unhealthy_threshold = each.value.health_check.unhealthy_threshold
  }

  tags = merge(module.naming.tags, { Name = module.naming.names["tg-${each.key}"] })
}

resource "aws_lb_listener" "https" {
  count = var.https_listener.enabled ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = var.https_listener.port
  protocol          = "HTTPS"
  ssl_policy        = var.https_listener.ssl_policy
  certificate_arn   = var.https_listener.certificate_arn

  default_action {
    type             = local.default_forward ? "forward" : "fixed-response"
    target_group_arn = local.default_forward ? try(aws_lb_target_group.this[var.default_target_group].arn, null) : null

    dynamic "fixed_response" {
      for_each = local.default_forward ? [] : [1]
      content {
        content_type = "text/plain"
        message_body = "Not Found"
        status_code  = "404"
      }
    }
  }

  tags = merge(module.naming.tags, { Name = "${module.naming.names.lb}-https" })
}

resource "aws_lb_listener_certificate" "this" {
  for_each = var.https_listener.enabled ? { for i, arn in var.https_listener.additional_certificate_arns : tostring(i) => arn } : {}

  listener_arn    = aws_lb_listener.https[0].arn
  certificate_arn = each.value
}

resource "aws_lb_listener" "http" {
  count = var.http_listener.enabled ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = var.http_listener.port
  protocol          = "HTTP"

  default_action {
    type             = var.http_listener.forward ? (local.default_forward ? "forward" : "fixed-response") : "redirect"
    target_group_arn = var.http_listener.forward && local.default_forward ? try(aws_lb_target_group.this[var.default_target_group].arn, null) : null

    dynamic "redirect" {
      for_each = var.http_listener.forward ? [] : [1]
      content {
        port        = tostring(var.https_listener.port)
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }

    dynamic "fixed_response" {
      for_each = var.http_listener.forward && !local.default_forward ? [1] : []
      content {
        content_type = "text/plain"
        message_body = "Not Found"
        status_code  = "404"
      }
    }
  }

  tags = merge(module.naming.tags, { Name = "${module.naming.names.lb}-http" })
}

resource "aws_lb_listener_rule" "this" {
  for_each = local.listener_rules

  listener_arn = local.listener_arns[each.value.listener]
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.value.target_group].arn
  }

  dynamic "condition" {
    for_each = length(each.value.path_patterns) > 0 ? [1] : []
    content {
      path_pattern {
        values = each.value.path_patterns
      }
    }
  }

  dynamic "condition" {
    for_each = length(each.value.host_headers) > 0 ? [1] : []
    content {
      host_header {
        values = each.value.host_headers
      }
    }
  }

  tags = merge(module.naming.tags, { Name = "${module.naming.names.lb}-${each.key}" })
}

resource "aws_wafv2_web_acl_association" "this" {
  count = var.waf.enabled ? 1 : 0

  resource_arn = aws_lb.this.arn
  web_acl_arn  = var.waf.web_acl_arn
}
