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
      id         = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:loadbalancer/net/core-prod-nlb/50dc6c495c0c9188"
      arn        = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:loadbalancer/net/core-prod-nlb/50dc6c495c0c9188"
      arn_suffix = "net/core-prod-nlb/50dc6c495c0c9188"
      dns_name   = "core-prod-nlb-50dc6c495c0c9188.elb.eu-west-1.amazonaws.com"
      zone_id    = "Z2IFOLAFXWLO4F"
    }
  }

  mock_resource "aws_lb_target_group" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:targetgroup/core-prod-nlb-app/73e2d6bc24d8a067"
      arn_suffix = "targetgroup/core-prod-nlb-app/73e2d6bc24d8a067"
    }
  }

  mock_resource "aws_lb_listener" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:listener/net/core-prod-nlb/50dc6c495c0c9188/f2f7dc8efc522ab2"
    }
  }

  mock_resource "aws_security_group" {
    defaults = {
      id = "sg-0123456789abcdef0"
    }
  }

  mock_resource "aws_vpc_endpoint_service" {
    defaults = {
      id           = "vpce-svc-0123456789abcdef0"
      service_name = "com.amazonaws.vpce.eu-west-1.vpce-svc-0123456789abcdef0"
    }
  }
}

variables {
  application = "core"
  environment = "prod"
  vpc_id      = "vpc-0a1b2c3d4e5f67890"
  subnet_ids  = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  tags        = { Team = "platform" }
  listeners = {
    app = { port = 443, target_group = "app" }
  }
  target_groups = {
    app = { port = 8443 }
  }
}

run "default_internal_tcp" {
  command = plan

  assert {
    condition     = aws_lb.this.name == "core-prod-nlb" && aws_lb.this.internal && aws_lb.this.load_balancer_type == "network" && aws_lb.this.ip_address_type == "ipv4"
    error_message = "An internal network load balancer named <application>-<environment>."
  }

  assert {
    condition     = aws_lb.this.enable_deletion_protection && aws_lb.this.enable_cross_zone_load_balancing && aws_lb.this.enable_zonal_shift
    error_message = "Deletion protection (ELB.6), cross-zone load balancing and zonal shift are on."
  }

  assert {
    condition     = aws_lb.this.enforce_security_group_inbound_rules_on_private_link_traffic == "on" && aws_lb.this.dns_record_client_routing_policy == "any_availability_zone"
    error_message = "PrivateLink traffic meets the security group; AWS default DNS routing."
  }

  assert {
    condition     = toset(aws_lb.this.subnets) == toset(var.subnet_ids) && length(aws_lb.this.subnet_mapping) == 0
    error_message = "Without static IPs the load balancer uses subnets."
  }

  assert {
    condition     = aws_lb_listener.this["app"].port == 443 && aws_lb_listener.this["app"].protocol == "TCP" && aws_lb_listener.this["app"].certificate_arn == null && aws_lb_listener.this["app"].alpn_policy == null && aws_lb_listener.this["app"].default_action[0].type == "forward"
    error_message = "A TCP listener forwards without TLS settings."
  }

  assert {
    condition     = aws_lb_target_group.this["app"].name == "core-prod-nlb-app" && aws_lb_target_group.this["app"].protocol == "TCP" && aws_lb_target_group.this["app"].target_type == "ip" && aws_lb_target_group.this["app"].port == 8443 && aws_lb_target_group.this["app"].vpc_id == "vpc-0a1b2c3d4e5f67890"
    error_message = "Target groups are named per key, TCP and ip by default."
  }

  assert {
    condition     = aws_lb_target_group.this["app"].health_check[0].protocol == "TCP" && aws_lb_target_group.this["app"].health_check[0].port == "traffic-port" && aws_lb_target_group.this["app"].health_check[0].enabled
    error_message = "TCP health check on the traffic port."
  }

  assert {
    condition     = aws_lb_target_group.this["app"].proxy_protocol_v2 == false && aws_lb_target_group.this["app"].connection_termination == false && aws_lb_target_group.this["app"].deregistration_delay == "300"
    error_message = "No proxy protocol or connection termination; 300 s deregistration delay."
  }

  assert {
    condition     = length(module.security_group.ingress_rule_ids) == 0 && length(module.security_group.egress_rule_ids) > 0 && alltrue([for k in keys(module.security_group.egress_rule_ids) : startswith(k, "vpc-")])
    error_message = "No ingress until sources are listed; egress only to target ports in the VPC."
  }

  assert {
    condition     = length(aws_lb.this.access_logs) == 0 && length(aws_vpc_endpoint_service.this) == 0 && length(aws_lb_listener_certificate.this) == 0 && length(aws_lb_target_group_attachment.this) == 0
    error_message = "No access logs, endpoint service, extra certificates or static targets by default."
  }

  assert {
    condition     = aws_lb.this.tags["Name"] == "core-prod-nlb" && aws_lb.this.tags["Team"] == "platform" && aws_lb.this.tags["ManagedBy"] == "Terraform" && aws_lb_listener.this["app"].tags["Name"] == "core-prod-nlb-app" && aws_lb_target_group.this["app"].tags["Application"] == "core"
    error_message = "Caller and governance tags must be applied."
  }
}

