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
  description = "Repository name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,31}$", var.name))
    error_message = "name: 1-32 chars, a-z 0-9 -."
  }
}

variable "tags" {
  description = "Extra tags; governance tags win."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "image_tag_mutability" {
  description = "IMMUTABLE, MUTABLE, IMMUTABLE_WITH_EXCLUSION or MUTABLE_WITH_EXCLUSION."
  type        = string
  default     = "IMMUTABLE"
  nullable    = false

  validation {
    condition     = contains(["IMMUTABLE", "MUTABLE", "IMMUTABLE_WITH_EXCLUSION", "MUTABLE_WITH_EXCLUSION"], var.image_tag_mutability)
    error_message = "image_tag_mutability: IMMUTABLE, MUTABLE, IMMUTABLE_WITH_EXCLUSION or MUTABLE_WITH_EXCLUSION."
  }
}

variable "image_tag_mutability_exclusion_filters" {
  description = "Tag wildcards exempt from the mutability setting."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = length(var.image_tag_mutability_exclusion_filters) <= 5
    error_message = "image_tag_mutability_exclusion_filters: at most 5."
  }
}

variable "scan_on_push" {
  description = "Scan images on push."
  type        = bool
  default     = true
  nullable    = false
}

variable "kms" {
  description = "Encryption: {} AES256, create = true module key, key_id your key (ARN or ID)."
  type = object({
    key_id                  = optional(string)
    create                  = optional(bool, false)
    deletion_window_in_days = optional(number, 30)
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
  })
  default  = {}
  nullable = false

  validation {
    condition     = !(var.kms.create && var.kms.key_id != null)
    error_message = "kms: set create or key_id, not both."
  }

  validation {
    condition     = var.kms.key_id == null || can(regex("^(arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/)?(mrk-[a-f0-9]{32}|[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})$", var.kms.key_id))
    error_message = "kms.key_id: a KMS key ARN or key ID."
  }
}

variable "lifecycle_policy" {
  description = "Image expiry: last tagged images kept, untagged images expired after days."
  type = object({
    enabled              = optional(bool, true)
    keep_tagged_images   = optional(number, 30)
    tag_patterns         = optional(list(string), ["*"])
    untagged_expiry_days = optional(number, 14)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.lifecycle_policy.keep_tagged_images >= 1 && var.lifecycle_policy.untagged_expiry_days >= 1
    error_message = "lifecycle_policy: counts must be 1 or more."
  }

  validation {
    condition     = length(var.lifecycle_policy.tag_patterns) > 0
    error_message = "lifecycle_policy.tag_patterns: at least one."
  }
}

variable "pull_principal_arns" {
  description = "AWS principals (account root or role ARNs) allowed to pull."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = !contains(var.pull_principal_arns, "*")
    error_message = "pull_principal_arns: * not allowed."
  }
}

variable "policy_statements" {
  description = "Repository policy statements; resources default to the repository."
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
    condition     = alltrue([for s in var.policy_statements : length(s.principals) > 0])
    error_message = "policy_statements: set principals."
  }
}
