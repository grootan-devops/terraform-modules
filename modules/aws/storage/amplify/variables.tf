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
  description = "App name suffix."
  type        = string
  default     = null

  validation {
    condition     = var.name == null || can(regex("^[a-z0-9][a-z0-9-]{0,31}$", coalesce(var.name, "-")))
    error_message = "name: 1-32 chars, a-z 0-9 -."
  }
}

variable "tags" {
  description = "Extra tags; governance tags win."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "description" {
  description = "App description."
  type        = string
  default     = null
}

variable "branches" {
  description = "Branches by name; builds come from CI."
  type = map(object({
    stage      = optional(string, "PRODUCTION")
    framework  = optional(string)
    auto_build = optional(bool, false)
  }))
  nullable = false

  validation {
    condition     = length(var.branches) > 0
    error_message = "branches: at least one branch."
  }

  validation {
    condition     = alltrue([for b in values(var.branches) : contains(["PRODUCTION", "BETA", "DEVELOPMENT", "EXPERIMENTAL", "PULL_REQUEST"], b.stage)])
    error_message = "branches[*].stage: PRODUCTION, BETA, DEVELOPMENT, EXPERIMENTAL or PULL_REQUEST."
  }
}

variable "domain_associations" {
  description = "Custom domains by name."
  type = map(object({
    certificate_arn       = optional(string)
    wait_for_verification = optional(bool, true)
    sub_domains = map(object({
      branch_name = string
      prefix      = string
    }))
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue(flatten([for d in values(var.domain_associations) : [for s in values(d.sub_domains) : contains(keys(var.branches), s.branch_name)]]))
    error_message = "domain_associations: sub-domain branch_name must be in branches."
  }
}

variable "custom_rules" {
  description = "Rewrite and redirect rules."
  type = list(object({
    source    = string
    target    = string
    status    = optional(string)
    condition = optional(string)
  }))
  default  = []
  nullable = false

  validation {
    condition     = alltrue([for r in var.custom_rules : r.status == null || contains(["200", "301", "302", "404", "404-200"], coalesce(r.status, "-"))])
    error_message = "custom_rules[*].status: 200, 301, 302, 404 or 404-200."
  }
}

variable "custom_headers" {
  description = "Response headers: module security headers or your customHttp YAML."
  type = object({
    enabled = optional(bool, true)
    yaml    = optional(string)
  })
  default  = {}
  nullable = false
}

variable "basic_auth" {
  description = "App-wide basic auth; stored in state."
  type = object({
    enabled  = optional(bool, false)
    username = optional(string)
    password = optional(string)
  })
  default   = {}
  nullable  = false
  sensitive = true

  validation {
    condition     = !var.basic_auth.enabled || (try(length(var.basic_auth.username) > 0, false) && try(length(var.basic_auth.password) >= 8, false))
    error_message = "basic_auth: username and a password of 8+ chars when enabled."
  }
}
