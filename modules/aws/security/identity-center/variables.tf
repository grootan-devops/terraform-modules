variable "application" {
  description = "Application name."
  type        = string
  default     = "platform"

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

variable "permission_sets" {
  description = "Permission sets by key: policies, boundary, session duration."
  type = map(object({
    description         = optional(string)
    session_duration    = optional(string, "PT1H")
    relay_state         = optional(string)
    managed_policy_arns = optional(list(string), [])
    customer_managed_policies = optional(list(object({
      name = string
      path = optional(string, "/")
    })), [])
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
    permissions_boundary = optional(object({
      enabled            = optional(bool, false)
      managed_policy_arn = optional(string)
      customer_managed_policy = optional(object({
        name = string
        path = optional(string, "/")
      }))
    }), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k in keys(var.permission_sets) : can(regex("^[a-z0-9][a-z0-9-]{0,17}$", k))])
    error_message = "permission_sets keys: 1-18 chars, a-z 0-9 -."
  }

  validation {
    condition     = alltrue([for p in values(var.permission_sets) : can(regex("^PT([1-9]|1[0-2])H$", p.session_duration))])
    error_message = "session_duration: PT1H-PT12H."
  }

  validation {
    condition     = alltrue(flatten([for p in values(var.permission_sets) : [for a in p.managed_policy_arns : can(regex("^arn:aws[a-z-]*:iam::aws:policy/.+$", a))]]))
    error_message = "managed_policy_arns: AWS managed policy ARNs."
  }

  validation {
    condition     = alltrue(flatten([for p in values(var.permission_sets) : [for s in p.policy_statements : s.resources != null && length(s.principals) == 0]]))
    error_message = "policy_statements: set resources, no principals."
  }

  validation {
    condition     = alltrue([for p in values(var.permission_sets) : !p.permissions_boundary.enabled || ((p.permissions_boundary.managed_policy_arn == null) != (p.permissions_boundary.customer_managed_policy == null))])
    error_message = "permissions_boundary: managed_policy_arn or customer_managed_policy."
  }
}

variable "groups" {
  description = "Identity store groups by key: description and member user IDs."
  type = map(object({
    description = optional(string)
    member_ids  = optional(list(string), [])
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k in keys(var.groups) : can(regex("^[a-z0-9][a-z0-9-]{0,63}$", k))])
    error_message = "groups keys: 1-64 chars, a-z 0-9 -."
  }
}

variable "account_assignments" {
  description = "Assignments by key: permission set key, principal and account IDs."
  type = map(object({
    permission_set = string
    principal_type = optional(string, "GROUP")
    principal_id   = optional(string)
    group          = optional(string)
    account_ids    = list(string)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for a in values(var.account_assignments) : contains(keys(var.permission_sets), a.permission_set)])
    error_message = "account_assignments.permission_set: a permission_sets key."
  }

  validation {
    condition     = alltrue([for a in values(var.account_assignments) : contains(["GROUP", "USER"], a.principal_type)])
    error_message = "account_assignments.principal_type: GROUP or USER."
  }

  validation {
    condition     = alltrue([for a in values(var.account_assignments) : (a.principal_id == null) != (a.group == null) && (a.group == null || (a.principal_type == "GROUP" && contains(keys(var.groups), coalesce(a.group, "-"))))])
    error_message = "account_assignments: principal_id or a groups key."
  }

  validation {
    condition     = alltrue([for a in values(var.account_assignments) : length(a.account_ids) > 0 && alltrue([for id in a.account_ids : can(regex("^[0-9]{12}$", id))])])
    error_message = "account_assignments.account_ids: 12-digit account IDs."
  }
}
