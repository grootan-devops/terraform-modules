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
  description = "Name suffix for the state machine (e.g. document-pipeline)."
  type        = string
}

variable "definition" {
  description = "Amazon States Language definition (JSON string)."
  type        = string
}

variable "type" {
  description = "State machine type: STANDARD or EXPRESS."
  type        = string
  default     = "STANDARD"
}

variable "lambda_function_arns" {
  description = "Lambda function ARNs the state machine may invoke (lambda task targets)."
  type        = list(string)
  default     = []
}

variable "tracing_enabled" {
  description = "Enable AWS X-Ray tracing for the state machine."
  type        = bool
  default     = true
}

variable "cloudwatch_logs" {
  description = "CloudWatch logging configuration for the state machine."
  type = object({
    retention_in_days           = number
    kms_key_arn                 = optional(string, null)
    deletion_protection_enabled = optional(bool, false)
    level                       = optional(string, "ALL") # ALL | ERROR | FATAL | OFF
  })
}

variable "tags" {
  description = "Common tags to apply to all resources."
  type        = map(string)
  default     = {}
}

variable "kms_key_arn" {
  description = "KMS Key ARN used for encrypting State Machine execution history and CloudWatch logs. Strictly required."
  type        = string
}
