# Listener and listener-rule arguments are validated as ARNs even under the
# mock provider, so the load balancer, target groups and listeners get
# well-formed ARNs instead of random strings. The HTTPS listener and the
# default and "auth" target groups get distinct ARNs so the wiring between
# them can be asserted.
mock_provider "aws" {
  mock_resource "aws_lb" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/core-prod-web/0123456789abcdef"
    }
  }

  mock_resource "aws_lb_target_group" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-west-2:123456789012:targetgroup/core-prod-web-extra/0123456789abcdef"
    }
  }

  mock_resource "aws_lb_listener" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-west-2:123456789012:listener/app/core-prod-web/0123456789abcdef/1111111111111111"
    }
  }
}

override_resource {
  target = aws_lb_listener.https
  values = {
    arn = "arn:aws:elasticloadbalancing:us-west-2:123456789012:listener/app/core-prod-web/0123456789abcdef/4444444444444444"
  }
}

override_resource {
  target = aws_lb_target_group.default
  values = {
    arn = "arn:aws:elasticloadbalancing:us-west-2:123456789012:targetgroup/core-prod-web-gateway/0123456789abcdef"
  }
}

override_resource {
  target = aws_lb_target_group.extra["auth"]
  values = {
    arn = "arn:aws:elasticloadbalancing:us-west-2:123456789012:targetgroup/core-prod-web-auth/0123456789abcdef"
  }
}

variables {
  application = "core"
  environment = "prod"
  name        = "web"
  vpc_id      = "vpc-0a1b2c3d4e5f67890"
  subnets     = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
}

run "verify_rendered_names" {
  command = plan

  assert {
    condition     = aws_lb.this.name == "core-prod-web"
    error_message = "ALB name did not match the rendered name <application>-<environment>-<name>."
  }

  assert {
    condition     = aws_security_group.alb[0].name == "core-prod-web-alb-sg"
    error_message = "Managed ALB security group name did not match <rendered_name>-alb-sg."
  }

  assert {
    condition     = aws_lb_target_group.default.name == "core-prod-web-gateway"
    error_message = "Default target group name did not match <rendered_name>-<default_target_group_name>."
  }
}

run "verify_name_fallback_when_null" {
  command = plan

  variables {
    name = null
  }

  assert {
    condition     = aws_lb.this.name == "core-prod"
    error_message = "ALB name did not fall back to <application>-<environment> when name is null."
  }

  assert {
    condition     = aws_lb.this.tags["Name"] == "core-prod"
    error_message = "ALB Name tag did not fall back to <application>-<environment> when name is null."
  }

  assert {
    condition     = aws_security_group.alb[0].name == "core-prod-alb-sg"
    error_message = "Security group name did not use the fallback rendered name."
  }

  assert {
    condition     = aws_lb_target_group.default.name == "core-prod-gateway"
    error_message = "Default target group name did not use the fallback rendered name."
  }
}

run "verify_name_fallback_when_empty" {
  command = plan

  variables {
    name = ""
  }

  assert {
    condition     = aws_lb.this.name == "core-prod"
    error_message = "ALB name did not fall back to <application>-<environment> when name is empty."
  }
}

