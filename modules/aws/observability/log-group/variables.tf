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
  description = "Instance name (tags)."
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

variable "log_group_name" {
  description = "Log group name, as the writing service requires it."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9_./#-]{1,512}$", var.log_group_name))
    error_message = "log_group_name: 1-512 chars of a-z A-Z 0-9 _ . / # -."
  }
}

variable "region" {
  description = "Log group Region. Null: provider Region."
  type        = string
  default     = null
}

variable "retention_in_days" {
  description = "Retention in days."
  type        = number
  default     = 365
  nullable    = false

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.retention_in_days)
    error_message = "retention_in_days: a CloudWatch Logs retention value (1-3653)."
  }
}

variable "kms_key_arn" {
  description = "KMS key ARN. Null: CloudWatch Logs service encryption."
  type        = string
  default     = null
}

variable "log_group_class" {
  description = "STANDARD, INFREQUENT_ACCESS or DELIVERY."
  type        = string
  default     = "STANDARD"
  nullable    = false

  validation {
    condition     = contains(["STANDARD", "INFREQUENT_ACCESS", "DELIVERY"], var.log_group_class)
    error_message = "log_group_class: STANDARD, INFREQUENT_ACCESS or DELIVERY."
  }
}

variable "deletion_protection_enabled" {
  description = "Block deletion of the log group."
  type        = bool
  default     = true
  nullable    = false
}
