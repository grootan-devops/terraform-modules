mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "eu-west-1"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_data "aws_vpc" {
    defaults = {
      cidr_block = "10.0.0.0/16"
    }
  }

  mock_resource "aws_lb" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:loadbalancer/app/core-prod/50dc6c495c0c9188"
      arn_suffix = "app/core-prod/50dc6c495c0c9188"
      dns_name   = "core-prod-1234567890.eu-west-1.elb.amazonaws.com"
      zone_id    = "Z32O12XQLNTSW2"
    }
  }

  mock_resource "aws_lb_target_group" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:targetgroup/core-prod-app/73e2d6bc24d8a067"
      arn_suffix = "targetgroup/core-prod-app/73e2d6bc24d8a067"
    }
  }

  mock_resource "aws_lb_listener" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:listener/app/core-prod/50dc6c495c0c9188/f2f7dc8efc522ab2"
    }
  }
}

variables {
  application    = "core"
  environment    = "prod"
  internal       = true
  vpc_id         = "vpc-0a1b2c3d4e5f67890"
  subnet_ids     = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  tags           = { Team = "web" }
  https_listener = { certificate_arn = "arn:aws:acm:eu-west-1:123456789012:certificate/11111111-2222-3333-4444-555555555555" }
  target_groups = {
    app = { port = 8080 }
  }
  default_target_group = "app"
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = aws_lb.this.name == "core-prod" && aws_lb.this.internal && aws_lb.this.load_balancer_type == "application"
    error_message = "The load balancer is named <application>-<environment> and internal here."
  }

  assert {
    condition     = aws_lb.this.drop_invalid_header_fields && aws_lb.this.desync_mitigation_mode == "defensive" && aws_lb.this.enable_deletion_protection && !aws_lb.this.enable_waf_fail_open
    error_message = "Invalid headers dropped (ELB.4), defensive desync mode (ELB.12), deletion protection (ELB.6), WAF fail closed."
  }

  assert {
    condition     = aws_lb_listener.https[0].ssl_policy == "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09" && aws_lb_listener.https[0].port == 443 && aws_lb_listener.https[0].protocol == "HTTPS" && aws_lb_listener.https[0].default_action[0].type == "forward"
    error_message = "HTTPS listener on 443 with the TLS 1.3 policy forwarding to the default target group (ELB.17)."
  }

  assert {
    condition     = aws_lb_listener.http[0].default_action[0].type == "redirect" && aws_lb_listener.http[0].default_action[0].redirect[0].protocol == "HTTPS" && aws_lb_listener.http[0].default_action[0].redirect[0].port == "443" && aws_lb_listener.http[0].default_action[0].redirect[0].status_code == "HTTP_301"
    error_message = "HTTP only redirects to HTTPS (ELB.1)."
  }

  assert {
    condition     = length(module.security_group[0].ingress_rule_ids) == 0 && keys(module.security_group[0].egress_rule_ids) == ["vpc-8080"]
    error_message = "No ingress until sources are listed; egress only to the target port in the VPC."
  }

  assert {
    condition     = aws_lb_target_group.this["app"].name == "core-prod-app" && aws_lb_target_group.this["app"].port == 8080 && aws_lb_target_group.this["app"].protocol == "HTTP" && aws_lb_target_group.this["app"].health_check[0].path == "/health" && aws_lb_target_group.this["app"].health_check[0].port == "traffic-port"
    error_message = "Target groups are named per key with a /health check."
  }

  assert {
    condition     = length(aws_lb.this.access_logs) == 0 && length(aws_wafv2_web_acl_association.this) == 0 && length(aws_lb_listener_rule.this) == 0 && length(aws_lb_listener_certificate.this) == 0
    error_message = "No access logs, web ACL, rules or extra certificates by default."
  }

  assert {
    condition     = aws_lb.this.tags["Name"] == "core-prod" && aws_lb.this.tags["Team"] == "web" && aws_lb.this.tags["ManagedBy"] == "Terraform"
    error_message = "Caller and governance tags must be applied."
  }
}

run "long_names_are_truncated" {
  command = plan

  variables {
    name                 = "customer-facing-storefront"
    target_groups        = { checkout-api = { port = 8443, protocol = "HTTPS" } }
    default_target_group = "checkout-api"
  }

  assert {
    condition     = length(aws_lb.this.name) == 32 && startswith(aws_lb.this.name, "core-prod-customer-facing-") && length(aws_lb_target_group.this["checkout-api"].name) == 32
    error_message = "Names over 32 characters are cut with a hash suffix."
  }

  assert {
    condition     = aws_lb_target_group.this["checkout-api"].protocol == "HTTPS" && aws_lb_target_group.this["checkout-api"].health_check[0].protocol == "HTTPS"
    error_message = "The health check follows the target protocol (ELB.21, ELB.22)."
  }
}

