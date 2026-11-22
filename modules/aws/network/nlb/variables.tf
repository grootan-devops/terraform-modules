variable "application" {
  description = "Application name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,23}$", var.application))
    error_message = "application: 2-24 chars, a-z 0-9 -, starts with a letter."
  }
}

variable "environment" {
  description = "Environment name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,11}$", var.environment))
    error_message = "environment: 2-12 chars, a-z 0-9 -, starts with a letter."
  }
}

variable "name" {
  description = "Load balancer name."
  type        = string
  default     = null

  validation {
    condition     = var.name == null || can(regex("^[a-z0-9][a-z0-9-]{0,31}$", var.name))
    error_message = "name: 1-32 chars, a-z 0-9 -."
  }
}

variable "tags" {
  description = "Extra tags; governance tags win."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "internal" {
  description = "Internal (true) or internet-facing (false)."
  type        = bool
  default     = true
  nullable    = false
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs in at least two AZs."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(distinct(var.subnet_ids)) >= 2
    error_message = "subnet_ids: at least two subnets (ELB.13)."
  }
}

variable "ip_address_type" {
  description = "ipv4 or dualstack."
  type        = string
  default     = "ipv4"
  nullable    = false

  validation {
    condition     = contains(["ipv4", "dualstack"], var.ip_address_type)
    error_message = "ip_address_type: ipv4 or dualstack."
  }
}