run "tls_listener" {
  command = plan

  variables {
    listeners = {
      tls = {
        port                        = 443
        protocol                    = "TLS"
        target_group                = "app"
        certificate_arn             = "arn:aws:acm:eu-west-1:123456789012:certificate/11111111-2222-3333-4444-555555555555"
        additional_certificate_arns = ["arn:aws:acm:eu-west-1:123456789012:certificate/22222222-2222-3333-4444-555555555555", "arn:aws:acm:eu-west-1:123456789012:certificate/33333333-2222-3333-4444-555555555555"]
        alpn_policy                 = "HTTP2Preferred"
        tcp_idle_timeout_seconds    = 600
      }
    }
    target_groups = {
      app = { port = 8443, protocol = "TLS", health_check = { protocol = "HTTPS", path = "/health" } }
    }
  }

  assert {
    condition     = aws_lb_listener.this["tls"].protocol == "TLS" && aws_lb_listener.this["tls"].ssl_policy == "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09" && aws_lb_listener.this["tls"].certificate_arn == "arn:aws:acm:eu-west-1:123456789012:certificate/11111111-2222-3333-4444-555555555555"
    error_message = "TLS listeners use the ELB.17 default policy and the certificate."
  }

  assert {
    condition     = aws_lb_listener.this["tls"].alpn_policy == "HTTP2Preferred" && aws_lb_listener.this["tls"].tcp_idle_timeout_seconds == 600
    error_message = "ALPN policy and TCP idle timeout are passed through."
  }

  assert {
    condition     = keys(aws_lb_listener_certificate.this) == ["tls/0", "tls/1"] && aws_lb_listener_certificate.this["tls/1"].certificate_arn == "arn:aws:acm:eu-west-1:123456789012:certificate/33333333-2222-3333-4444-555555555555"
    error_message = "Extra certificates are attached to the TLS listener."
  }

  assert {
    condition     = aws_lb_target_group.this["app"].protocol == "TLS" && aws_lb_target_group.this["app"].health_check[0].protocol == "HTTPS" && aws_lb_target_group.this["app"].health_check[0].path == "/health" && aws_lb_target_group.this["app"].health_check[0].matcher == "200-399"
    error_message = "TLS targets with an HTTPS health check (ELB.21, ELB.22)."
  }
}

run "other_tls_policy" {
  command = plan

  variables {
    listeners = {
      tls = { port = 443, protocol = "TLS", target_group = "app", certificate_arn = "arn:aws:acm:eu-west-1:123456789012:certificate/11111111-2222-3333-4444-555555555555", ssl_policy = "ELBSecurityPolicy-TLS13-1-3-FIPS-PQ-2025-09" }
    }
  }

  assert {
    condition     = aws_lb_listener.this["tls"].ssl_policy == "ELBSecurityPolicy-TLS13-1-3-FIPS-PQ-2025-09"
    error_message = "Any ELB.17 policy is accepted."
  }
}

