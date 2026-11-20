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
  description = "Distribution name."
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

variable "aliases" {
  description = "Alternate domain names. Empty: the default CloudFront certificate."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "acm_certificate_arn" {
  description = "us-east-1 ACM certificate ARN for the aliases."
  type        = string
  default     = null

  validation {
    condition     = length(var.aliases) == 0 || var.acm_certificate_arn != null
    error_message = "acm_certificate_arn: required with aliases."
  }
}

variable "minimum_protocol_version" {
  description = "Viewer TLS policy."
  type        = string
  default     = "TLSv1.2_2025"
  nullable    = false

  validation {
    condition     = contains(["TLSv1.2_2025", "TLSv1.3_2025"], var.minimum_protocol_version)
    error_message = "minimum_protocol_version: TLSv1.2_2025 or TLSv1.3_2025."
  }
}

variable "waf" {
  description = "CLOUDFRONT-scope WAF web ACL (CloudFront.6)."
  type = object({
    enabled     = optional(bool, false)
    web_acl_arn = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.waf.enabled || var.waf.web_acl_arn != null
    error_message = "waf: set web_acl_arn."
  }
}

variable "origins" {
  description = "Origins by ID: domain name, type s3, lambda or custom, path."
  type = map(object({
    domain_name = string
    type        = optional(string, "custom")
    origin_path = optional(string)
  }))
  nullable = false

  validation {
    condition     = length(var.origins) > 0 && alltrue([for o in values(var.origins) : contains(["s3", "lambda", "custom"], o.type)])
    error_message = "origins: at least one; type s3, lambda or custom."
  }
}

variable "origin_groups" {
  description = "Failover origin groups by ID: primary, secondary, status codes."
  type = map(object({
    primary      = string
    secondary    = string
    status_codes = optional(list(number), [500, 502, 503, 504])
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for g in values(var.origin_groups) : contains(keys(var.origins), g.primary) && contains(keys(var.origins), g.secondary)])
    error_message = "origin_groups: primary and secondary are origin IDs."
  }
}

variable "default_cache_behavior" {
  description = "Default behavior: origin, methods, cache, origin request and response headers policies (Managed-* name or ID)."
  type = object({
    target_origin_id        = string
    allowed_methods         = optional(list(string), ["GET", "HEAD", "OPTIONS"])
    cached_methods          = optional(list(string), ["GET", "HEAD"])
    cache_policy            = optional(string, "Managed-CachingOptimized")
    origin_request_policy   = optional(string)
    response_headers_policy = optional(string, "Managed-SecurityHeadersPolicy")
    compress                = optional(bool, true)
  })
  nullable = false

  validation {
    condition     = contains(concat(keys(var.origins), keys(var.origin_groups)), var.default_cache_behavior.target_origin_id)
    error_message = "default_cache_behavior.target_origin_id: an origin or origin group ID."
  }
}

variable "ordered_cache_behaviors" {
  description = "Path behaviors in order, same fields as the default plus path_pattern."
  type = list(object({
    path_pattern            = string
    target_origin_id        = string
    allowed_methods         = optional(list(string), ["GET", "HEAD", "OPTIONS"])
    cached_methods          = optional(list(string), ["GET", "HEAD"])
    cache_policy            = optional(string, "Managed-CachingOptimized")
    origin_request_policy   = optional(string)
    response_headers_policy = optional(string, "Managed-SecurityHeadersPolicy")
    compress                = optional(bool, true)
  }))
  default  = []
  nullable = false

  validation {
    condition     = alltrue([for b in var.ordered_cache_behaviors : contains(concat(keys(var.origins), keys(var.origin_groups)), b.target_origin_id)])
    error_message = "ordered_cache_behaviors[*].target_origin_id: an origin or origin group ID."
  }
}

variable "default_root_object" {
  description = "Object for / requests, such as index.html (CloudFront.1)."
  type        = string
  default     = null
}

variable "custom_error_responses" {
  description = "Custom error responses."
  type = list(object({
    error_code            = number
    response_code         = optional(number)
    response_page_path    = optional(string)
    error_caching_min_ttl = optional(number, 10)
  }))
  default  = []
  nullable = false
}

variable "geo_restriction" {
  description = "Geo restriction: none, whitelist or blacklist with country codes."
  type = object({
    restriction_type = optional(string, "none")
    locations        = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["none", "whitelist", "blacklist"], var.geo_restriction.restriction_type)
    error_message = "geo_restriction.restriction_type: none, whitelist or blacklist."
  }
}

variable "price_class" {
  description = "Price class."
  type        = string
  default     = "PriceClass_All"
  nullable    = false

  validation {
    condition     = contains(["PriceClass_All", "PriceClass_200", "PriceClass_100"], var.price_class)
    error_message = "price_class: PriceClass_All, PriceClass_200 or PriceClass_100."
  }
}

variable "cloudwatch_logs" {
  description = "Access log group in us-east-1."
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

variable "kms" {
  description = "Log encryption in us-east-1: {} service encryption, create = true module key, key_id your key (ARN or ID)."
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

variable "alarms" {
  description = "Built-in CloudWatch alarms: switch, topics by severity, per-alarm overrides."
  type = object({
    enabled    = optional(bool, true)
    topic_arns = optional(map(string), {})
    overrides = optional(object({
      server_error_rate = optional(object({ enabled = optional(bool), threshold = optional(number), evaluation_periods = optional(number), datapoints_to_alarm = optional(number), period = optional(number), severity = optional(string) }), {})
      client_error_rate = optional(object({ enabled = optional(bool), threshold = optional(number), evaluation_periods = optional(number), datapoints_to_alarm = optional(number), period = optional(number), severity = optional(string) }), {})
      requests          = optional(object({ enabled = optional(bool), threshold = optional(number), evaluation_periods = optional(number), datapoints_to_alarm = optional(number), period = optional(number), severity = optional(string) }), {})
    }), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for s, arn in var.alarms.topic_arns : can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]+$", arn))])
    error_message = "alarms.topic_arns: SNS topic ARNs by severity."
  }
}
