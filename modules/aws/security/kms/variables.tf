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
  description = "Key name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,31}$", var.name))
    error_message = "name: 1-32 chars, a-z 0-9 -."
  }
}

variable "purpose" {
  description = "Key purpose, appended to the alias."
  type        = string
  default     = null

  validation {
    condition     = var.purpose == null || can(regex("^[a-z0-9][a-z0-9-]{0,31}$", var.purpose))
    error_message = "purpose: 1-32 chars, a-z 0-9 -."
  }
}

variable "tags" {
  description = "Extra tags; governance tags win."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "region" {
  description = "Key Region. Null: provider Region."
  type        = string
  default     = null
}

variable "description" {
  description = "Key description."
  type        = string
  default     = null
}

variable "key_usage" {
  description = "Key usage."
  type        = string
  default     = "ENCRYPT_DECRYPT"
  nullable    = false

  validation {
    condition     = contains(["ENCRYPT_DECRYPT", "SIGN_VERIFY", "GENERATE_VERIFY_MAC", "KEY_AGREEMENT"], var.key_usage)
    error_message = "key_usage: ENCRYPT_DECRYPT, SIGN_VERIFY, GENERATE_VERIFY_MAC or KEY_AGREEMENT."
  }
}

variable "key_spec" {
  description = "Key spec."
  type        = string
  default     = "SYMMETRIC_DEFAULT"
  nullable    = false

  validation {
    condition = contains([
      "SYMMETRIC_DEFAULT", "RSA_2048", "RSA_3072", "RSA_4096", "HMAC_224", "HMAC_256", "HMAC_384", "HMAC_512",
      "ECC_NIST_P256", "ECC_NIST_P384", "ECC_NIST_P521", "ECC_SECG_P256K1", "ECC_NIST_EDWARDS25519", "ML_DSA_44", "ML_DSA_65", "ML_DSA_87"
    ], var.key_spec)
    error_message = "key_spec: not a KMS key spec."
  }
}

variable "deletion_window_in_days" {
  description = "Deletion window (7-30 days)."
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days: 7-30."
  }
}

variable "rotation_period_in_days" {
  description = "Rotation period (90-2560 days)."
  type        = number
  default     = 365
  nullable    = false

  validation {
    condition     = var.rotation_period_in_days >= 90 && var.rotation_period_in_days <= 2560
    error_message = "rotation_period_in_days: 90-2560."
  }
}

variable "multi_region" {
  description = "Multi-Region primary key."
  type        = bool
  default     = false
  nullable    = false
}

variable "replica_regions" {
  description = "Replica Regions."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = length(var.replica_regions) == 0 || var.multi_region
    error_message = "replica_regions needs multi_region = true."
  }
}

variable "additional_aliases" {
  description = "Extra alias names, without alias/."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for a in var.additional_aliases : can(regex("^[a-zA-Z0-9/_-]{1,250}$", a)) && !startswith(a, "aws/")])
    error_message = "additional_aliases: letters, digits, / _ -; no aws/ prefix."
  }
}

variable "policy_statements" {
  description = "Extra key policy statements."
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
    condition     = alltrue([for s in var.policy_statements : !(s.effect == "Allow" && length(s.conditions) == 0 && contains(flatten(values(s.principals)), "*"))])
    error_message = "Allow for principal * needs a condition (KMS.5)."
  }
}