run "udp_and_tcp_udp_listeners" {
  command = plan

  variables {
    listeners = {
      dns = { port = 53, protocol = "UDP", target_group = "dns" }
      vpn = { port = 1194, protocol = "TCP_UDP", target_group = "vpn" }
    }
    target_groups = {
      dns = { port = 53, protocol = "UDP", connection_termination = true }
      vpn = { port = 1194, protocol = "TCP_UDP", target_type = "instance", health_check = { port = "8080" } }
    }
    security_group = {
      ingress_cidr_blocks       = ["10.0.0.0/8"]
      egress_security_group_ids = ["sg-0ccccccccccccccc0"]
    }
  }

  assert {
    condition     = aws_lb_listener.this["dns"].protocol == "UDP" && aws_lb_listener.this["vpn"].protocol == "TCP_UDP"
    error_message = "UDP and TCP_UDP listeners."
  }

  assert {
    condition     = keys(module.security_group.ingress_rule_ids) == ["cidr-0-tcp-1194", "cidr-0-udp-1194", "cidr-0-udp-53"]
    error_message = "Ingress per listener port and IP protocol."
  }

  assert {
    condition     = keys(module.security_group.egress_rule_ids) == ["sg-0-tcp-1194", "sg-0-tcp-53", "sg-0-tcp-8080", "sg-0-udp-1194", "sg-0-udp-53"]
    error_message = "Egress to targets per protocol, plus TCP health checks."
  }

  assert {
    condition     = aws_lb_target_group.this["dns"].proxy_protocol_v2 == null && aws_lb_target_group.this["dns"].connection_termination && aws_lb_target_group.this["vpn"].target_type == "instance" && aws_lb_target_group.this["vpn"].health_check[0].port == "8080"
    error_message = "No proxy protocol on UDP groups; connection termination and health check port are passed through."
  }
}

