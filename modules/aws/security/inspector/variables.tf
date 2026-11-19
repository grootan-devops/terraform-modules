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
  description = "Regions to manage. Empty: provider Region."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for region in var.regions : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", region))])
    error_message = "regions: AWS Region codes."
  }
}

variable "organization_admin" {
  description = "Management account call: delegated administrator in every Region."
  type = object({
    enabled    = optional(bool, false)
    account_id = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.organization_admin.enabled || can(regex("^[0-9]{12}$", var.organization_admin.account_id))
    error_message = "organization_admin.account_id: 12 digits."
  }

  validation {
    condition     = !var.organization_admin.enabled || !var.organization_configuration.enabled
    error_message = "organization_admin: set organization_configuration.enabled = false."
  }
}

variable "organization_configuration" {
  description = "Delegated administrator call: auto-enabled scan types and administrator activation."
  type = object({
    enabled                = optional(bool, true)
    activate_admin_account = optional(bool, true)
    auto_enable = optional(object({
      ec2             = optional(bool, true)
      ecr             = optional(bool, true)
      lambda          = optional(bool, true)
      lambda_code     = optional(bool, true)
      code_repository = optional(bool, false)
    }), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.organization_configuration.auto_enable.lambda_code || var.organization_configuration.auto_enable.lambda
    error_message = "auto_enable.lambda_code needs auto_enable.lambda."
  }

  validation {
    condition     = !var.organization_configuration.enabled || anytrue(values(var.organization_configuration.auto_enable))
    error_message = "auto_enable: at least one scan type."
  }
}

variable "member_account_ids" {
  description = "Existing accounts to associate and activate."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for account_id in var.member_account_ids : can(regex("^[0-9]{12}$", account_id))])
    error_message = "member_account_ids: 12-digit account IDs."
  }

  validation {
    condition     = length(var.member_account_ids) == 0 || var.organization_configuration.enabled
    error_message = "member_account_ids needs organization_configuration.enabled."
  }
}

variable "filters" {
  description = "Suppression rules by key, in every Region."
  type = map(object({
    description = optional(string)
    reason      = optional(string)
    action      = optional(string, "SUPPRESS")
    severity = optional(list(object({
      comparison = optional(string, "EQUALS")
      value      = string
    })), [])
    finding_type = optional(list(object({
      comparison = optional(string, "EQUALS")
      value      = string
    })), [])
    resource_type = optional(list(object({
      comparison = optional(string, "EQUALS")
      value      = string
    })), [])
    vulnerability_id = optional(list(object({
      comparison = optional(string, "EQUALS")
      value      = string
    })), [])
    aws_account_id = optional(list(object({
      comparison = optional(string, "EQUALS")
      value      = string
    })), [])
    resource_tags = optional(list(object({
      key   = string
      value = string
    })), [])
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for key in keys(var.filters) : can(regex("^[a-z0-9][a-z0-9-]{0,31}$", key))])
    error_message = "filters keys: 1-32 chars, a-z 0-9 -."
  }

  validation {
    condition     = alltrue([for f in values(var.filters) : contains(["SUPPRESS", "NONE"], f.action)])
    error_message = "filters[*].action: SUPPRESS or NONE."
  }

  validation {
    condition = alltrue([
      for f in values(var.filters) :
      length(f.severity) + length(f.finding_type) + length(f.resource_type) + length(f.vulnerability_id) + length(f.aws_account_id) + length(f.resource_tags) > 0
    ])
    error_message = "filters: at least one criterion each."
  }

  validation {
    condition = alltrue(flatten([
      for f in values(var.filters) : [
        for c in concat(f.severity, f.finding_type, f.resource_type, f.vulnerability_id, f.aws_account_id) : contains(["EQUALS", "PREFIX", "NOT_EQUALS"], c.comparison)
      ]
    ]))
    error_message = "filters comparison: EQUALS, PREFIX or NOT_EQUALS."
  }

  validation {
    condition     = alltrue(flatten([for f in values(var.filters) : [for c in f.severity : contains(["INFORMATIONAL", "LOW", "MEDIUM", "HIGH", "CRITICAL", "UNTRIAGED"], c.value)]]))
    error_message = "filters[*].severity: INFORMATIONAL, LOW, MEDIUM, HIGH, CRITICAL or UNTRIAGED."
  }

  validation {
    condition     = alltrue(flatten([for f in values(var.filters) : [for c in f.finding_type : contains(["NETWORK_REACHABILITY", "PACKAGE_VULNERABILITY", "CODE_VULNERABILITY"], c.value)]]))
    error_message = "filters[*].finding_type: NETWORK_REACHABILITY, PACKAGE_VULNERABILITY or CODE_VULNERABILITY."
  }

  validation {
    condition = alltrue([
      for f in values(var.filters) :
      max(length(f.severity), length(f.finding_type), length(f.resource_type), length(f.vulnerability_id), length(f.aws_account_id), length(f.resource_tags)) <= 10
    ])
    error_message = "filters: at most 10 entries per criterion."
  }

  validation {
    condition     = length(var.filters) == 0 || var.organization_configuration.enabled
    error_message = "filters needs organization_configuration.enabled."
  }
}
