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
  description = "Zone instance name."
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

variable "zone_name" {
  description = "Domain name of the hosted zone."
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", var.zone_name)) && length(var.zone_name) <= 200
    error_message = "zone_name: a lower-case domain name without a trailing dot."
  }
}

variable "comment" {
  description = "Zone comment."
  type        = string
  default     = null
}

variable "vpc_ids" {
  description = "VPC IDs for a private zone. Empty: public zone."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "records" {
  description = "Records by key: name relative to the zone (\"\" apex), type, TTL and values or alias, failover."
  type = map(object({
    name    = optional(string, "")
    type    = string
    ttl     = optional(number, 300)
    records = optional(list(string), [])
    alias = optional(object({
      name                   = string
      zone_id                = string
      evaluate_target_health = optional(bool, false)
    }))
    set_identifier = optional(string)
    failover       = optional(string)
    health_check   = optional(string)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for r in values(var.records) : contains(["A", "AAAA", "CAA", "CNAME", "DS", "HTTPS", "MX", "NAPTR", "NS", "PTR", "SPF", "SRV", "SSHFP", "SVCB", "TLSA", "TXT"], r.type)])
    error_message = "records[*].type: a Route 53 record type."
  }

  validation {
    condition     = alltrue([for r in values(var.records) : (r.alias == null) == (length(r.records) > 0)])
    error_message = "records: set records or alias."
  }

  validation {
    condition     = alltrue([for r in values(var.records) : r.failover == null || (contains(["PRIMARY", "SECONDARY"], coalesce(r.failover, "-")) && r.set_identifier != null)])
    error_message = "records: failover PRIMARY or SECONDARY with set_identifier."
  }

  validation {
    condition     = alltrue([for r in values(var.records) : r.health_check == null || contains(keys(var.health_checks), coalesce(r.health_check, "-"))])
    error_message = "records: health_check a health_checks key."
  }
}

variable "health_checks" {
  description = "Health checks by key: type, endpoint, path, thresholds."
  type = map(object({
    type              = optional(string, "HTTPS")
    fqdn              = optional(string)
    ip_address        = optional(string)
    port              = optional(number)
    resource_path     = optional(string, "/")
    search_string     = optional(string)
    failure_threshold = optional(number, 3)
    request_interval  = optional(number, 30)
    measure_latency   = optional(bool, false)
    regions           = optional(list(string))
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for h in values(var.health_checks) : contains(["HTTP", "HTTPS", "HTTP_STR_MATCH", "HTTPS_STR_MATCH", "TCP"], h.type) && (h.fqdn != null || h.ip_address != null)])
    error_message = "health_checks: type HTTP, HTTPS, HTTP_STR_MATCH, HTTPS_STR_MATCH or TCP; set fqdn or ip_address."
  }

  validation {
    condition     = alltrue([for h in values(var.health_checks) : contains([10, 30], h.request_interval) && h.failure_threshold >= 1 && h.failure_threshold <= 10])
    error_message = "health_checks: request_interval 10 or 30; failure_threshold 1-10."
  }
}

variable "cloudwatch_logs" {
  description = "Query log group in us-east-1 (public zones)."
  type = object({
    retention_in_days           = optional(number, 365)
    log_group_class             = optional(string, "STANDARD")
    deletion_protection_enabled = optional(bool, true)
    kms_key_arn                 = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.cloudwatch_logs.kms_key_arn == null || can(regex("^arn:aws[a-z-]*:kms:us-east-1:", var.cloudwatch_logs.kms_key_arn))
    error_message = "cloudwatch_logs.kms_key_arn: a us-east-1 key."
  }
}

variable "dnssec" {
  description = "DNSSEC signing for public zones with a us-east-1 KMS key."
  type = object({
    enabled                 = optional(bool, true)
    deletion_window_in_days = optional(number, 30)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.dnssec.deletion_window_in_days >= 7 && var.dnssec.deletion_window_in_days <= 30
    error_message = "dnssec.deletion_window_in_days: 7-30."
  }
}

variable "kms" {
  description = "Query log encryption in us-east-1: {} service encryption, create = true module key, key_id your key (ARN or ID)."
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
    condition     = var.kms.key_id == null || can(regex("^(arn:aws[a-z-]*:kms:us-east-1:[0-9]{12}:key/)?(mrk-[a-f0-9]{32}|[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})$", var.kms.key_id))
    error_message = "kms.key_id: a us-east-1 KMS key ARN or key ID."
  }
}
