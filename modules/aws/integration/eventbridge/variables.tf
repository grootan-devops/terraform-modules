variable "application" {
  description = "The name of the application."
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

variable "name" {
  description = "The name suffix for EventBridge resources."
  type        = string
  default     = ""
}

variable "create_bus" {
  description = "Controls whether to create a custom event bus. If false, the default bus or an existing bus name passed via rules will be used."
  type        = bool
  default     = true
}


variable "bus_name" {
  description = "The name of the event bus to create (required if create_bus is true)."
  type        = string
  default     = ""
}

variable "kms_key_arn" {
  description = "The KMS Key ARN used to encrypt the EventBridge bus. Strictly required."
  type        = string
}

variable "bus_tags" {
  description = "A map of tags to assign to the event bus."
  type        = map(string)
  default     = {}
}

variable "rules" {
  description = "Map of EventBridge rules to create. The key is the rule name."
  type = map(object({
    description         = optional(string, null)
    event_pattern       = optional(string, null)      # JSON pattern
    schedule_expression = optional(string, null)      # Cron or rate
    state               = optional(string, "ENABLED") # ENABLED, DISABLED, or ENABLED_WITH_ALL_CLOUDTRAIL_MANAGEMENT_EVENTS
    role_arn            = optional(string, null)      # IAM Role ARN associated with the rule
    force_destroy       = optional(bool, false)
    tags                = optional(map(string), {})
  }))
  default = {}
}

variable "targets" {
  description = "Map of targets to associate with the EventBridge rules."
  type = map(object({
    rule_name = string                 # Key matching a rule in the 'rules' map
    arn       = string                 # Target ARN (SNS topic, SQS queue, Step Function, etc.)
    role_arn  = optional(string, null) # IAM role ARN to assume (required for Step Functions)

    # Input modifiers
    input      = optional(string, null)
    input_path = optional(string, null)
    input_transformer = optional(object({
      input_paths    = map(string)
      input_template = string
    }), null)

    # DLQ and Retry configuration
    dead_letter_arn = optional(string, null)
    retry_policy = optional(object({
      maximum_event_age_in_seconds = optional(number, null)
      maximum_retry_attempts       = optional(number, null)
    }), null)

    # SQS Specific Target Options
    sqs_target = optional(object({
      message_group_id = optional(string, null)
    }), null)
  }))
  default = {}
}

variable "bus_policy" {
  description = "The JSON policy document to apply to the event bus."
  type        = string
  default     = null
}

variable "tags" {
  description = "Common tags to apply to all resources."
  type        = map(string)
  default     = {}
}

variable "cloudwatch_logs" {
  description = "CloudWatch logs configuration for EventBridge."
  type = object({
    retention_in_days           = number
    kms_key_arn                 = optional(string, null)
    deletion_protection_enabled = optional(bool, false)
  })
  default = null
}
