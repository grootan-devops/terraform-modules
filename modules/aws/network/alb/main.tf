resource "aws_security_group" "alb" {
  count       = length(var.security_groups) == 0 ? 1 : 0
  name        = "${local.rendered_name}-alb-sg"
  description = "Security group for application load balancer"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow inbound HTTP traffic"
    from_port   = var.listener_port
    to_port     = var.listener_port
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  dynamic "ingress" {
    for_each = var.certificate_arn != null ? [1] : []
    content {
      description = "Allow inbound HTTPS traffic"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.rendered_name}-alb-sg" })
}

resource "aws_lb" "this" {
  name                       = local.rendered_name
  internal                   = var.internal
  load_balancer_type         = "application"
  security_groups            = length(var.security_groups) > 0 ? var.security_groups : [aws_security_group.alb[0].id]
  subnets                    = var.subnets
  enable_deletion_protection = var.deletion_protection_enabled
  drop_invalid_header_fields = true
  idle_timeout               = var.idle_timeout

  tags = local.tags
}

resource "aws_lb_target_group" "default" {
  name        = substr("${local.rendered_name}-${var.default_target_group_name}", 0, 32)
  port        = var.default_target_group_port
  protocol    = var.default_target_group_protocol
  vpc_id      = var.vpc_id
  target_type = var.default_target_group_target_type

  health_check {
    path                = var.default_health_check_path
    matcher             = var.default_health_check_matcher
    interval            = var.default_health_check_interval
    timeout             = var.default_health_check_timeout
    healthy_threshold   = var.default_health_check_healthy_threshold
    unhealthy_threshold = var.default_health_check_unhealthy_threshold
  }

  tags = merge(local.tags, { Name = "${local.rendered_name}-${var.default_target_group_name}" })
}

resource "aws_lb_listener" "http" {
  count = var.certificate_arn == null ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = var.listener_port
  protocol          = var.listener_protocol

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.default.arn
  }

  tags = local.tags
}

resource "aws_lb_listener" "http_redirect" {
  count = var.certificate_arn != null ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = var.listener_port
  protocol          = var.listener_protocol

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = local.tags
}

resource "aws_lb_listener" "https" {
  count = var.certificate_arn != null ? 1 : 0

  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.default.arn
  }

  tags = local.tags
}

resource "aws_lb_target_group" "extra" {
  for_each = var.extra_routes

  name        = substr("${local.rendered_name}-${replace(each.key, "_", "-")}", 0, 32)
  port        = each.value.port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = coalesce(each.value.target_type, "ip")

  health_check {
    path                = coalesce(each.value.health_check_path, "/health")
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.tags, { Name = "${local.rendered_name}-${replace(each.key, "_", "-")}" })
}

resource "aws_lb_listener_rule" "extra" {
  for_each = var.extra_routes

  listener_arn = var.certificate_arn != null ? aws_lb_listener.https[0].arn : aws_lb_listener.http[0].arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.extra[each.key].arn
  }

  condition {
    path_pattern {
      values = each.value.paths
    }
  }
}
