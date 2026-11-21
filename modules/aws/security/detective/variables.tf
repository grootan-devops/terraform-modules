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

variable "behavior_graph" {
  description = "Behavior graph and members (account ID => root email)."
  type = object({
    enabled         = optional(bool, false)
    member_accounts = optional(map(string), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for account_id in keys(var.behavior_graph.member_accounts) : can(regex("^[0-9]{12}$", account_id))])
    error_message = "behavior_graph.member_accounts keys: 12-digit account IDs."
  }

  validation {
    condition     = alltrue([for email in values(var.behavior_graph.member_accounts) : length(email) <= 64 && can(regex("^[^@\\s]+@([A-Za-z0-9-]+\\.)+[A-Za-z]{2,63}$", email))])
    error_message = "behavior_graph.member_accounts values: email addresses, 64 chars max."
  }

  validation {
    condition     = length(var.behavior_graph.member_accounts) == 0 || var.behavior_graph.enabled
    error_message = "behavior_graph.member_accounts: needs behavior_graph.enabled."
  }
}

variable "organization_configuration" {
  description = "Organization auto-enable for new accounts; off for account-only mode."
  type = object({
    enabled     = optional(bool, true)
    auto_enable = optional(bool, true)
  })
  default  = {}
  nullable = false
}

variable "organization_admin" {
  description = "Management account call: Detective administrator."
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
    condition     = !var.organization_admin.enabled || !var.behavior_graph.enabled
    error_message = "organization_admin: set behavior_graph.enabled = false."
  }
}