run "internet_facing_sources" {
  command = plan

  variables {
    internal = false
    security_group = {
      ingress_cidr_blocks        = ["0.0.0.0/0", "::/0"]
      ingress_security_group_ids = ["sg-0aaaaaaaaaaaaaaaa"]
      ingress_prefix_list_ids    = ["pl-0bbbbbbbbbbbbbbbb"]
    }
  }

  assert {
    condition     = keys(module.security_group[0].ingress_rule_ids) == ["cidr-0-443", "cidr-0-80", "cidr-1-443", "cidr-1-80", "pl-0-443", "pl-0-80", "sg-0-443", "sg-0-80"]
    error_message = "Every listener port is opened to every listed source."
  }

  assert {
    condition     = !aws_lb.this.internal
    error_message = "internal = false makes the load balancer internet-facing."
  }
}

run "explicit_egress" {
  command = plan

  variables {
    target_groups = {
      app = { port = 8080, health_check = { port = "8081" } }
      fn  = { target_type = "lambda" }
    }
    security_group = { egress_security_group_ids = ["sg-0ccccccccccccccc0"] }
  }

  assert {
    condition     = keys(module.security_group[0].egress_rule_ids) == ["sg-0-8080", "sg-0-8081"] && length(data.aws_vpc.this) == 0
    error_message = "Egress goes to the listed groups on the target and health check ports only."
  }

  assert {
    condition     = aws_lb_target_group.this["fn"].port == null && aws_lb_target_group.this["fn"].vpc_id == null && aws_lb_target_group.this["fn"].target_type == "lambda"
    error_message = "Lambda target groups have no port or VPC."
  }
}

run "rules_certificates_waf_and_logs" {
  command = plan

  variables {
    https_listener = {
      certificate_arn             = "arn:aws:acm:eu-west-1:123456789012:certificate/11111111-2222-3333-4444-555555555555"
      additional_certificate_arns = ["arn:aws:acm:eu-west-1:123456789012:certificate/22222222-2222-3333-4444-555555555555"]
      ssl_policy                  = "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09"
    }
    target_groups = {
      app = { port = 8080 }
      api = { port = 9090 }
    }
    listener_rules = {
      api = { priority = 10, target_group = "api", path_patterns = ["/api/*"], host_headers = ["api.example.com"] }
    }
    waf         = { enabled = true, web_acl_arn = "arn:aws:wafv2:eu-west-1:123456789012:regional/webacl/core-prod/a1b2c3d4-5678-90ab-cdef-EXAMPLE11111" }
    access_logs = { enabled = true, bucket = "core-prod-logs-123456789012-eu-west-1", prefix = "alb" }
  }

  assert {
    condition     = keys(aws_lb_listener_rule.this) == ["https-api"] && aws_lb_listener_rule.this["https-api"].priority == 10 && length(aws_lb_listener_rule.this["https-api"].condition) == 2
    error_message = "Listener rules attach to the HTTPS listener only."
  }

  assert {
    condition     = aws_lb_listener_certificate.this["0"].certificate_arn == "arn:aws:acm:eu-west-1:123456789012:certificate/22222222-2222-3333-4444-555555555555" && aws_lb_listener.https[0].ssl_policy == "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09"
    error_message = "Extra certificates are added for SNI."
  }

  assert {
    condition     = aws_wafv2_web_acl_association.this[0].web_acl_arn == "arn:aws:wafv2:eu-west-1:123456789012:regional/webacl/core-prod/a1b2c3d4-5678-90ab-cdef-EXAMPLE11111"
    error_message = "waf.enabled associates the web ACL (ELB.16)."
  }

  assert {
    condition     = aws_lb.this.access_logs[0].bucket == "core-prod-logs-123456789012-eu-west-1" && aws_lb.this.access_logs[0].prefix == "alb" && aws_lb.this.access_logs[0].enabled && aws_lb.this.connection_logs[0].bucket == "core-prod-logs-123456789012-eu-west-1"
    error_message = "Access and connection logs go to the bucket (ELB.5)."
  }

  assert {
    condition     = keys(module.security_group[0].egress_rule_ids) == ["vpc-8080", "vpc-9090"]
    error_message = "Egress covers every target port."
  }
}

run "plain_http_forward" {
  command = plan

  variables {
    https_listener = { enabled = false }
    http_listener  = { forward = true }
    listener_rules = { app = { priority = 5, target_group = "app", path_patterns = ["/app/*"] } }
  }

  assert {
    condition     = length(aws_lb_listener.https) == 0 && aws_lb_listener.http[0].default_action[0].type == "forward" && output.https_listener_arn == null
    error_message = "forward = true serves plain HTTP without an HTTPS listener."
  }

  assert {
    condition     = keys(aws_lb_listener_rule.this) == ["http-app"]
    error_message = "Rules follow the forwarding listener."
  }
}

