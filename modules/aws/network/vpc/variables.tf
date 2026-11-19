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
  description = "VPC name."
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

variable "cidr_block" {
  description = "VPC IPv4 CIDR."
  type        = string

  validation {
    condition     = can(cidrhost(var.cidr_block, 0)) && can(regex("^[0-9.]+/(1[6-9]|2[0-8])$", var.cidr_block))
    error_message = "cidr_block: an IPv4 CIDR from /16 to /28."
  }

  validation {
    condition     = !can(regex("/(2[1-8])$", var.cidr_block)) || alltrue([for t in [var.public_subnets, var.private_subnets, var.intra_subnets] : !t.enabled || length(t.cidrs) > 0])
    error_message = "cidr_block: /16-/20 for computed subnets; set cidrs otherwise."
  }
}

variable "az_count" {
  description = "Availability Zones to use (1-6)."
  type        = number
  default     = 3
  nullable    = false

  validation {
    condition     = var.az_count >= 1 && var.az_count <= 6
    error_message = "az_count: 1-6."
  }
}

variable "azs" {
  description = "Availability Zone names. Empty: the first az_count zones."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = length(var.azs) <= 6 && length(distinct(var.azs)) == length(var.azs)
    error_message = "azs: up to 6 distinct zones."
  }
}

variable "public_subnets" {
  description = "Public tier: enabled, CIDRs (one per AZ; empty: computed)."
  type = object({
    enabled = optional(bool, true)
    cidrs   = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = length(var.public_subnets.cidrs) == 0 || length(var.public_subnets.cidrs) == (length(var.azs) > 0 ? length(var.azs) : var.az_count)
    error_message = "public_subnets.cidrs: one per AZ."
  }

  validation {
    condition     = alltrue([for c in var.public_subnets.cidrs : can(cidrhost(c, 0))])
    error_message = "public_subnets.cidrs: IPv4 CIDRs."
  }
}

variable "private_subnets" {
  description = "Private tier: enabled, CIDRs (one per AZ; empty: computed)."
  type = object({
    enabled = optional(bool, true)
    cidrs   = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = length(var.private_subnets.cidrs) == 0 || length(var.private_subnets.cidrs) == (length(var.azs) > 0 ? length(var.azs) : var.az_count)
    error_message = "private_subnets.cidrs: one per AZ."
  }

  validation {
    condition     = alltrue([for c in var.private_subnets.cidrs : can(cidrhost(c, 0))])
    error_message = "private_subnets.cidrs: IPv4 CIDRs."
  }
}

variable "intra_subnets" {
  description = "Intra tier (no internet route): enabled, CIDRs (one per AZ; empty: computed)."
  type = object({
    enabled = optional(bool, true)
    cidrs   = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = length(var.intra_subnets.cidrs) == 0 || length(var.intra_subnets.cidrs) == (length(var.azs) > 0 ? length(var.azs) : var.az_count)
    error_message = "intra_subnets.cidrs: one per AZ."
  }

  validation {
    condition     = alltrue([for c in var.intra_subnets.cidrs : can(cidrhost(c, 0))])
    error_message = "intra_subnets.cidrs: IPv4 CIDRs."
  }
}

variable "nat" {
  description = "NAT gateways: single, per_az or none."
  type = object({
    mode = optional(string, "single")
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["single", "per_az", "none"], var.nat.mode)
    error_message = "nat.mode: single, per_az or none."
  }

  validation {
    condition     = var.nat.mode == "none" || var.public_subnets.enabled
    error_message = "nat: needs public subnets."
  }
}

variable "nacl_rules" {
  description = "Extra network ACL rules by key; same tier, direction and number replaces a default."
  type = map(object({
    tier            = string
    rule_number     = number
    egress          = optional(bool, false)
    protocol        = optional(string, "tcp")
    action          = optional(string, "allow")
    cidr_block      = optional(string)
    ipv6_cidr_block = optional(string)
    from_port       = optional(number, 0)
    to_port         = optional(number, 0)
    icmp_type       = optional(number)
    icmp_code       = optional(number)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for r in values(var.nacl_rules) : contains(["public", "private", "intra"], r.tier) && r.rule_number >= 1 && r.rule_number <= 32766])
    error_message = "nacl_rules: tier public, private or intra; rule_number 1-32766."
  }

  validation {
    condition     = alltrue([for r in values(var.nacl_rules) : contains(["allow", "deny"], r.action) && contains(["tcp", "udp", "icmp", "icmpv6", "-1"], r.protocol)])
    error_message = "nacl_rules: action allow or deny; protocol tcp, udp, icmp, icmpv6 or -1."
  }

  validation {
    condition     = alltrue([for r in values(var.nacl_rules) : (r.cidr_block == null) != (r.ipv6_cidr_block == null)])
    error_message = "nacl_rules: set cidr_block or ipv6_cidr_block."
  }

  validation {
    condition     = length(distinct([for r in values(var.nacl_rules) : "${r.tier}-${r.egress}-${r.rule_number}"])) == length(var.nacl_rules)
    error_message = "nacl_rules: one rule per tier, direction and number."
  }

  validation {
    condition = !anytrue([
      for r in values(var.nacl_rules) : !r.egress && r.action == "allow" && contains(["0.0.0.0/0", "::/0"], coalesce(r.cidr_block, r.ipv6_cidr_block, "none")) && (
        r.protocol == "-1" || (contains(["tcp", "udp"], r.protocol) && ((r.from_port <= 22 && r.to_port >= 22) || (r.from_port <= 3389 && r.to_port >= 3389)))
      )
    ])
    error_message = "nacl_rules: no 22 or 3389 from 0.0.0.0/0 or ::/0 (EC2.21)."
  }
}

variable "routes" {
  description = "Extra routes by key: tiers, one destination, one target."
  type = map(object({
    tiers                       = optional(list(string), ["private", "intra"])
    destination_cidr_block      = optional(string)
    destination_ipv6_cidr_block = optional(string)
    destination_prefix_list_id  = optional(string)
    transit_gateway_id          = optional(string)
    vpc_peering_connection_id   = optional(string)
    network_interface_id        = optional(string)
    vpc_endpoint_id             = optional(string)
    gateway_id                  = optional(string)
    core_network_arn            = optional(string)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for r in values(var.routes) : length(r.tiers) > 0 && alltrue([for t in r.tiers : contains(["public", "private", "intra"], t)])])
    error_message = "routes[*].tiers: public, private or intra."
  }

  validation {
    condition     = alltrue([for r in values(var.routes) : length(compact([r.destination_cidr_block, r.destination_ipv6_cidr_block, r.destination_prefix_list_id])) == 1])
    error_message = "routes: set one destination."
  }

  validation {
    condition     = alltrue([for r in values(var.routes) : length(compact([r.transit_gateway_id, r.vpc_peering_connection_id, r.network_interface_id, r.vpc_endpoint_id, r.gateway_id, r.core_network_arn])) == 1])
    error_message = "routes: set one target."
  }
}

variable "flow_logs" {
  description = "VPC flow logs: destination cloudwatch or s3, traffic type, aggregation interval."
  type = object({
    enabled                  = optional(bool, true)
    destination              = optional(string, "cloudwatch")
    s3_bucket_arn            = optional(string)
    traffic_type             = optional(string, "ALL")
    max_aggregation_interval = optional(number, 600)
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["cloudwatch", "s3"], var.flow_logs.destination)
    error_message = "flow_logs.destination: cloudwatch or s3."
  }

  validation {
    condition     = var.flow_logs.destination != "s3" || var.flow_logs.s3_bucket_arn != null
    error_message = "flow_logs: s3 needs s3_bucket_arn."
  }

  validation {
    condition     = contains(["ALL", "ACCEPT", "REJECT"], var.flow_logs.traffic_type) && contains([60, 600], var.flow_logs.max_aggregation_interval)
    error_message = "flow_logs: traffic_type ALL, ACCEPT or REJECT; interval 60 or 600."
  }
}

variable "cloudwatch_logs" {
  description = "Flow log group (destination cloudwatch)."
  type = object({
    retention_in_days           = optional(number, 365)
    log_group_class             = optional(string, "STANDARD")
    deletion_protection_enabled = optional(bool, true)
    kms_key_arn                 = optional(string)
  })
  default  = {}
  nullable = false
}

variable "kms" {
  description = "Encryption: {} AWS managed key, create = true module key, key_id your key (ARN or ID)."
  type = object({
    key_id                  = optional(string)
    create                  = optional(bool, false)
    deletion_window_in_days = optional(number, 30)
    policy_statements = optional(list(object({
      sid        = optional(string)
      effect     = optional(string, "Allow")
      actions    = list(string)
      resources  = optional(list(string))
      principals = optional(map(list(string)), {})
      conditions = optional(list(object({
        test     = string
        variable = string
        values   = list(string)
      })), [])
    })), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = !(var.kms.create && var.kms.key_id != null)
    error_message = "kms: set create or key_id, not both."
  }

  validation {
    condition     = var.kms.key_id == null || can(regex("^(arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/)?(mrk-[a-f0-9]{32}|[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})$", var.kms.key_id))
    error_message = "kms.key_id: a KMS key ARN or key ID."
  }
}

variable "iam_role" {
  description = "Flow log role: extend it or bring your own."
  type = object({
    create                   = optional(bool, true)
    arn                      = optional(string)
    name                     = optional(string)
    path                     = optional(string, "/")
    permissions_boundary_arn = optional(string)
    managed_policy_arns      = optional(list(string), [])
    policy_statements = optional(list(object({
      sid        = optional(string)
      effect     = optional(string, "Allow")
      actions    = list(string)
      resources  = optional(list(string))
      principals = optional(map(list(string)), {})
      conditions = optional(list(object({
        test     = string
        variable = string
        values   = list(string)
      })), [])
    })), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.iam_role.create || var.iam_role.arn != null
    error_message = "iam_role: set arn when create = false."
  }
}

variable "vpc_endpoints" {
  description = "VPC endpoints by service (s3, ecr.api, ssm...): type, subnet tier, private DNS, policy."
  type = map(object({
    type                = optional(string, "Interface")
    service_name        = optional(string)
    subnet_tier         = optional(string, "private")
    private_dns_enabled = optional(bool, true)
    policy_statements = optional(list(object({
      sid        = optional(string)
      effect     = optional(string, "Allow")
      actions    = list(string)
      resources  = optional(list(string))
      principals = optional(map(list(string)), {})
      conditions = optional(list(object({
        test     = string
        variable = string
        values   = list(string)
      })), [])
    })), [])
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for e in values(var.vpc_endpoints) : contains(["Interface", "Gateway"], e.type)])
    error_message = "vpc_endpoints[*].type: Interface or Gateway."
  }

  validation {
    condition     = alltrue([for e in values(var.vpc_endpoints) : e.type == "Gateway" || contains(compact([var.public_subnets.enabled ? "public" : "", var.private_subnets.enabled ? "private" : "", var.intra_subnets.enabled ? "intra" : ""]), e.subnet_tier)])
    error_message = "vpc_endpoints[*].subnet_tier: an enabled tier."
  }
}

variable "dhcp_options" {
  description = "Custom DHCP option set."
  type = object({
    enabled              = optional(bool, false)
    domain_name          = optional(string)
    domain_name_servers  = optional(list(string), ["AmazonProvidedDNS"])
    ntp_servers          = optional(list(string), [])
    netbios_name_servers = optional(list(string), [])
    netbios_node_type    = optional(string)
  })
  default  = {}
  nullable = false
}

variable "alarms" {
  description = "Built-in CloudWatch alarms: switch, topics by severity, per-alarm overrides."
  type = object({
    enabled    = optional(bool, true)
    topic_arns = optional(map(string), {})
    overrides = optional(object({
      error_port_allocation = optional(object({ enabled = optional(bool), threshold = optional(number), evaluation_periods = optional(number), datapoints_to_alarm = optional(number), period = optional(number), severity = optional(string) }), {})
      packets_drop_rate     = optional(object({ enabled = optional(bool), threshold = optional(number), evaluation_periods = optional(number), datapoints_to_alarm = optional(number), period = optional(number), severity = optional(string) }), {})
    }), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for s, arn in var.alarms.topic_arns : can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]+$", arn))])
    error_message = "alarms.topic_arns: SNS topic ARNs by severity."
  }
}
