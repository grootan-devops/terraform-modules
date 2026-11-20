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

variable "security_group" {
  description = "Security group: listener sources, target destinations, extra groups."
  type = object({
    create                        = optional(bool, true)
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

  validation {
    condition     = var.security_group.create || length(var.security_group.additional_security_group_ids) > 0
    error_message = "security_group: set additional_security_group_ids when create = false."
  }
}

variable "https_listener" {
  description = "HTTPS listener: port, certificate, extra SNI certificates, TLS policy."
  type = object({
    enabled                     = optional(bool, true)
    port                        = optional(number, 443)
    certificate_arn             = optional(string)
    additional_certificate_arns = optional(list(string), [])
    ssl_policy                  = optional(string, "ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09")
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.https_listener.enabled || var.https_listener.certificate_arn != null
    error_message = "https_listener: set certificate_arn."
  }

  validation {
    condition     = contains(["ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09", "ELBSecurityPolicy-TLS13-1-2-PQ-2025-09", "ELBSecurityPolicy-TLS13-1-3-PQ-2025-09", "ELBSecurityPolicy-TLS13-1-3-2021-06", "ELBSecurityPolicy-TLS13-1-2-Res-FIPS-PQ-2025-09", "ELBSecurityPolicy-TLS13-1-2-FIPS-PQ-2025-09", "ELBSecurityPolicy-TLS13-1-3-FIPS-PQ-2025-09", "ELBSecurityPolicy-TLS13-1-3-FIPS-2023-04", "ELBSecurityPolicy-TLS13-1-2-RFC9151-FIPS-2023-07", "ELBSecurityPolicy-TLS13-1-2-RFC9151-INTEROP1-FIPS-2023-07", "ELBSecurityPolicy-TLS13-1-2-RFC9151-INTEROP2-FIPS-2023-07", "ELBSecurityPolicy-TLS13-1-3-RFC9151-FIPS-2023-07"], var.https_listener.ssl_policy)
    error_message = "https_listener.ssl_policy: a policy on the ELB.17 list."
  }
}

variable "http_listener" {
  description = "HTTP listener: redirects to HTTPS; forward = true serves plain HTTP."
  type = object({
    enabled = optional(bool, true)
    port    = optional(number, 80)
    forward = optional(bool, false)
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.http_listener.enabled || var.http_listener.forward || var.https_listener.enabled
    error_message = "http_listener: redirect needs https_listener."
  }

  validation {
    condition     = var.http_listener.enabled || var.https_listener.enabled
    error_message = "http_listener: enable at least one listener."
  }
}

variable "target_groups" {
  description = "Target groups by key: port, protocol, target type, health check."
  type = map(object({
    port                 = optional(number)
    protocol             = optional(string, "HTTP")
    target_type          = optional(string, "ip")
    deregistration_delay = optional(number, 300)
    health_check = optional(object({
      path                = optional(string, "/health")
      protocol            = optional(string)
      port                = optional(string, "traffic-port")
      matcher             = optional(string, "200")
      interval            = optional(number, 30)
      timeout             = optional(number, 5)
      healthy_threshold   = optional(number, 3)
      unhealthy_threshold = optional(number, 3)
    }), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k in keys(var.target_groups) : can(regex("^[a-z0-9][a-z0-9-]{0,15}$", k))])
    error_message = "target_groups keys: 1-16 chars, a-z 0-9 -."
  }

  validation {
    condition     = alltrue([for t in values(var.target_groups) : contains(["ip", "instance", "lambda"], t.target_type) && contains(["HTTP", "HTTPS"], t.protocol)])
    error_message = "target_groups: target_type ip, instance or lambda; protocol HTTP or HTTPS."
  }

  validation {
    condition     = alltrue([for t in values(var.target_groups) : t.target_type == "lambda" || t.port != null])
    error_message = "target_groups: port is required unless target_type = lambda."
  }

  validation {
    condition     = alltrue([for t in values(var.target_groups) : t.health_check.port == "traffic-port" || can(tonumber(t.health_check.port))])
    error_message = "target_groups: health_check.port is traffic-port or a number."
  }
}

variable "default_target_group" {
  description = "Target group key for the listener default action. Null: fixed 404."
  type        = string
  default     = null

  validation {
    condition     = var.default_target_group == null || contains(keys(var.target_groups), coalesce(var.default_target_group, "-"))
    error_message = "default_target_group: a target_groups key."
  }
}

variable "listener_rules" {
  description = "Listener rules by key: priority, target group, path and host conditions."
  type = map(object({
    priority      = number
    target_group  = string
    path_patterns = optional(list(string), [])
    host_headers  = optional(list(string), [])
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for r in values(var.listener_rules) : contains(keys(var.target_groups), r.target_group) && r.priority >= 1 && r.priority <= 50000])
    error_message = "listener_rules: target_group a target_groups key; priority 1-50000."
  }

  validation {
    condition     = alltrue([for r in values(var.listener_rules) : length(r.path_patterns) + length(r.host_headers) > 0])
    error_message = "listener_rules: set path_patterns or host_headers."
  }
}

variable "access_logs" {
  description = "Access and connection logs to an S3 bucket."
  type = object({
    enabled         = optional(bool, false)
    bucket          = optional(string)
    prefix          = optional(string)
    connection_logs = optional(bool, true)
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.access_logs.enabled || var.access_logs.bucket != null
    error_message = "access_logs: set bucket."
  }
}

variable "waf" {
  description = "REGIONAL WAF web ACL association."
  type = object({
    enabled     = optional(bool, false)
    web_acl_arn = optional(string)
    fail_open   = optional(bool, false)
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.waf.enabled || var.waf.web_acl_arn != null
    error_message = "waf: set web_acl_arn."
  }
}

variable "idle_timeout" {
  description = "Idle timeout in seconds (1-4000)."
  type        = number
  default     = 60
  nullable    = false

  validation {
    condition     = var.idle_timeout >= 1 && var.idle_timeout <= 4000
    error_message = "idle_timeout: 1-4000."
  }
}

variable "desync_mitigation_mode" {
  description = "Desync mitigation: defensive or strictest."
  type        = string
  default     = "defensive"
  nullable    = false

  validation {
    condition     = contains(["defensive", "strictest"], var.desync_mitigation_mode)
    error_message = "desync_mitigation_mode: defensive or strictest (ELB.12)."
  }
}

variable "deletion_protection" {
  description = "Block deletion of the load balancer."
  type        = bool
  default     = true
  nullable    = false
}
