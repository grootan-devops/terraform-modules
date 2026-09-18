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

variable "branches" {
  description = "List of branch names to create in Amplify"
  type        = list(string)
}

variable "domain_associations" {
  description = "Map of domain names to their subdomains and branch associations"
  type = map(object({
    acm_certificate_arn = optional(string)
    sub_domains = map(object({
      branch_name = string
      prefix      = string
    }))
  }))
  default = {}
}

variable "custom_rules" {
  description = "List of custom rewrite/redirect rules"
  type = list(object({
    source    = string
    target    = string
    status    = optional(string)
    condition = optional(string)
  }))
  default = []
}

variable "custom_headers" {
  description = "Optional custom headers YAML configuration"
  type        = string
  default     = null
  nullable    = true
}

variable "basic_auth" {
  description = "Basic auth configuration for the Amplify app"
  type = object({
    enable   = optional(bool, false)
    username = optional(string, null)
    password = optional(string, null)
  })
  default   = {}
  sensitive = true
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