run "fixed_response_without_default" {
  command = plan

  variables {
    default_target_group = null
  }

  assert {
    condition     = aws_lb_listener.https[0].default_action[0].type == "fixed-response" && aws_lb_listener.https[0].default_action[0].fixed_response[0].status_code == "404"
    error_message = "Without default_target_group the listener answers 404."
  }
}

run "bring_your_own_security_group" {
  command = plan

  variables {
    security_group = { create = false, additional_security_group_ids = ["sg-0ddddddddddddddd0"] }
  }

  assert {
    condition     = length(module.security_group) == 0 && toset(aws_lb.this.security_groups) == toset(["sg-0ddddddddddddddd0"]) && output.security_group_id == null
    error_message = "create = false uses only the caller groups."
  }
}

run "outputs" {
  command = apply

  assert {
    condition     = output.arn_suffix == "app/core-prod/50dc6c495c0c9188" && output.zone_id == "Z32O12XQLNTSW2" && output.dns_name == "core-prod-1234567890.eu-west-1.elb.amazonaws.com"
    error_message = "Outputs expose the load balancer for DNS and metrics."
  }

  assert {
    condition     = keys(output.target_group_arns) == ["app"] && output.target_group_arn_suffixes["app"] == "targetgroup/core-prod-app/73e2d6bc24d8a067" && output.https_listener_arn == aws_lb_listener.https[0].arn && output.security_group_id == module.security_group[0].id
    error_message = "Target group, listener and security group outputs are wired."
  }

  assert {
    condition     = aws_lb_listener.https[0].default_action[0].target_group_arn == aws_lb_target_group.this["app"].arn
    error_message = "The HTTPS default action forwards to default_target_group."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Web_ALB"
  }

  expect_failures = [var.name]
}

run "rejects_invalid_application" {
  command = plan

  variables {
    application = "Core"
  }

  expect_failures = [var.application]
}

run "rejects_invalid_environment" {
  command = plan

  variables {
    environment = "PROD"
  }

  expect_failures = [var.environment]
}

run "rejects_single_subnet" {
  command = plan

  variables {
    subnet_ids = ["subnet-0123456789abcdef0"]
  }

  expect_failures = [var.subnet_ids]
}

run "rejects_open_ingress_on_internal" {
  command = plan

  variables {
    security_group = { ingress_cidr_blocks = ["0.0.0.0/0"] }
  }

  expect_failures = [var.security_group]
}

run "rejects_no_security_group" {
  command = plan

  variables {
    security_group = { create = false }
  }

  expect_failures = [var.security_group]
}

run "rejects_https_without_certificate" {
  command = plan

  variables {
    https_listener = {}
  }

  expect_failures = [var.https_listener]
}

run "rejects_old_tls_policy" {
  command = plan

  variables {
    https_listener = { certificate_arn = "arn:aws:acm:eu-west-1:123456789012:certificate/11111111-2222-3333-4444-555555555555", ssl_policy = "ELBSecurityPolicy-2016-08" }
  }

  expect_failures = [var.https_listener]
}

run "rejects_tls13_policy_not_on_elb17_list" {
  command = plan

  variables {
    https_listener = { certificate_arn = "arn:aws:acm:eu-west-1:123456789012:certificate/11111111-2222-3333-4444-555555555555", ssl_policy = "ELBSecurityPolicy-TLS13-1-2-Ext1-2021-06" }
  }

  expect_failures = [var.https_listener]
}

run "rejects_redirect_without_https" {
  command = plan

  variables {
    https_listener = { enabled = false }
  }

  expect_failures = [var.http_listener]
}

run "rejects_no_listener" {
  command = plan

  variables {
    https_listener = { enabled = false }
    http_listener  = { enabled = false }
  }

  expect_failures = [var.http_listener]
}

run "rejects_invalid_target_group_key" {
  command = plan

  variables {
    target_groups        = { App_1 = { port = 80 } }
    default_target_group = null
  }

  expect_failures = [var.target_groups]
}

run "rejects_invalid_target_type" {
  command = plan

  variables {
    target_groups = { app = { port = 80, target_type = "alb" } }
  }

  expect_failures = [var.target_groups]
}

run "rejects_target_group_without_port" {
  command = plan

  variables {
    target_groups = { app = {} }
  }

  expect_failures = [var.target_groups]
}

run "rejects_invalid_health_check_port" {
  command = plan

  variables {
    target_groups = { app = { port = 80, health_check = { port = "http" } } }
  }

  expect_failures = [var.target_groups]
}

run "rejects_unknown_default_target_group" {
  command = plan

  variables {
    default_target_group = "web"
  }

  expect_failures = [var.default_target_group]
}