run "verify_tags" {
  command = plan

  variables {
    certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    cloudwatch_logs = {
      retention_in_days = 90
    }
    extra_routes = {
      auth = {
        port     = 8001
        priority = 10
        paths    = ["/auth/*"]
      }
    }
    tags = {
      CostCenter = "1234"
      Team       = "platform"
    }
  }

  assert {
    condition     = aws_lb.this.tags["Application"] == "core" && aws_lb.this.tags["Environment"] == "prod" && aws_lb.this.tags["Name"] == "core-prod-web"
    error_message = "ALB is missing the Application, Environment or Name governance tags."
  }

  assert {
    condition     = aws_lb.this.tags["CostCenter"] == "1234" && aws_lb.this.tags["Team"] == "platform"
    error_message = "Caller tags from var.tags were not preserved on the ALB."
  }

  assert {
    condition     = aws_security_group.alb[0].tags["Name"] == "core-prod-web-alb-sg" && aws_security_group.alb[0].tags["Application"] == "core" && aws_security_group.alb[0].tags["CostCenter"] == "1234"
    error_message = "Security group tags must carry governance and caller tags with Name overridden to <rendered_name>-alb-sg."
  }

  assert {
    condition     = aws_lb_target_group.default.tags["Name"] == "core-prod-web-gateway" && aws_lb_target_group.default.tags["Environment"] == "prod" && aws_lb_target_group.default.tags["CostCenter"] == "1234"
    error_message = "Default target group tags must carry governance and caller tags with Name overridden to the target group name."
  }

  assert {
    condition     = aws_lb_target_group.extra["auth"].tags["Name"] == "core-prod-web-auth" && aws_lb_target_group.extra["auth"].tags["Application"] == "core"
    error_message = "Extra target group tags must carry governance tags with Name overridden to <rendered_name>-<route>."
  }

  assert {
    condition     = aws_lb_listener.https[0].tags["Name"] == "core-prod-web" && aws_lb_listener.https[0].tags["CostCenter"] == "1234"
    error_message = "HTTPS listener did not receive the module tags."
  }

  assert {
    condition     = aws_lb_listener.http_redirect[0].tags["Name"] == "core-prod-web" && aws_lb_listener.http_redirect[0].tags["Environment"] == "prod"
    error_message = "HTTP redirect listener did not receive the module tags."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].tags["Name"] == "/aws/alb/core-prod-web" && aws_cloudwatch_log_group.this[0].tags["Application"] == "core" && aws_cloudwatch_log_group.this[0].tags["Team"] == "platform"
    error_message = "CloudWatch log group tags must carry governance and caller tags with Name overridden to the log group name."
  }
}

run "verify_http_listener_tags_without_certificate" {
  command = plan

  assert {
    condition     = aws_lb_listener.http[0].tags["Application"] == "core" && aws_lb_listener.http[0].tags["Name"] == "core-prod-web"
    error_message = "Plain HTTP listener did not receive the module tags."
  }
}

run "verify_https_security_defaults" {
  command = plan

  variables {
    certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  }

  assert {
    condition     = aws_lb.this.drop_invalid_header_fields == true
    error_message = "ALB must drop invalid HTTP header fields to mitigate request smuggling."
  }

  assert {
    condition     = aws_lb.this.enable_deletion_protection == true
    error_message = "ALB deletion protection must be enabled by default."
  }

  assert {
    condition     = length(aws_lb_listener.https) == 1 && length(aws_lb_listener.http_redirect) == 1 && length(aws_lb_listener.http) == 0
    error_message = "With a certificate, the module must create the HTTPS and HTTP-redirect listeners and no plain HTTP forward listener."
  }

  assert {
    condition     = aws_lb_listener.https[0].ssl_policy == "ELBSecurityPolicy-TLS13-1-2-2021-06"
    error_message = "HTTPS listener must use the TLS 1.3/1.2 security policy ELBSecurityPolicy-TLS13-1-2-2021-06."
  }

  assert {
    condition     = aws_lb_listener.https[0].port == 443 && aws_lb_listener.https[0].protocol == "HTTPS"
    error_message = "HTTPS listener must listen on 443 with protocol HTTPS."
  }

  assert {
    condition     = aws_lb_listener.https[0].certificate_arn == "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    error_message = "HTTPS listener did not use the supplied ACM certificate."
  }

  assert {
    condition     = aws_lb_listener.https[0].default_action[0].type == "forward"
    error_message = "HTTPS listener must forward to the default target group."
  }

  assert {
    condition     = aws_lb_listener.http_redirect[0].port == 80 && aws_lb_listener.http_redirect[0].protocol == "HTTP"
    error_message = "HTTP redirect listener must listen on the default listener port 80 over HTTP."
  }

  assert {
    condition     = aws_lb_listener.http_redirect[0].default_action[0].type == "redirect"
    error_message = "HTTP listener must redirect when a certificate is configured."
  }

  assert {
    condition = (
      aws_lb_listener.http_redirect[0].default_action[0].redirect[0].protocol == "HTTPS" &&
      aws_lb_listener.http_redirect[0].default_action[0].redirect[0].port == "443" &&
      aws_lb_listener.http_redirect[0].default_action[0].redirect[0].status_code == "HTTP_301"
    )
    error_message = "HTTP listener must issue a permanent 301 redirect to HTTPS on port 443."
  }

  assert {
    condition     = toset([for r in aws_security_group.alb[0].ingress : r.from_port]) == toset([80, 443])
    error_message = "Managed security group must open the listener port and 443 when a certificate is configured."
  }
}