run "alb_target_type" {
  command = plan

  variables {
    target_groups = {
      app = {
        port        = 443
        target_type = "alb"
        targets     = { web = { id = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:loadbalancer/app/core-prod-web/1234567890abcdef" } }
      }
    }
  }

  assert {
    condition     = aws_lb_target_group.this["app"].target_type == "alb" && aws_lb_target_group.this["app"].protocol == "TCP" && aws_lb_target_group.this["app"].health_check[0].protocol == "HTTP" && aws_lb_target_group.this["app"].health_check[0].path == "/" && aws_lb_target_group.this["app"].health_check[0].matcher == "200-399"
    error_message = "alb target groups are TCP with an HTTP health check."
  }

  assert {
    condition     = aws_lb_target_group.this["app"].proxy_protocol_v2 == null
    error_message = "No proxy protocol on alb target groups."
  }

  assert {
    condition     = aws_lb_target_group_attachment.this["app/web"].target_id == "arn:aws:elasticloadbalancing:eu-west-1:123456789012:loadbalancer/app/core-prod-web/1234567890abcdef" && aws_lb_target_group_attachment.this["app/web"].port == null
    error_message = "The ALB is registered on the target group port."
  }
}

run "static_targets" {
  command = plan

  variables {
    target_groups = {
      app = {
        port               = 8443
        preserve_client_ip = false
        proxy_protocol_v2  = true
        targets = {
          a = { id = "10.0.1.10" }
          b = { id = "192.168.1.10", port = 9443, availability_zone = "all" }
        }
      }
    }
  }

  assert {
    condition     = keys(aws_lb_target_group_attachment.this) == ["app/a", "app/b"] && aws_lb_target_group_attachment.this["app/b"].port == 9443 && aws_lb_target_group_attachment.this["app/b"].availability_zone == "all" && aws_lb_target_group_attachment.this["app/a"].port == null
    error_message = "Static targets are registered with optional port and AZ."
  }

  assert {
    condition     = aws_lb_target_group.this["app"].preserve_client_ip == "false" && aws_lb_target_group.this["app"].proxy_protocol_v2
    error_message = "Client IP preservation and proxy protocol are passed through."
  }
}

run "static_ips_internet_facing" {
  command = plan

  variables {
    internal        = false
    ip_address_type = "dualstack"
    static_ips      = { allocation_ids = ["eipalloc-0aaaaaaaaaaaaaaa0", "eipalloc-0bbbbbbbbbbbbbbb0"] }
  }

  assert {
    condition     = !aws_lb.this.internal && aws_lb.this.ip_address_type == "dualstack"
    error_message = "internal = false makes the load balancer internet-facing."
  }

  assert {
    condition     = toset([for m in aws_lb.this.subnet_mapping : "${m.subnet_id}=${m.allocation_id}"]) == toset(["subnet-0123456789abcdef0=eipalloc-0aaaaaaaaaaaaaaa0", "subnet-0fedcba9876543210=eipalloc-0bbbbbbbbbbbbbbb0"])
    error_message = "One Elastic IP per subnet, by index."
  }
}

run "security_group_sources" {
  command = plan

  variables {
    internal = false
    listeners = {
      app = { port = 443, target_group = "app" }
      dns = { port = 53, protocol = "UDP", target_group = "dns" }
    }
    target_groups = {
      app = { port = 8443, health_check = { port = "8081" } }
      dns = { port = 53, protocol = "UDP" }
    }
    security_group = {
      ingress_cidr_blocks        = ["0.0.0.0/0", "::/0"]
      ingress_security_group_ids = ["sg-0aaaaaaaaaaaaaaa0"]
      ingress_prefix_list_ids    = ["pl-0bbbbbbbbbbbbbbbb"]
      egress_cidr_blocks         = ["10.0.0.0/16"]
    }
  }

  assert {
    condition     = keys(module.security_group.ingress_rule_ids) == ["cidr-0-tcp-443", "cidr-0-udp-53", "cidr-1-tcp-443", "cidr-1-udp-53", "pl-0-tcp-443", "pl-0-udp-53", "sg-0-tcp-443", "sg-0-udp-53"]
    error_message = "Every listener port is opened to every listed source, including /0 on an internet-facing NLB."
  }

  assert {
    condition     = keys(module.security_group.egress_rule_ids) == ["cidr-0-tcp-53", "cidr-0-tcp-8081", "cidr-0-tcp-8443", "cidr-0-udp-53"]
    error_message = "Egress only on target and health check ports to the listed CIDRs."
  }
}

run "access_logs" {
  command = plan

  variables {
    access_logs = { enabled = true, bucket = "core-prod-logs-123456789012-eu-west-1", prefix = "nlb" }
  }

  assert {
    condition     = aws_lb.this.access_logs[0].enabled && aws_lb.this.access_logs[0].bucket == "core-prod-logs-123456789012-eu-west-1" && aws_lb.this.access_logs[0].prefix == "nlb"
    error_message = "Access logs go to the given bucket and prefix."
  }
}

run "endpoint_service" {
  command = plan

  variables {
    endpoint_service = {
      enabled            = true
      allowed_principals = ["arn:aws:iam::210987654321:root"]
      private_dns_name   = "api.example.com"
      supported_regions  = ["eu-west-1", "eu-central-1"]
    }
  }

  assert {
    condition     = aws_vpc_endpoint_service.this[0].acceptance_required && toset(aws_vpc_endpoint_service.this[0].allowed_principals) == toset(["arn:aws:iam::210987654321:root"]) && aws_vpc_endpoint_service.this[0].private_dns_name == "api.example.com"
    error_message = "Endpoint service requires acceptance and allows only the listed principals."
  }

  assert {
    condition     = toset(aws_vpc_endpoint_service.this[0].supported_regions) == toset(["eu-west-1", "eu-central-1"]) && aws_vpc_endpoint_service.this[0].tags["Name"] == "core-prod-nlb" && aws_vpc_endpoint_service.this[0].tags["ManagedBy"] == "Terraform"
    error_message = "Supported Regions and governance tags (EC2.47)."
  }
}

run "settings" {
  command = plan

  variables {
    deletion_protection                                          = false
    cross_zone_load_balancing                                    = false
    zonal_shift                                                  = false
    dns_record_client_routing_policy                             = "availability_zone_affinity"
    enforce_security_group_inbound_rules_on_private_link_traffic = "off"
  }

  assert {
    condition     = !aws_lb.this.enable_deletion_protection && !aws_lb.this.enable_cross_zone_load_balancing && !aws_lb.this.enable_zonal_shift
    error_message = "Deletion protection, cross-zone and zonal shift can be turned off."
  }

  assert {
    condition     = aws_lb.this.dns_record_client_routing_policy == "availability_zone_affinity" && aws_lb.this.enforce_security_group_inbound_rules_on_private_link_traffic == "off"
    error_message = "DNS routing policy and PrivateLink enforcement are passed through."
  }
}

run "long_names_are_truncated" {
  command = plan

  variables {
    name          = "customer-facing-storefront"
    listeners     = { app = { port = 443, target_group = "checkout-api" } }
    target_groups = { checkout-api = { port = 8443 } }
  }

  assert {
    condition     = length(aws_lb.this.name) == 32 && startswith(aws_lb.this.name, "core-prod-customer-facing-") && length(aws_lb_target_group.this["checkout-api"].name) == 32 && aws_lb_target_group.this["checkout-api"].name != aws_lb.this.name
    error_message = "Names over 32 characters are cut with a hash suffix."
  }

  assert {
    condition     = aws_lb.this.tags["Name"] == aws_lb.this.name && aws_lb.this.tags["Environment"] == "prod"
    error_message = "The Name tag follows the truncated name."
  }
}

run "outputs" {
  command = apply

  variables {
    listeners = {
      tls = { port = 443, protocol = "TLS", target_group = "app", certificate_arn = "arn:aws:acm:eu-west-1:123456789012:certificate/11111111-2222-3333-4444-555555555555", additional_certificate_arns = ["arn:aws:acm:eu-west-1:123456789012:certificate/22222222-2222-3333-4444-555555555555"] }
    }
    target_groups = {
      app = { port = 8443, targets = { a = { id = "10.0.1.10" } } }
    }
    security_group = { additional_security_group_ids = ["sg-0ddddddddddddddd0"] }
  }

  assert {
    condition     = output.id == output.arn && output.arn == "arn:aws:elasticloadbalancing:eu-west-1:123456789012:loadbalancer/net/core-prod-nlb/50dc6c495c0c9188" && output.arn_suffix == "net/core-prod-nlb/50dc6c495c0c9188" && output.name == "core-prod-nlb"
    error_message = "Load balancer identity outputs."
  }

  assert {
    condition     = output.dns_name == "core-prod-nlb-50dc6c495c0c9188.elb.eu-west-1.amazonaws.com" && output.zone_id == "Z2IFOLAFXWLO4F"
    error_message = "DNS outputs for alias records."
  }

  assert {
    condition     = output.security_group_id == "sg-0123456789abcdef0" && toset(aws_lb.this.security_groups) == toset(["sg-0123456789abcdef0", "sg-0ddddddddddddddd0"])
    error_message = "The module security group is always attached, plus the extra groups."
  }

  assert {
    condition     = output.listener_arns["tls"] == aws_lb_listener.this["tls"].arn && output.target_group_arns["app"] == aws_lb_target_group.this["app"].arn && output.target_group_arn_suffixes["app"] == "targetgroup/core-prod-nlb-app/73e2d6bc24d8a067"
    error_message = "Listener and target group outputs are wired."
  }

  assert {
    condition     = aws_lb_listener.this["tls"].load_balancer_arn == aws_lb.this.arn && aws_lb_listener.this["tls"].default_action[0].target_group_arn == aws_lb_target_group.this["app"].arn
    error_message = "The listener forwards to its target group."
  }

  assert {
    condition     = aws_lb_listener_certificate.this["tls/0"].listener_arn == aws_lb_listener.this["tls"].arn && aws_lb_target_group_attachment.this["app/a"].target_group_arn == aws_lb_target_group.this["app"].arn
    error_message = "Certificates and targets attach to the module listener and target group."
  }

  assert {
    condition     = output.endpoint_service_name == null && output.endpoint_service_id == null
    error_message = "No endpoint service outputs when disabled."
  }
}

run "endpoint_service_outputs" {
  command   = apply
  state_key = "endpoint"

  variables {
    endpoint_service = { enabled = true, allowed_principals = ["arn:aws:iam::210987654321:root"] }
  }

  assert {
    condition     = output.endpoint_service_name == "com.amazonaws.vpce.eu-west-1.vpce-svc-0123456789abcdef0" && output.endpoint_service_id == "vpce-svc-0123456789abcdef0"
    error_message = "Endpoint service outputs."
  }

  assert {
    condition     = toset(aws_vpc_endpoint_service.this[0].network_load_balancer_arns) == toset([aws_lb.this.arn])
    error_message = "The endpoint service fronts this load balancer."
  }
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

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Edge_NLB"
  }

  expect_failures = [var.name]
}

run "rejects_single_subnet" {
  command = plan

  variables {
    subnet_ids = ["subnet-0123456789abcdef0"]
  }

  expect_failures = [var.subnet_ids]
}

run "rejects_invalid_ip_address_type" {
  command = plan

  variables {
    ip_address_type = "dualstack-without-public-ipv4"
  }

  expect_failures = [var.ip_address_type]
}

run "rejects_static_ips_on_internal" {
  command = plan

  variables {
    static_ips = { allocation_ids = ["eipalloc-0aaaaaaaaaaaaaaa0", "eipalloc-0bbbbbbbbbbbbbbb0"] }
  }

  expect_failures = [var.static_ips]
}

run "rejects_static_ips_count_mismatch" {
  command = plan

  variables {
    internal   = false
    static_ips = { allocation_ids = ["eipalloc-0aaaaaaaaaaaaaaa0"] }
  }

  expect_failures = [var.static_ips]
}

run "rejects_open_ingress_on_internal" {
  command = plan

  variables {
    security_group = { ingress_cidr_blocks = ["::/0"] }
  }

  expect_failures = [var.security_group]
}

run "rejects_no_listener" {
  command = plan

  variables {
    listeners = {}
  }

  expect_failures = [var.listeners]
}

run "rejects_duplicate_listener_port" {
  command = plan

  variables {
    listeners = {
      app = { port = 443, target_group = "app" }
      tls = { port = 443, protocol = "TLS", target_group = "app", certificate_arn = "arn:aws:acm:eu-west-1:123456789012:certificate/11111111-2222-3333-4444-555555555555" }
    }
  }

  expect_failures = [var.listeners]
}

run "rejects_invalid_listener_protocol" {
  command = plan

  variables {
    listeners = { app = { port = 80, protocol = "HTTP", target_group = "app" } }
  }

  expect_failures = [var.listeners]
}

run "rejects_unknown_target_group" {
  command = plan

  variables {
    listeners = { app = { port = 443, target_group = "web" } }
  }

  expect_failures = [var.listeners]
}

run "rejects_incompatible_target_group_protocol" {
  command = plan

  variables {
    listeners = { dns = { port = 53, protocol = "UDP", target_group = "app" } }
  }

  expect_failures = [var.listeners]
}

run "rejects_tls_listener_without_certificate" {
  command = plan

  variables {
    listeners = { tls = { port = 443, protocol = "TLS", target_group = "app" } }
  }

  expect_failures = [var.listeners]
}

run "rejects_certificate_on_tcp_listener" {
  command = plan

  variables {
    listeners = { app = { port = 443, target_group = "app", additional_certificate_arns = ["arn:aws:acm:eu-west-1:123456789012:certificate/22222222-2222-3333-4444-555555555555"] } }
  }

  expect_failures = [var.listeners]
}

run "rejects_old_tls_policy" {
  command = plan

  variables {
    listeners = { tls = { port = 443, protocol = "TLS", target_group = "app", certificate_arn = "arn:aws:acm:eu-west-1:123456789012:certificate/11111111-2222-3333-4444-555555555555", ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06" } }
  }

  expect_failures = [var.listeners]
}

run "rejects_alpn_on_tcp_listener" {
  command = plan

  variables {
    listeners = { app = { port = 443, target_group = "app", alpn_policy = "HTTP2Preferred" } }
  }

  expect_failures = [var.listeners]
}

run "rejects_tcp_idle_timeout_on_udp_listener" {
  command = plan

  variables {
    listeners     = { dns = { port = 53, protocol = "UDP", target_group = "dns", tcp_idle_timeout_seconds = 350 } }
    target_groups = { dns = { port = 53, protocol = "UDP" } }
  }

  expect_failures = [var.listeners]
}

run "rejects_invalid_target_group_key" {
  command = plan

  variables {
    listeners     = { app = { port = 443, target_group = "App_1" } }
    target_groups = { App_1 = { port = 8443 } }
  }

  expect_failures = [var.target_groups]
}

run "rejects_invalid_target_type" {
  command = plan

  variables {
    target_groups = { app = { port = 8443, target_type = "lambda" } }
  }

  expect_failures = [var.target_groups]
}

run "rejects_alb_target_with_other_port" {
  command = plan

  variables {
    target_groups = {
      app = {
        port        = 443
        target_type = "alb"
        targets     = { web = { id = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:loadbalancer/app/core-prod-web/1234567890abcdef", port = 8443 } }
      }
    }
  }

  expect_failures = [var.target_groups]
}

run "rejects_proxy_protocol_on_udp" {
  command = plan

  variables {
    listeners     = { dns = { port = 53, protocol = "UDP", target_group = "dns" } }
    target_groups = { dns = { port = 53, protocol = "UDP", proxy_protocol_v2 = true } }
  }

  expect_failures = [var.target_groups]
}

run "rejects_invalid_health_check_protocol" {
  command = plan

  variables {
    target_groups = { app = { port = 8443, health_check = { protocol = "UDP" } } }
  }

  expect_failures = [var.target_groups]
}

run "rejects_invalid_health_check_port" {
  command = plan

  variables {
    target_groups = { app = { port = 8443, health_check = { port = "http" } } }
  }

  expect_failures = [var.target_groups]
}

run "rejects_invalid_health_check_interval" {
  command = plan

  variables {
    target_groups = { app = { port = 8443, health_check = { interval = 1 } } }
  }

  expect_failures = [var.target_groups]
}

run "rejects_invalid_deregistration_delay" {
  command = plan

  variables {
    target_groups = { app = { port = 8443, deregistration_delay = 4000 } }
  }

  expect_failures = [var.target_groups]
}

run "rejects_access_logs_without_bucket" {
  command = plan

  variables {
    access_logs = { enabled = true }
  }

  expect_failures = [var.access_logs]
}

run "rejects_wildcard_endpoint_principal" {
  command = plan

  variables {
    endpoint_service = { enabled = true, allowed_principals = ["*"] }
  }

  expect_failures = [var.endpoint_service]
}

run "rejects_invalid_dns_routing_policy" {
  command = plan

  variables {
    dns_record_client_routing_policy = "nearest"
  }

  expect_failures = [var.dns_record_client_routing_policy]
}

run "rejects_invalid_private_link_enforcement" {
  command = plan

  variables {
    enforce_security_group_inbound_rules_on_private_link_traffic = "true"
  }

  expect_failures = [var.enforce_security_group_inbound_rules_on_private_link_traffic]
}