run "rejects_rule_for_unknown_target_group" {
  command = plan

  variables {
    listener_rules = { api = { priority = 10, target_group = "api", path_patterns = ["/api/*"] } }
  }

  expect_failures = [var.listener_rules]
}

run "rejects_rule_without_condition" {
  command = plan

  variables {
    listener_rules = { api = { priority = 10, target_group = "app" } }
  }

  expect_failures = [var.listener_rules]
}

run "rejects_access_logs_without_bucket" {
  command = plan

  variables {
    access_logs = { enabled = true }
  }

  expect_failures = [var.access_logs]
}

run "rejects_waf_without_web_acl" {
  command = plan

  variables {
    waf = { enabled = true }
  }

  expect_failures = [var.waf]
}

run "rejects_invalid_idle_timeout" {
  command = plan

  variables {
    idle_timeout = 0
  }

  expect_failures = [var.idle_timeout]
}

run "rejects_monitor_desync_mode" {
  command = plan

  variables {
    desync_mitigation_mode = "monitor"
  }

  expect_failures = [var.desync_mitigation_mode]
}

run "alarms_by_default" {
  command = plan

  assert {
    condition     = sort(keys(output.alarm_names)) == tolist(["alb-lb-app-unhealthy-hosts", "alb-lb-elb-5xx-count", "alb-lb-rejected-connections", "alb-lb-target-5xx-rate", "alb-lb-target-response-time-p99"])
    error_message = "Default alarms: target and ELB 5XX, p99 response time, rejected connections, unhealthy hosts per target group."
  }

  assert {
    condition     = alltrue([for n in values(output.alarm_names) : startswith(n, "core-prod-alb-lb-")]) && module.alarms[0].alarm_settings["alb-lb-target-response-time-p99"].threshold == 48
    error_message = "Alarm names start with the module base name; p99 response time alarms at 80 % of the idle timeout."
  }

  assert {
    condition     = alltrue([for k, r in module.alarms[0].alarm_routes : r.topic_arn == null])
    error_message = "Without topic_arns, alarms have no actions."
  }
}

run "alarms_off" {
  command = plan

  variables {
    alarms = { enabled = false }
  }

  assert {
    condition     = length(module.alarms) == 0 && length(output.alarm_names) == 0 && length(output.alarm_arns) == 0
    error_message = "alarms.enabled = false creates no alarms."
  }
}

run "alarms_tuned_and_routed" {
  command = apply

  variables {
    idle_timeout = 120
    target_groups = {
      app = { port = 8080 }
      api = { port = 9090 }
    }
    alarms = {
      topic_arns = {
        critical = "arn:aws:sns:eu-west-1:123456789012:platform-prod-critical"
        warning  = "arn:aws:sns:eu-west-1:123456789012:platform-prod-warning"
        info     = "arn:aws:sns:eu-west-1:123456789012:platform-prod-info"
      }
      overrides = {
        target_5xx_rate      = { threshold = 2 }
        rejected_connections = { enabled = false }
      }
    }
  }

  assert {
    condition     = sort(keys(output.alarm_arns)) == tolist(["alb-lb-api-unhealthy-hosts", "alb-lb-app-unhealthy-hosts", "alb-lb-elb-5xx-count", "alb-lb-target-5xx-rate", "alb-lb-target-response-time-p99"])
    error_message = "A disabled alarm is dropped; each target group gets an unhealthy hosts alarm."
  }

  assert {
    condition     = module.alarms[0].alarm_settings["alb-lb-target-5xx-rate"].threshold == 2 && module.alarms[0].alarm_settings["alb-lb-target-5xx-rate"].evaluation_periods == 3 && module.alarms[0].alarm_settings["alb-lb-target-response-time-p99"].threshold == 96
    error_message = "Overrides change one setting; the rest keep the preset defaults and follow the idle timeout."
  }

  assert {
    condition     = module.alarms[0].alarm_routes["alb-lb-target-5xx-rate"].topic_arn == "arn:aws:sns:eu-west-1:123456789012:platform-prod-critical" && module.alarms[0].alarm_routes["alb-lb-target-response-time-p99"].topic_arn == "arn:aws:sns:eu-west-1:123456789012:platform-prod-warning"
    error_message = "Each alarm notifies the topic for its severity."
  }
}

run "alarms_plan_with_unknown_arns" {
  command   = plan
  state_key = "alarms_unknown_arns"

  assert {
    condition     = length(module.alarms) == 1 && length(output.alarm_names) == 5
    error_message = "Alarm keys and names must be known at plan before the ARN suffixes."
  }
}

run "rejects_invalid_alarm_topic" {
  command = plan

  variables {
    alarms = { topic_arns = { critical = "arn:aws:sqs:eu-west-1:123456789012:core-prod-critical" } }
  }

  expect_failures = [var.alarms]
}