run "verify_listener_arn_output_with_certificate" {
  command = apply

  variables {
    certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  }

  assert {
    condition     = output.listener_arn == aws_lb_listener.https[0].arn
    error_message = "listener_arn output must be the HTTPS listener ARN when a certificate is configured."
  }

  assert {
    condition     = aws_lb_listener.https[0].default_action[0].target_group_arn == aws_lb_target_group.default.arn
    error_message = "HTTPS listener must forward to the default target group."
  }

  assert {
    condition     = aws_lb_listener.https[0].load_balancer_arn == aws_lb.this.arn && aws_lb_listener.http_redirect[0].load_balancer_arn == aws_lb.this.arn
    error_message = "Listeners must attach to the module's ALB."
  }
}

run "verify_parameter_defaults" {
  command = plan

  assert {
    condition     = aws_lb.this.internal == false && aws_lb.this.load_balancer_type == "application"
    error_message = "ALB must default to an internet-facing application load balancer."
  }

  assert {
    condition     = aws_lb.this.idle_timeout == 60
    error_message = "ALB idle timeout must default to 60 seconds."
  }

  assert {
    condition     = aws_lb.this.subnets == toset(["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"])
    error_message = "ALB subnets did not match var.subnets."
  }

  assert {
    condition     = length(aws_security_group.alb) == 1 && aws_security_group.alb[0].vpc_id == "vpc-0a1b2c3d4e5f67890"
    error_message = "A managed security group must be created in the VPC when no security_groups are supplied."
  }

  assert {
    condition     = length(aws_security_group.alb[0].ingress) == 1 && alltrue([for r in aws_security_group.alb[0].ingress : r.from_port == 80 && r.to_port == 80 && r.protocol == "tcp" && r.cidr_blocks == tolist(["0.0.0.0/0"])])
    error_message = "Without a certificate, the managed security group must open only the listener port 80 to the default 0.0.0.0/0."
  }

  assert {
    condition     = length(aws_lb_listener.http) == 1 && length(aws_lb_listener.https) == 0 && length(aws_lb_listener.http_redirect) == 0
    error_message = "Without a certificate, only the plain HTTP listener must be created."
  }

  assert {
    condition     = aws_lb_listener.http[0].port == 80 && aws_lb_listener.http[0].protocol == "HTTP" && aws_lb_listener.http[0].default_action[0].type == "forward"
    error_message = "Plain HTTP listener must default to port 80 / HTTP and forward to the default target group."
  }

  assert {
    condition = (
      aws_lb_target_group.default.port == 8000 &&
      aws_lb_target_group.default.protocol == "HTTP" &&
      aws_lb_target_group.default.target_type == "ip" &&
      aws_lb_target_group.default.vpc_id == "vpc-0a1b2c3d4e5f67890"
    )
    error_message = "Default target group must default to port 8000, HTTP, target type ip, in var.vpc_id."
  }

  assert {
    condition = (
      aws_lb_target_group.default.health_check[0].path == "/health" &&
      aws_lb_target_group.default.health_check[0].matcher == "200" &&
      aws_lb_target_group.default.health_check[0].interval == 30 &&
      aws_lb_target_group.default.health_check[0].timeout == 5 &&
      aws_lb_target_group.default.health_check[0].healthy_threshold == 2 &&
      aws_lb_target_group.default.health_check[0].unhealthy_threshold == 3
    )
    error_message = "Default target group health check did not use the shipped defaults (/health, 200, 30s, 5s, 2, 3)."
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.this) == 0
    error_message = "CloudWatch log group must not be created when cloudwatch_logs is null."
  }

  assert {
    condition     = length(aws_lb_target_group.extra) == 0 && length(aws_lb_listener_rule.extra) == 0
    error_message = "No extra target groups or listener rules must be created by default."
  }
}

