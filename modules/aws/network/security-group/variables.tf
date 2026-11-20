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
  description = "Instance name."
  type        = string
  default     = null

  validation {
    condition     = var.name == null || can(regex("^[a-z0-9][a-z0-9-]{0,31}$", var.name))
    error_message = "name: 1-32 chars, a-z 0-9 -."
  }
}

variable "purpose" {
  description = "Group purpose, appended to the name."
  type        = string
  default     = null

  validation {
    condition     = var.purpose == null || can(regex("^[a-z0-9][a-z0-9-]{0,31}$", var.purpose))
    error_message = "purpose: 1-32 chars, a-z 0-9 -."
  }

  validation {
    condition     = var.purpose != null || var.name != null
    error_message = "Set name, purpose or both."
  }
}

variable "tags" {
  description = "Extra tags; governance tags win."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "description" {
  description = "Group description."
  type        = string
  default     = null
}

variable "ingress_rules" {
  description = "Ingress rules by key; one source per rule."
  type = map(object({
    description                  = string
    ip_protocol                  = optional(string, "tcp")
    from_port                    = optional(number)
    to_port                      = optional(number)
    cidr_ipv4                    = optional(string)
    cidr_ipv6                    = optional(string)
    prefix_list_id               = optional(string)
    referenced_security_group_id = optional(string)
    self                         = optional(bool, false)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for r in values(var.ingress_rules) : length(compact([r.cidr_ipv4, r.cidr_ipv6, r.prefix_list_id, r.referenced_security_group_id])) + (r.self ? 1 : 0) == 1])
    error_message = "ingress_rules: set exactly one of cidr_ipv4, cidr_ipv6, prefix_list_id, referenced_security_group_id, self."
  }

  validation {
    condition     = alltrue([for r in values(var.ingress_rules) : contains(["tcp", "udp", "icmp", "icmpv6", "-1"], r.ip_protocol)])
    error_message = "ingress_rules: ip_protocol must be tcp, udp, icmp, icmpv6 or -1."
  }

  validation {
    condition     = alltrue([for r in values(var.ingress_rules) : r.ip_protocol == "-1" || (r.from_port != null && r.to_port != null)])
    error_message = "ingress_rules: from_port and to_port are required unless ip_protocol is -1."
  }

  validation {
    condition     = var.allow_public_ingress || alltrue([for r in values(var.ingress_rules) : !contains(["0.0.0.0/0", "::/0"], coalesce(r.cidr_ipv4, r.cidr_ipv6, "none"))])
    error_message = "ingress_rules: 0.0.0.0/0 and ::/0 need allow_public_ingress = true."
  }
}

variable "egress_rules" {
  description = "Egress rules by key; one destination per rule."
  type = map(object({
    description                  = string
    ip_protocol                  = optional(string, "tcp")
    from_port                    = optional(number)
    to_port                      = optional(number)
    cidr_ipv4                    = optional(string)
    cidr_ipv6                    = optional(string)
    prefix_list_id               = optional(string)
    referenced_security_group_id = optional(string)
    self                         = optional(bool, false)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for r in values(var.egress_rules) : length(compact([r.cidr_ipv4, r.cidr_ipv6, r.prefix_list_id, r.referenced_security_group_id])) + (r.self ? 1 : 0) == 1])
    error_message = "egress_rules: set exactly one of cidr_ipv4, cidr_ipv6, prefix_list_id, referenced_security_group_id, self."
  }

  validation {
    condition     = alltrue([for r in values(var.egress_rules) : contains(["tcp", "udp", "icmp", "icmpv6", "-1"], r.ip_protocol)])
    error_message = "egress_rules: ip_protocol must be tcp, udp, icmp, icmpv6 or -1."
  }

  validation {
    condition     = alltrue([for r in values(var.egress_rules) : r.ip_protocol == "-1" || (r.from_port != null && r.to_port != null)])
    error_message = "egress_rules: from_port and to_port are required unless ip_protocol is -1."
  }
}

variable "allow_public_ingress" {
  description = "Allow ingress from 0.0.0.0/0 or ::/0 (internet-facing load balancers only)."
  type        = bool
  default     = false
  nullable    = false
}
