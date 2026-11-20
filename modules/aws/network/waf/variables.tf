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
  description = "Web ACL name."
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

variable "scope" {
  description = "REGIONAL or CLOUDFRONT (created in us-east-1)."
  type        = string
  default     = "REGIONAL"
  nullable    = false

  validation {
    condition     = contains(["REGIONAL", "CLOUDFRONT"], var.scope)
    error_message = "scope: REGIONAL or CLOUDFRONT."
  }
}

variable "default_action" {
  description = "Action when no rule matches: allow or block."
  type        = string
  default     = "allow"
  nullable    = false

  validation {
    condition     = contains(["allow", "block"], var.default_action)
    error_message = "default_action: allow or block."
  }
}

variable "managed_rules" {
  description = "Managed rule groups by key: name, vendor, override action, version."
  type = map(object({
    name            = string
    vendor_name     = optional(string, "AWS")
    override_action = optional(string, "none")
    version         = optional(string)
  }))
  default = {
    common        = { name = "AWSManagedRulesCommonRuleSet" }
    ip_reputation = { name = "AWSManagedRulesAmazonIpReputationList" }
    known_bad     = { name = "AWSManagedRulesKnownBadInputsRuleSet" }
  }
  nullable = false

  validation {
    condition     = alltrue([for r in values(var.managed_rules) : contains(["none", "count"], r.override_action)])
    error_message = "managed_rules[*].override_action: none or count."
  }

  validation {
    condition     = length(var.managed_rules) + length(var.rate_limit_rules) + length(var.ip_block_rules) + length(var.geo_block_rules) + length(var.regex_match_rules) > 0
    error_message = "managed_rules: the web ACL needs at least one rule (WAF.10)."
  }
}

variable "rate_limit_rules" {
  description = "Per-IP rate limits by key: requests per 5 minutes, action."
  type = map(object({
    limit  = number
    action = optional(string, "block")
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for r in values(var.rate_limit_rules) : contains(["block", "count", "captcha", "challenge"], r.action) && r.limit >= 10 && r.limit <= 2000000000])
    error_message = "rate_limit_rules: action block, count, captcha or challenge; limit 10-2000000000."
  }
}

variable "ip_sets" {
  description = "IP sets by key: version and addresses."
  type = map(object({
    addresses          = list(string)
    ip_address_version = optional(string, "IPV4")
    description        = optional(string)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for s in values(var.ip_sets) : contains(["IPV4", "IPV6"], s.ip_address_version)])
    error_message = "ip_sets[*].ip_address_version: IPV4 or IPV6."
  }
}

variable "ip_block_rules" {
  description = "Rules matching an ip_sets key, by key: action."
  type = map(object({
    ip_set_key = string
    action     = optional(string, "block")
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for r in values(var.ip_block_rules) : contains(keys(var.ip_sets), r.ip_set_key) && contains(["block", "count"], r.action)])
    error_message = "ip_block_rules: ip_set_key an ip_sets key; action block or count."
  }
}

variable "geo_block_rules" {
  description = "Country match rules by key: country codes, action."
  type = map(object({
    countries = list(string)
    action    = optional(string, "block")
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for r in values(var.geo_block_rules) : contains(["block", "count"], r.action) && length(r.countries) > 0])
    error_message = "geo_block_rules: action block or count; at least one country."
  }
}

variable "regex_pattern_sets" {
  description = "Regex pattern sets by key."
  type = map(object({
    regexes     = list(string)
    description = optional(string)
  }))
  default  = {}
  nullable = false
}

variable "regex_match_rules" {
  description = "Rules matching a regex_pattern_sets key on uri_path, query_string or single_header."
  type = map(object({
    regex_pattern_set_key = string
    action                = optional(string, "block")
    field_to_match        = optional(string, "uri_path")
    header_name           = optional(string)
    text_transformation   = optional(string, "NONE")
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for r in values(var.regex_match_rules) : contains(keys(var.regex_pattern_sets), r.regex_pattern_set_key) && contains(["block", "count"], r.action) && contains(["uri_path", "query_string", "single_header"], r.field_to_match)])
    error_message = "regex_match_rules: a regex_pattern_sets key; action block or count; field uri_path, query_string or single_header."
  }

  validation {
    condition     = alltrue([for r in values(var.regex_match_rules) : r.field_to_match != "single_header" || r.header_name != null])
    error_message = "regex_match_rules: single_header needs header_name."
  }
}

variable "token_domains" {
  description = "Domains whose CAPTCHA and challenge tokens the web ACL accepts."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "redacted_fields" {
  description = "Request fields redacted in logs."
  type = object({
    headers      = optional(list(string), ["authorization", "cookie"])
    query_string = optional(bool, false)
    uri_path     = optional(bool, false)
  })
  default  = {}
  nullable = false
}

variable "cloudwatch_logs" {
  description = "WAF log group (aws-waf-logs- prefix)."
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
  description = "Log encryption: {} service encryption, create = true module key, key_id your key (ARN or ID)."
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
