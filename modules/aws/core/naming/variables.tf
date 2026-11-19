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

variable "tags" {
  description = "Extra tags; governance tags win."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "region" {
  description = "Region for names. Null: provider Region."
  type        = string
  default     = null
}

variable "names" {
  description = "Names to derive: suffix, uniqueness (region, account, global), max_length."
  type = map(object({
    suffix     = optional(string)
    uniqueness = optional(string, "region")
    max_length = optional(number, 64)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for n in values(var.names) : contains(["region", "account", "global"], n.uniqueness)])
    error_message = "uniqueness: region, account or global."
  }

  validation {
    condition     = alltrue([for n in values(var.names) : n.max_length >= 16])
    error_message = "max_length: at least 16."
  }

  validation {
    condition     = alltrue([for n in values(var.names) : n.suffix == null || can(regex("^[a-z0-9][a-z0-9-]*$", n.suffix))])
    error_message = "suffix: a-z 0-9 -."
  }
}