run "verify_parameter_overrides" {
  command = plan

  variables {
    internal                                 = true
    idle_timeout                             = 120
    allowed_cidr_blocks                      = ["10.0.0.0/8"]
    listener_port                            = 8080
    deletion_protection_enabled              = false
    default_target_group_name                = "api"
    default_target_group_port                = 9000
    default_target_group_protocol            = "HTTPS"
    default_target_group_target_type         = "instance"
    default_health_check_path                = "/healthz"
    default_health_check_matcher             = "200-299"
    default_health_check_interval            = 15
    default_health_check_timeout             = 10
    default_health_check_healthy_threshold   = 3
    default_health_check_unhealthy_threshold = 5
  }

  assert {
    condition     = aws_lb.this.internal == true && aws_lb.this.idle_timeout == 120
    error_message = "internal and idle_timeout overrides did not flow through to the ALB."
  }

  assert {
    condition     = aws_lb.this.enable_deletion_protection == false
    error_message = "deletion_protection_enabled = false did not flow through to the ALB."
  }

  assert {
    condition     = aws_lb.this.drop_invalid_header_fields == true
    error_message = "drop_invalid_header_fields must stay enabled regardless of other inputs."
  }

  assert {
    condition     = alltrue([for r in aws_security_group.alb[0].ingress : r.from_port == 8080 && r.to_port == 8080 && r.cidr_blocks == tolist(["10.0.0.0/8"])])
    error_message = "listener_port and allowed_cidr_blocks overrides did not flow through to the security group ingress."
  }

  assert {
    condition     = aws_lb_listener.http[0].port == 8080
    error_message = "listener_port override did not flow through to the HTTP listener."
  }

  assert {
    condition = (
      aws_lb_target_group.default.name == "core-prod-web-api" &&
      aws_lb_target_group.default.port == 9000 &&
      aws_lb_target_group.default.protocol == "HTTPS" &&
      aws_lb_target_group.default.target_type == "instance"
    )
    error_message = "Default target group overrides (name, port, protocol, target_type) did not flow through."
  }

  assert {
    condition = (
      aws_lb_target_group.default.health_check[0].path == "/healthz" &&
      aws_lb_target_group.default.health_check[0].matcher == "200-299" &&
      aws_lb_target_group.default.health_check[0].interval == 15 &&
      aws_lb_target_group.default.health_check[0].timeout == 10 &&
      aws_lb_target_group.default.health_check[0].healthy_threshold == 3 &&
      aws_lb_target_group.default.health_check[0].unhealthy_threshold == 5
    )
    error_message = "Default health check overrides did not flow through to the target group."
  }
}

run "verify_external_security_groups_skip_managed_sg" {
  command = plan

  variables {
    security_groups = ["sg-0123456789abcdef0", "sg-0fedcba9876543210"]
  }

  assert {
    condition     = length(aws_security_group.alb) == 0
    error_message = "No managed security group must be created when security_groups are supplied."
  }

  assert {
    condition     = aws_lb.this.security_groups == toset(["sg-0123456789abcdef0", "sg-0fedcba9876543210"])
    error_message = "ALB must use the supplied security groups."
  }

  assert {
    condition     = output.security_group_id == "sg-0123456789abcdef0"
    error_message = "security_group_id output must return the first supplied security group."
  }
}

