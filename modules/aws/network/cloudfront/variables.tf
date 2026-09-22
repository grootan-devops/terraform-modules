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

variable "aliases" {
  description = "List of aliases (CNAMEs) for the CloudFront distribution"
  type        = list(string)
}

variable "acm_certificate_arn" {
  description = "ARN of the ACM certificate to use"
  type        = string
}

variable "web_acl_id" {
  description = "ID of the WAF Web ACL to associate"
  type        = string
  default     = null
}

variable "default_root_object" {
  description = "The default root object to return when a user requests the root URL"
  type        = string
  default     = null
}

variable "origin_access_controls" {
  description = "Map of Origin Access Controls to create"
  type = map(object({
    name                              = string
    description                       = string
    origin_access_control_origin_type = string
    signing_behavior                  = string
    signing_protocol                  = string
  }))
  default = {}
}

variable "origins" {
  description = "List of origins for the CloudFront distribution"
  type = list(object({
    domain_name              = string
    origin_id                = string
    origin_access_control_id = string
    is_s3                    = bool
  }))
  default = []
}

variable "origin_groups" {
  description = "List of origin groups for failover configurations"
  type = list(object({
    origin_id             = string
    failover_status_codes = list(number)
    primary_member_id     = string
    secondary_member_id   = string
  }))
  default = []
}

variable "default_cache_behavior_origin_id" {
  description = "The origin ID for the default cache behavior"
  type        = string
}

variable "static_paths" {
  description = "List of path patterns to apply the static cache behavior"
  type        = list(string)
  default     = []
}

variable "custom_error_responses" {
  description = "List of custom error responses"
  type = list(object({
    error_code            = number
    response_code         = number
    error_caching_min_ttl = number
    response_page_path    = string
  }))
  default = []
}

variable "cache_tag_config_header_name" {
  description = "Header name for cache tags if needed"
  type        = string
  default     = null
}

variable "cloudwatch_logs" {
  description = "CloudWatch logs configuration"
  type = object({
    retention_in_days           = number
    kms_key_arn                 = optional(string, null)
    deletion_protection_enabled = optional(bool, false)
  })
}

variable "geo_restriction" {
  description = "The restriction configuration for this distribution (geo_restriction)"
  type = object({
    restriction_type = string
    locations        = optional(list(string), [])
  })
  default = {
    restriction_type = "none"
  }
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
  description = "KMS Key ARN used for encrypting CloudFront CloudWatch delivery logs. Strictly required."
  type        = string
}
