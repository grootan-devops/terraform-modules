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
  description = "Secret name."
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

variable "description" {
  description = "Secret description."
  type        = string
  default     = null
}

variable "kms" {
  description = "Encryption: {} aws/secretsmanager, create = true module key, key_id your key (ARN or ID)."
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

variable "recovery_window_in_days" {
  description = "Recovery window: 0 or 7-30 days."
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition     = var.recovery_window_in_days == 0 || (var.recovery_window_in_days >= 7 && var.recovery_window_in_days <= 30)
    error_message = "recovery_window_in_days: 0 or 7-30."
  }
}

variable "secret_string_wo" {
  description = "Secret value, write-only."
  type        = string
  default     = null
  sensitive   = true
  ephemeral   = true
}

variable "secret_string_wo_version" {
  description = "Value version; increment to write a new value."
  type        = number
  default     = null

  validation {
    condition     = (var.secret_string_wo_version == null) == (var.secret_string_wo == null)
    error_message = "secret_string_wo_version: set with secret_string_wo."
  }
}

variable "rotation" {
  description = "Rotation by a Lambda function on a schedule (SecretsManager.1, SecretsManager.4)."
  type = object({
    enabled                  = optional(bool, false)
    lambda_arn               = optional(string)
    automatically_after_days = optional(number, 30)
    schedule_expression      = optional(string)
    duration                 = optional(string)
    rotate_immediately       = optional(bool, true)
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.rotation.enabled || var.rotation.lambda_arn != null
    error_message = "rotation.lambda_arn: required when enabled."
  }

  validation {
    condition     = var.rotation.schedule_expression != null || (var.rotation.automatically_after_days >= 1 && var.rotation.automatically_after_days <= 90)
    error_message = "rotation.automatically_after_days: 1-90 (SecretsManager.4)."
  }
}

variable "replica_regions" {
  description = "Replica Regions and optional key ARNs."
  type = map(object({
    kms_key_arn = optional(string)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for r in keys(var.replica_regions) : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", r))])
    error_message = "replica_regions: Region codes as keys."
  }

  validation {
    condition     = var.kms.key_id == null || alltrue([for r in values(var.replica_regions) : r.kms_key_arn != null])
    error_message = "replica_regions: set kms_key_arn per Region with kms.key_id."
  }
}

variable "policy_statements" {
  description = "Resource policy statements; resources default to the secret."
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
}