run "verify_extra_routes_with_https" {
  command = apply

  variables {
    certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    extra_routes = {
      auth = {
        port              = 8001
        priority          = 10
        paths             = ["/auth/*", "/oauth/*"]
        health_check_path = "/auth/health"
        target_type       = "instance"
      }
      user_profile = {
        port     = 8002
        priority = 20
        paths    = ["/profile/*"]
      }
    }
  }

  assert {
    condition     = length(aws_lb_target_group.extra) == 2 && length(aws_lb_listener_rule.extra) == 2
    error_message = "One target group and one listener rule must be created per extra route."
  }

  assert {
    condition     = aws_lb_target_group.extra["auth"].name == "core-prod-web-auth" && aws_lb_target_group.extra["user_profile"].name == "core-prod-web-user-profile"
    error_message = "Extra target group names must be <rendered_name>-<route> with underscores replaced by hyphens."
  }

  assert {
    condition     = aws_lb_target_group.extra["auth"].port == 8001 && aws_lb_target_group.extra["auth"].target_type == "instance" && aws_lb_target_group.extra["auth"].health_check[0].path == "/auth/health"
    error_message = "Extra route port, target_type and health_check_path did not flow through."
  }

  assert {
    condition     = aws_lb_target_group.extra["user_profile"].target_type == "ip" && aws_lb_target_group.extra["user_profile"].health_check[0].path == "/health" && aws_lb_target_group.extra["user_profile"].protocol == "HTTP"
    error_message = "Extra route must default to target type ip, health check /health and protocol HTTP."
  }

  assert {
    condition     = aws_lb_listener_rule.extra["auth"].listener_arn == aws_lb_listener.https[0].arn && aws_lb_listener_rule.extra["user_profile"].listener_arn == aws_lb_listener.https[0].arn
    error_message = "Extra route listener rules must attach to the HTTPS listener when a certificate is configured."
  }

  assert {
    condition     = aws_lb_listener_rule.extra["auth"].priority == 10 && aws_lb_listener_rule.extra["user_profile"].priority == 20
    error_message = "Extra route priorities did not flow through to the listener rules."
  }

  assert {
    condition     = toset(flatten([for c in aws_lb_listener_rule.extra["auth"].condition : [for p in c.path_pattern : p.values]])) == toset(["/auth/*", "/oauth/*"])
    error_message = "Extra route path patterns did not flow through to the listener rule condition."
  }

  assert {
    condition     = aws_lb_listener_rule.extra["auth"].action[0].type == "forward" && aws_lb_listener_rule.extra["auth"].action[0].target_group_arn == aws_lb_target_group.extra["auth"].arn
    error_message = "Extra route listener rule must forward to its own target group."
  }

  assert {
    condition     = aws_lb_target_group.extra["auth"].arn != aws_lb_target_group.extra["user_profile"].arn && aws_lb_listener_rule.extra["user_profile"].action[0].target_group_arn == aws_lb_target_group.extra["user_profile"].arn
    error_message = "Each extra route listener rule must forward to its own target group, not another route's."
  }

  assert {
    condition     = aws_lb_listener.https[0].default_action[0].target_group_arn == aws_lb_target_group.default.arn && aws_lb_target_group.default.arn != aws_lb_target_group.extra["auth"].arn
    error_message = "HTTPS listener default action must keep forwarding to the default target group when extra routes exist."
  }

  assert {
    condition     = output.extra_target_group_arns["auth"] == aws_lb_target_group.extra["auth"].arn && length(output.extra_target_group_arns) == 2
    error_message = "extra_target_group_arns output must map each route to its target group ARN."
  }
}

run "verify_extra_routes_without_certificate_use_http_listener" {
  command = apply

  variables {
    extra_routes = {
      auth = {
        port     = 8001
        priority = 10
        paths    = ["/auth/*"]
      }
    }
  }

  assert {
    condition     = aws_lb_listener_rule.extra["auth"].listener_arn == aws_lb_listener.http[0].arn
    error_message = "Extra route listener rules must attach to the HTTP listener when no certificate is configured."
  }

  assert {
    condition     = output.listener_arn == aws_lb_listener.http[0].arn
    error_message = "listener_arn output must be the HTTP listener ARN when no certificate is configured."
  }
}

run "verify_cloudwatch_logs_enabled_with_module_kms_key" {
  command = plan

  variables {
    cloudwatch_logs = {
      retention_in_days = 365
    }
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.this) == 1
    error_message = "CloudWatch log group must be created when cloudwatch_logs is set."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].name == "/aws/alb/core-prod-web"
    error_message = "CloudWatch log group name must be /aws/alb/<rendered_name>."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].kms_key_id == "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
    error_message = "CloudWatch log group must be encrypted with var.kms_key_arn when cloudwatch_logs.kms_key_arn is not set."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].retention_in_days == 365 && aws_cloudwatch_log_group.this[0].log_group_class == "STANDARD"
    error_message = "CloudWatch log group retention or class did not match the configuration."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].deletion_protection_enabled == false
    error_message = "CloudWatch log group deletion protection must default to false."
  }
}

run "verify_cloudwatch_logs_overrides" {
  command = plan

  variables {
    cloudwatch_logs = {
      retention_in_days           = 30
      kms_key_arn                 = "arn:aws:kms:us-west-2:123456789012:key/abcdefab-1234-1234-1234-abcdefabcdef"
      deletion_protection_enabled = true
    }
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].kms_key_id == "arn:aws:kms:us-west-2:123456789012:key/abcdefab-1234-1234-1234-abcdefabcdef"
    error_message = "cloudwatch_logs.kms_key_arn must take precedence over var.kms_key_arn."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].retention_in_days == 30 && aws_cloudwatch_log_group.this[0].deletion_protection_enabled == true
    error_message = "cloudwatch_logs retention and deletion protection overrides did not flow through."
  }
}

run "verify_invalid_environment_fails" {
  command = plan

  variables {
    environment = "INVALID_UPPERCASE"
  }

  expect_failures = [var.environment]
}
