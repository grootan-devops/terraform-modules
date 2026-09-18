variable "application" {
  description = "Application name"
  type        = string
}

variable "environment" {
  description = "Deployment environment name (e.g. dev, staging, prod)."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "The environment name must contain only lowercase alphanumeric characters and hyphens."
  }
}

variable "scope" {
  description = "Specifies whether this is for an AWS CloudFront distribution or for a regional application. Valid values are CLOUDFRONT or REGIONAL."
  type        = string
  default     = "REGIONAL"
}

variable "default_action" {
  description = "Default action for the WAF. Can be 'allow' or 'block'"
  type        = string
  default     = "allow"
}

variable "token_domains" {
  description = "List of domains to configure for the AWS WAFv2 API Key (used for CAPTCHA/JavaScript challenges). Max 5 domains."
  type        = list(string)
  default     = []
}

variable "managed_rules" {
  description = "Map of AWS Managed Rule Groups to enable"
  type = map(object({
    name            = string
    vendor_name     = string
    override_action = string # 'none' or 'count'
  }))
  default = {
    "common" = {
      name            = "AWSManagedRulesCommonRuleSet"
      vendor_name     = "AWS"
      override_action = "none"
    },
    "ip_reputation" = {
      name            = "AWSManagedRulesAmazonIpReputationList"
      vendor_name     = "AWS"
      override_action = "none"
    },
    "known_bad" = {
      name            = "AWSManagedRulesKnownBadInputsRuleSet"
      vendor_name     = "AWS"
      override_action = "none"
    }
  }
}

variable "ip_sets" {
  description = "Map of IP sets to create"
  type = map(object({
    name               = string
    description        = string
    ip_address_version = string # IPV4 or IPV6
    addresses          = list(string)
  }))
  default = {}
}

variable "regex_pattern_sets" {
  description = "Map of Regex Pattern Sets to create"
  type = map(object({
    name        = string
    description = string
    regexes     = list(string)
  }))
  default = {}
}

variable "rate_limit_rules" {
  description = "Map of Rate Limit rules to create (blanket limit based on IP)"
  type = map(object({
    name   = string
    limit  = number
    action = string # 'block', 'count', or 'captcha'
  }))
  default = {}
}

variable "ip_block_rules" {
  description = "Map of rules to block specific IP sets created in var.ip_sets"
  type = map(object({
    name       = string
    ip_set_key = string
    action     = string # 'block' or 'count'
  }))
  default = {}
}

variable "geo_block_rules" {
  description = "Map of Geo match rules"
  type = map(object({
    name      = string
    action    = string # 'block' or 'count'
    countries = list(string)
  }))
  default = {}
}

variable "association_arns" {
  description = "List of ARNs (ALB, API Gateway, AppSync) to associate the WAF with"
  type        = list(string)
  default     = []
}

variable "cloudwatch_logs" {
  description = "CloudWatch logs configuration"
  type = object({
    retention_in_days = optional(number, 30)
    kms_key_arn       = optional(string, null)
  })
  default = {}
}

variable "redacted_fields" {
  description = "Configuration for redacted fields in WAF logs"
  type = object({
    headers      = optional(list(string), [])
    query_string = optional(bool, false)
    uri_path     = optional(bool, false)
  })
  default = {}
}

variable "name" {
  type        = string
  description = "Name for the resource. If not provided, will be derived from application and environment."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Additional tags to apply to all resources"
  default     = {}
}

variable "kms_key_arn" {
  description = "KMS Key ARN used for encrypting WAF CloudWatch log groups. Strictly required."
  type        = string
}
