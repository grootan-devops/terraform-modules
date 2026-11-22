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
  description = "Instance name."
  type        = string
  default     = null

  validation {
    condition     = var.name == null || can(regex("^[a-z0-9][a-z0-9-]{0,31}$", var.name))
    error_message = "name: 1-32 chars, a-z 0-9 -."
  }
}

variable "purpose" {
  description = "Role purpose, appended to the name."
  type        = string
  default     = null

  validation {
    condition     = var.purpose == null || can(regex("^[a-z0-9][a-z0-9-]{0,31}$", var.purpose))
    error_message = "purpose: 1-32 chars, a-z 0-9 -."
  }

  validation {
    condition     = var.purpose != null || var.name != null || var.role_name != null
    error_message = "Set name, purpose or role_name."
  }
}

variable "tags" {
  description = "Extra tags; governance tags win."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "role_name" {
  description = "Exact role name. Null: derived."
  type        = string
  default     = null

  validation {
    condition     = var.role_name == null || can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.role_name))
    error_message = "role_name: 1-64 chars of a-z A-Z 0-9 +=,.@_-."
  }
}

variable "include_region_in_name" {
  description = "Append the Region to the derived name."
  type        = bool
  default     = true
  nullable    = false
}

variable "description" {
  description = "Role description."
  type        = string
  default     = null
}

variable "trust" {
  description = "Who may assume the role."
  type = object({
    services       = optional(list(string), [])
    aws_principals = optional(list(string), [])
    federated      = optional(list(string), [])
    actions        = optional(list(string), ["sts:AssumeRole"])
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
  })
  nullable = false

  validation {
    condition     = length(var.trust.services) + length(var.trust.aws_principals) + length(var.trust.federated) > 0
    error_message = "trust: set a service, AWS principal or federated provider."
  }

  validation {
    condition     = !contains(var.trust.aws_principals, "*")
    error_message = "trust.aws_principals: * not allowed."
  }
}

variable "managed_policy_arns" {
  description = "Managed policies to attach."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "policy_statements" {
  description = "Inline policy statements."
  type = list(object({
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
  }))
  default  = []
  nullable = false

  validation {
    condition     = alltrue([for s in var.policy_statements : length(s.principals) == 0 && s.resources != null])
    error_message = "policy_statements: set resources, no principals."
  }

  validation {
    condition     = alltrue([for s in var.policy_statements : !(s.effect == "Allow" && contains(s.actions, "*") && contains(coalesce(s.resources, []), "*"))])
    error_message = "policy_statements: no * action on * resource (IAM.1)."
  }
}

variable "policy_documents" {
  description = "Policy JSON documents merged into the inline policy."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary ARN."
  type        = string
  default     = null
}

variable "path" {
  description = "IAM path."
  type        = string
  default     = "/"
  nullable    = false

  validation {
    condition     = can(regex("^/([a-zA-Z0-9+=,.@_-]+/)*$", var.path))
    error_message = "path: must start and end with /."
  }
}

variable "max_session_duration" {
  description = "Max session duration (3600-43200 s)."
  type        = number
  default     = 3600
  nullable    = false

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration: 3600-43200."
  }
}

variable "instance_profile" {
  description = "Create an instance profile."
  type = object({
    enabled = optional(bool, false)
  })
  default  = {}
  nullable = false
}
