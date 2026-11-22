variable "application" {
  description = "Application name."
  type        = string
  default     = "platform"
  nullable    = false

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

variable "tags" {
  description = "Extra tags; governance tags win."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "regions" {
  description = "Regions for external access analyzers. Empty: provider Region."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for region in var.regions : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", region))])
    error_message = "regions: AWS Region codes."
  }
}

variable "analyzers" {
  description = "Analyzers and archive rules; off for the management account call."
  type = object({
    enabled = optional(bool, true)
  })
  default  = {}
  nullable = false
}

variable "organization_configuration" {
  description = "Organization analyzers; off for account-only analyzers."
  type = object({
    enabled = optional(bool, true)
  })
  default  = {}
  nullable = false
}

variable "organization_admin" {
  description = "Management account call: trusted access and delegated administrator."
  type = object({
    enabled               = optional(bool, false)
    account_id            = optional(string)
    manage_trusted_access = optional(bool, true)
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.organization_admin.enabled || can(regex("^[0-9]{12}$", var.organization_admin.account_id))
    error_message = "organization_admin.account_id: 12 digits."
  }

  validation {
    condition     = !var.organization_admin.enabled || !var.analyzers.enabled
    error_message = "organization_admin: set analyzers.enabled = false."
  }
}

variable "unused_access" {
  description = "Unused access analyzer in one Region (null: provider Region)."
  type = object({
    enabled                 = optional(bool, true)
    region                  = optional(string)
    unused_access_age       = optional(number, 90)
    exclusion_account_ids   = optional(list(string), [])
    exclusion_resource_tags = optional(list(map(string)), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.unused_access.unused_access_age >= 1 && var.unused_access.unused_access_age <= 365 && floor(var.unused_access.unused_access_age) == var.unused_access.unused_access_age
    error_message = "unused_access.unused_access_age: whole days, 1-365."
  }

  validation {
    condition     = var.organization_configuration.enabled || length(var.unused_access.exclusion_account_ids) == 0
    error_message = "unused_access.exclusion_account_ids: needs organization_configuration.enabled."
  }
}

variable "internal_access" {
  description = "Internal access analyzer in one Region (null: provider Region)."
  type = object({
    enabled = optional(bool, false)
    region  = optional(string)
    inclusions = optional(list(object({
      account_ids    = optional(list(string))
      resource_arns  = optional(list(string))
      resource_types = optional(list(string))
    })), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.organization_configuration.enabled || alltrue([for inclusion in var.internal_access.inclusions : length(coalesce(inclusion.account_ids, [])) == 0])
    error_message = "internal_access.inclusions[*].account_ids: needs organization_configuration.enabled."
  }
}

variable "archive_rules" {
  description = "Archive rules by rule name: analyzer (external, unused, internal), region, filters."
  type = map(object({
    analyzer = string
    region   = optional(string)
    filters = list(object({
      criteria = string
      eq       = optional(list(string))
      neq      = optional(list(string))
      contains = optional(list(string))
      exists   = optional(bool)
    }))
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for key in keys(var.archive_rules) : can(regex("^[A-Za-z][A-Za-z0-9_.-]{0,254}$", key))])
    error_message = "archive_rules keys: 1-255 chars, a letter first, then A-Z a-z 0-9 _ . -."
  }

  validation {
    condition     = alltrue([for rule in values(var.archive_rules) : contains(["external", "unused", "internal"], rule.analyzer)])
    error_message = "archive_rules[*].analyzer: external, unused or internal."
  }

  validation {
    condition = alltrue([
      for rule in values(var.archive_rules) : length(rule.filters) > 0 && alltrue([
        for f in rule.filters : f.eq != null || f.neq != null || f.contains != null || f.exists != null
      ])
    ])
    error_message = "archive_rules: a filter each, each with eq, neq, contains or exists."
  }

  validation {
    condition = alltrue(flatten([
      for rule in values(var.archive_rules) : [
        for f in rule.filters : [for vals in [f.eq, f.neq, f.contains] : vals == null ? true : length(vals) >= 1 && length(vals) <= 20]
      ]
    ]))
    error_message = "archive_rules: eq, neq and contains take 1-20 values."
  }

  validation {
    condition = alltrue([
      for rule in values(var.archive_rules) : var.analyzers.enabled && (
        rule.analyzer == "external" ||
        (rule.analyzer == "unused" && var.unused_access.enabled) ||
        (rule.analyzer == "internal" && var.internal_access.enabled)
      )
    ])
    error_message = "archive_rules: target an analyzer this call creates."
  }
}
