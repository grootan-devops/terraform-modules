variable "name" {
  description = "Name identifier for the KMS key"
  type        = string
  default     = null
}

variable "description" {
  description = "Optional custom description for the KMS key. Overrides the default computed description."
  type        = string
  default     = null
}

variable "application" {
  description = "Name of the product"
  type        = string
}

variable "environment" {
  description = "Deployment environment name (e.g. dev, staging, prod)."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "The environment name must contain only lowercase alphanumeric characters and hyphens."
  }
}

variable "is_enabled" {
  description = "Specifies whether the key is enabled."
  type        = bool
  default     = true
}

variable "key_usage" {
  description = "Specifies the intended use of the key. Valid values: ENCRYPT_DECRYPT, SIGN_VERIFY, or GENERATE_VERIFY_MAC."
  type        = string
  default     = "ENCRYPT_DECRYPT"
}

variable "customer_master_key_spec" {
  description = "Specifies whether the key contains a symmetric key or an asymmetric key pair and the encryption algorithms or signing algorithms that the key supports. Valid values: SYMMETRIC_DEFAULT, RSA_2048, RSA_3072, RSA_4096, HMAC_256, ECC_NIST_P256, ECC_NIST_P384, ECC_NIST_P521, or ECC_SECG_P256K1."
  type        = string
  default     = "SYMMETRIC_DEFAULT"
}

variable "deletion_window_in_days" {
  description = "Duration in days after which the key is deleted after destruction of the resource. Must be between 7 and 30."
  type        = number
  default     = 30
  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "The deletion window must be between 7 and 30 days."
  }
}

variable "enable_key_rotation" {
  description = "Specifies whether key rotation is enabled. Defaults to true for production safety. Note: Rotation is only supported for symmetric keys."
  type        = bool
  default     = true
}

variable "rotation_period_in_days" {
  description = "Custom period of time between each rotation date. Must be a number between 90 and 2560. Default is AWS default if not specified (365)."
  type        = number
  default     = 365
  validation {
    condition     = var.rotation_period_in_days == null ? true : (var.rotation_period_in_days >= 90 && var.rotation_period_in_days <= 2560)
    error_message = "If specified, rotation_period_in_days must be between 90 and 2560."
  }
}

variable "multi_region" {
  description = "Indicates whether the KMS key is a multi-Region (true) or regional (false) key. Default is false."
  type        = bool
  default     = false
}

variable "policy_json" {
  description = "A valid policy JSON document."
  type        = string
  default     = null
}

# ==============================================================================
# Replica Key Configuration
# ==============================================================================

variable "replica_key" {
  description = "Configuration for creating a replica key in a secondary region. multi_region must be true."
  type = object({
    create                  = bool
    region                  = optional(string, null)
    policy_json             = optional(string, null)
    deletion_window_in_days = optional(number, 30)
  })
  default = {
    create = false
  }
}

variable "tags" {
  type        = map(string)
  description = "Additional tags to apply to all resources"
  default     = {}
}
