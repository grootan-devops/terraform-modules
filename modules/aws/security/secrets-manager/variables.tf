variable "application" {
  type        = string
  description = "Application name for resource naming and tagging."
}

variable "environment" {
  description = "Deployment environment name (e.g. dev, staging, prod)."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "The environment name must contain only lowercase alphanumeric characters and hyphens."
  }
}

variable "name" {
  type        = string
  description = "Friendly name of the secret. Conflicts with name_prefix."
  default     = null

  validation {
    condition     = !(var.name != null && var.name_prefix != null)
    error_message = "Only one of 'name' or 'name_prefix' may be specified."
  }
}

variable "name_prefix" {
  type        = string
  description = "Creates a unique name beginning with the specified prefix. Conflicts with name."
  default     = null
}

variable "description" {
  type        = string
  description = "Description of the secret."
  default     = null
}

variable "kms_key_arn" {
  type        = string
  description = "ARN of the AWS KMS key to encrypt the secret values. Strictly required."
}

variable "recovery_window_in_days" {
  type        = number
  description = "Number of days that AWS Secrets Manager waits before it can delete the secret. (0 or 7 to 30)."
  default     = 30

  validation {
    condition     = var.recovery_window_in_days == 0 || (var.recovery_window_in_days >= 7 && var.recovery_window_in_days <= 30)
    error_message = "recovery_window_in_days must be 0 (force delete) or between 7 and 30 days."
  }
}

variable "force_overwrite_replica_secret" {
  type        = bool
  description = "Accepts boolean value to specify whether to overwrite a secret with the same name in the destination Region."
  default     = false
}

variable "type" {
  type        = string
  description = "Type of secret for managed external secrets (SalesforceClientSecret, BigIDClientSecret, SnowflakeKeyPairAuthentication)."
  default     = null
}

variable "region" {
  type        = string
  description = "Region where this resource will be managed."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Key-value map of user-defined tags that are attached to the secret."
  default     = {}
}

variable "policy" {
  type        = string
  description = "Valid JSON document representing a resource policy to attach to the secret."
  default     = null
}

variable "block_public_policy" {
  type        = bool
  description = "Makes an API call to validate the resource policy to prevent public access."
  default     = true
}

variable "rotation_config" {
  type = object({
    rotation_lambda_arn = string
    rotate_immediately  = optional(bool, true)
    rotation_rules = object({
      automatically_after_days = optional(number)
      duration                 = optional(string)
      schedule_expression      = optional(string)
    })
  })
  description = "Configuration block for secret rotation."
  default     = null
}

variable "secret_string" {
  type        = string
  description = "Text data to encrypt and store in this version of the secret."
  default     = null
  sensitive   = true
}

variable "secret_binary" {
  type        = string
  description = "Binary data to encrypt and store in this version of the secret (base64-encoded)."
  default     = null
  sensitive   = true
}

variable "secret_string_wo" {
  type        = string
  description = "Write-only text data to encrypt and store in this version of the secret."
  default     = null
  sensitive   = true
}

variable "secret_string_wo_version" {
  type        = number
  description = "Version identifier for secret_string_wo to trigger updates."
  default     = null
}

variable "version_stages" {
  type        = list(string)
  description = "List of staging labels attached to this version of the secret."
  default     = null
}