variable "static_ips" {
  description = "Elastic IP allocation IDs, one per subnet in subnet_ids order."
  type = object({
    allocation_ids = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = length(var.static_ips.allocation_ids) == 0 || (!var.internal && length(var.static_ips.allocation_ids) == length(var.subnet_ids))
    error_message = "static_ips: one allocation ID per subnet, internet-facing only."
  }
}

variable "security_group" {
  description = "Security group: listener sources, target destinations, extra groups."
  type = object({
    ingress_cidr_blocks           = optional(list(string), [])
    ingress_security_group_ids    = optional(list(string), [])
    ingress_prefix_list_ids       = optional(list(string), [])
    egress_cidr_blocks            = optional(list(string), [])
    egress_security_group_ids     = optional(list(string), [])
    additional_security_group_ids = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.internal || !anytrue([for c in var.security_group.ingress_cidr_blocks : contains(["0.0.0.0/0", "::/0"], c)])
    error_message = "security_group: 0.0.0.0/0 and ::/0 only when internal = false."
  }
}

variable "listeners" {
  description = "Listeners by key: port, protocol, target group key, TLS settings."
  type = map(object({
    port                        = number
    protocol                    = optional(string, "TCP")
    target_group                = string
    certificate_arn             = optional(string)
    additional_certificate_arns = optional(list(string), [])
    ssl_policy                  = optional(string, "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09")
    alpn_policy                 = optional(string)
    tcp_idle_timeout_seconds    = optional(number)
  }))
  nullable = false

  validation {
    condition     = length(var.listeners) > 0 && length(distinct([for l in values(var.listeners) : l.port])) == length(var.listeners) && alltrue([for l in values(var.listeners) : contains(["TCP", "UDP", "TCP_UDP", "TLS"], l.protocol) && l.port >= 1 && l.port <= 65535])
    error_message = "listeners: at least one; unique port 1-65535; protocol TCP, UDP, TCP_UDP or TLS."
  }

  validation {
    condition     = alltrue([for l in values(var.listeners) : try(contains({ TCP = ["TCP", "TCP_UDP"], TLS = ["TCP", "TLS"], UDP = ["UDP", "TCP_UDP"], TCP_UDP = ["TCP_UDP"] }[l.protocol], var.target_groups[l.target_group].protocol) && (var.target_groups[l.target_group].target_type != "alb" || l.protocol == "TCP"), false)])
    error_message = "listeners: target_group a target_groups key with a compatible protocol."
  }

  validation {
    condition     = alltrue([for l in values(var.listeners) : l.protocol == "TLS" ? l.certificate_arn != null : l.certificate_arn == null && length(l.additional_certificate_arns) == 0])
    error_message = "listeners: certificate_arn required on TLS listeners, not allowed on others."
  }

  validation {
    condition     = alltrue([for l in values(var.listeners) : contains(["ELBSecurityPolicy-TLS13-1-3-2021-06", "ELBSecurityPolicy-TLS13-1-3-FIPS-2023-04", "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09", "ELBSecurityPolicy-TLS13-1-3-PQ-2025-09", "ELBSecurityPolicy-TLS13-1-2-Res-FIPS-PQ-2025-09", "ELBSecurityPolicy-TLS13-1-3-FIPS-PQ-2025-09", "ELBSecurityPolicy-TLS13-1-2-RFC9151-FIPS-2023-07", "ELBSecurityPolicy-TLS13-1-2-RFC9151-INTEROP1-FIPS-2023-07", "ELBSecurityPolicy-TLS13-1-2-RFC9151-INTEROP2-FIPS-2023-07", "ELBSecurityPolicy-TLS13-1-3-RFC9151-FIPS-2023-07", "ELBSecurityPolicy-TLS13-1-2-FIPS-PQ-2025-09", "ELBSecurityPolicy-TLS13-1-2-PQ-2025-09"], l.ssl_policy)])
    error_message = "listeners.ssl_policy: an ELB.17 recommended policy."
  }

  validation {
    condition     = alltrue([for l in values(var.listeners) : l.alpn_policy == null || (l.protocol == "TLS" && contains(["HTTP1Only", "HTTP2Only", "HTTP2Optional", "HTTP2Preferred", "None"], coalesce(l.alpn_policy, "-")))])
    error_message = "listeners.alpn_policy: HTTP1Only, HTTP2Only, HTTP2Optional, HTTP2Preferred or None, TLS only."
  }

  validation {
    condition     = alltrue([for l in values(var.listeners) : l.tcp_idle_timeout_seconds == null || (contains(["TCP", "TLS"], l.protocol) && coalesce(l.tcp_idle_timeout_seconds, 0) >= 60 && coalesce(l.tcp_idle_timeout_seconds, 0) <= 6000)])
    error_message = "listeners.tcp_idle_timeout_seconds: 60-6000, TCP and TLS only."
  }
}

variable "target_groups" {
  description = "Target groups by key: port, protocol, target type, health check, static targets."
  type = map(object({
    port                   = number
    protocol               = optional(string, "TCP")
    target_type            = optional(string, "ip")
    deregistration_delay   = optional(number, 300)
    preserve_client_ip     = optional(bool)
    proxy_protocol_v2      = optional(bool, false)
    connection_termination = optional(bool, false)
    health_check = optional(object({
      protocol            = optional(string)
      port                = optional(string, "traffic-port")
      path                = optional(string, "/")
      matcher             = optional(string, "200-399")
      interval            = optional(number, 30)
      timeout             = optional(number)
      healthy_threshold   = optional(number, 3)
      unhealthy_threshold = optional(number, 3)
    }), {})
    targets = optional(map(object({
      id                = string
      port              = optional(number)
      availability_zone = optional(string)
    })), {})
  }))
  nullable = false

  validation {
    condition     = alltrue([for k in keys(var.target_groups) : can(regex("^[a-z0-9][a-z0-9-]{0,15}$", k))])
    error_message = "target_groups keys: 1-16 chars, a-z 0-9 -."
  }

  validation {
    condition     = alltrue([for t in values(var.target_groups) : contains(["TCP", "UDP", "TCP_UDP", "TLS"], t.protocol) && contains(["instance", "ip", "alb"], t.target_type) && t.port >= 1 && t.port <= 65535])
    error_message = "target_groups: protocol TCP, UDP, TCP_UDP or TLS; target_type instance, ip or alb; port 1-65535."
  }

  validation {
    condition     = alltrue([for t in values(var.target_groups) : t.target_type != "alb" || (t.protocol == "TCP" && contains(["HTTP", "HTTPS"], coalesce(t.health_check.protocol, "HTTP")) && length(t.targets) <= 1 && alltrue([for x in values(t.targets) : coalesce(x.port, t.port) == t.port]))])
    error_message = "target_groups: alb type needs TCP, an HTTP(S) health check, one target on the group port."
  }

  validation {
    condition     = alltrue([for t in values(var.target_groups) : !t.proxy_protocol_v2 || (t.target_type != "alb" && contains(["TCP", "TLS"], t.protocol))])
    error_message = "target_groups: proxy_protocol_v2 on TCP and TLS instance or ip groups only."
  }

  validation {
    condition     = alltrue([for t in values(var.target_groups) : contains(["TCP", "HTTP", "HTTPS"], coalesce(t.health_check.protocol, "TCP")) && (t.health_check.port == "traffic-port" || can(tonumber(t.health_check.port)))])
    error_message = "target_groups: health_check protocol TCP, HTTP or HTTPS; port traffic-port or a number."
  }

  validation {
    condition     = alltrue([for t in values(var.target_groups) : t.health_check.interval >= 5 && t.health_check.interval <= 300 && t.health_check.healthy_threshold >= 2 && t.health_check.healthy_threshold <= 10 && t.health_check.unhealthy_threshold >= 2 && t.health_check.unhealthy_threshold <= 10 && (t.health_check.timeout == null || (coalesce(t.health_check.timeout, 0) >= 2 && coalesce(t.health_check.timeout, 0) <= 120))])
    error_message = "target_groups: health_check interval 5-300, timeout 2-120, thresholds 2-10."
  }

  validation {
    condition     = alltrue([for t in values(var.target_groups) : t.deregistration_delay >= 0 && t.deregistration_delay <= 3600])
    error_message = "target_groups: deregistration_delay 0-3600."
  }
}

variable "access_logs" {
  description = "TLS listener access logs to an S3 bucket."
  type = object({
    enabled = optional(bool, false)
    bucket  = optional(string)
    prefix  = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.access_logs.enabled || var.access_logs.bucket != null
    error_message = "access_logs: set bucket."
  }
}

variable "endpoint_service" {
  description = "PrivateLink endpoint service."
  type = object({
    enabled             = optional(bool, false)
    allowed_principals  = optional(list(string), [])
    acceptance_required = optional(bool, true)
    private_dns_name    = optional(string)
    supported_regions   = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = !contains(var.endpoint_service.allowed_principals, "*")
    error_message = "endpoint_service.allowed_principals: ARNs, not *."
  }
}

variable "cross_zone_load_balancing" {
  description = "Cross-zone load balancing."
  type        = bool
  default     = true
  nullable    = false
}

variable "zonal_shift" {
  description = "Route 53 ARC zonal shift."
  type        = bool
  default     = true
  nullable    = false
}

variable "dns_record_client_routing_policy" {
  description = "DNS client routing policy."
  type        = string
  default     = "any_availability_zone"
  nullable    = false

  validation {
    condition     = contains(["any_availability_zone", "availability_zone_affinity", "partial_availability_zone_affinity"], var.dns_record_client_routing_policy)
    error_message = "dns_record_client_routing_policy: any_availability_zone, availability_zone_affinity or partial_availability_zone_affinity."
  }
}

variable "enforce_security_group_inbound_rules_on_private_link_traffic" {
  description = "Apply security group ingress to PrivateLink traffic: on or off."
  type        = string
  default     = "on"
  nullable    = false

  validation {
    condition     = contains(["on", "off"], var.enforce_security_group_inbound_rules_on_private_link_traffic)
    error_message = "enforce_security_group_inbound_rules_on_private_link_traffic: on or off."
  }
}

variable "deletion_protection" {
  description = "Block deletion of the load balancer."
  type        = bool
  default     = true
  nullable    = false
}

variable "alarms" {
  description = "Built-in CloudWatch alarms: switch, topics by severity, per-alarm overrides."
  type = object({
    enabled    = optional(bool, true)
    topic_arns = optional(map(string), {})
    overrides = optional(object({
      unhealthy_hosts  = optional(object({ enabled = optional(bool), threshold = optional(number), evaluation_periods = optional(number), datapoints_to_alarm = optional(number), period = optional(number), severity = optional(string) }), {})
      no_healthy_hosts = optional(object({ enabled = optional(bool), threshold = optional(number), evaluation_periods = optional(number), datapoints_to_alarm = optional(number), period = optional(number), severity = optional(string) }), {})
    }), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for s, arn in var.alarms.topic_arns : can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]+$", arn))])
    error_message = "alarms.topic_arns: SNS topic ARNs by severity."
  }
}
