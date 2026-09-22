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
  description = "The name suffix for AWS Batch resources."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Common tags to apply to all resources."
  type        = map(string)
  default     = {}
}

# ------------------------------------------------------------------------------
# Scheduling Policy Configuration
# ------------------------------------------------------------------------------
variable "create_scheduling_policy" {
  description = "Whether to create an AWS Batch scheduling policy."
  type        = bool
  default     = false
}

variable "scheduling_policy_name" {
  description = "Custom name for the scheduling policy. If not provided, a rendered name will be used."
  type        = string
  default     = null
}

variable "scheduling_policy_fair_share_policy" {
  description = "The fair share policy block for the scheduling policy."
  type = object({
    share_decay_seconds = optional(number, 0)
    share_distribution = optional(list(object({
      share_identifier = string
      weight_factor    = optional(number, 0)
    })), [])
  })
  default = null
}

# ------------------------------------------------------------------------------
# Compute Environment Configuration
# ------------------------------------------------------------------------------
variable "compute_environments" {
  description = "Map of compute environments to create."
  type = map(object({
    type             = optional(string, "MANAGED")
    state            = optional(string, "ENABLED")
    service_role_arn = optional(string, null)

    # Compute resources configuration
    compute_resources = object({
      type               = optional(string, "FARGATE") # FARGATE or FARGATE_SPOT
      max_vcpus          = number
      security_group_ids = list(string)
      subnets            = list(string)
    })
  }))
  default = {}
}

# ------------------------------------------------------------------------------
# Job Queue Configuration
# ------------------------------------------------------------------------------
variable "job_queues" {
  description = "Map of job queues to create."
  type = map(object({
    state                 = optional(string, "ENABLED")
    priority              = number
    scheduling_policy_arn = optional(string, null)
    # List of compute environment keys (created by this module) or direct ARNs
    compute_environments = list(string)
  }))
  default = {}
}

# ------------------------------------------------------------------------------
# ECS Task IAM Configurations
# ------------------------------------------------------------------------------
variable "custom_ecs_execution_policies" {
  description = "List of additional IAM policy ARNs to attach to the ECS Task Execution Role."
  type        = list(string)
  default     = []
}

variable "custom_ecs_job_role_policies" {
  description = "List of IAM policy ARNs to attach to the ECS Task Job Role."
  type        = list(string)
  default     = []
}

# ------------------------------------------------------------------------------
# Job Definition Configuration
# ------------------------------------------------------------------------------
variable "job_definitions" {
  description = "Map of job definitions to create."
  type = map(object({
    type                  = string                 # container or multinode
    container_properties  = optional(string, null) # JSON string
    parameters            = optional(map(string), {})
    platform_capabilities = optional(list(string), ["FARGATE"]) # FARGATE or EC2

    retry_strategy = optional(object({
      attempts = optional(number, 1)
      evaluate_on_exit = optional(list(object({
        action           = string
        on_exit_code     = optional(string, null)
        on_reason        = optional(string, null)
        on_status_reason = optional(string, null)
      })), [])
    }), null)

    timeout = optional(object({
      attempt_duration_seconds = optional(number, null)
    }), null)
  }))
  default = {}
}

# ------------------------------------------------------------------------------
# EventBridge Rules & Targets for scheduling jobs
# ------------------------------------------------------------------------------
variable "custom_eventbridge_policies" {
  description = "List of additional IAM policy ARNs to attach to the automatically created EventBridge execution role."
  type        = list(string)
  default     = []
}

variable "eventbridge_rules" {
  description = "Map of EventBridge rules for scheduling or triggering jobs."
  type = map(object({
    description         = optional(string, null)
    schedule_expression = optional(string, null) # e.g. cron(0 12 * * ? *) or rate(1 hour)
    event_pattern       = optional(string, null) # JSON pattern
    state               = optional(string, "ENABLED")
    tags                = optional(map(string), {})
  }))
  default = {}
}

variable "eventbridge_targets" {
  description = "Map of EventBridge targets pointing to the AWS Batch queues and job definitions."
  type = map(object({
    rule_name          = string # Key matching a rule in the 'eventbridge_rules' map
    job_queue_key      = string # Key in 'job_queues' map or direct ARN
    job_definition_key = string # Key in 'job_definitions' map or direct ARN
    job_name           = string

    # Optional parameters to override at runtime
    attempts            = optional(number, null)
    container_overrides = optional(string, null) # JSON string representing ContainerOverrides

    # Retry and DLQ configuration for the EventBridge target itself
    dead_letter_arn = optional(string, null)
    retry_policy = optional(object({
      maximum_event_age_in_seconds = optional(number, null)
      maximum_retry_attempts       = optional(number, null)
    }), null)
  }))
  default = {}
}

variable "cloudwatch_logs" {
  description = "CloudWatch logs configuration for AWS Batch containers."
  type = object({
    retention_in_days           = number
    kms_key_arn                 = optional(string, null)
    deletion_protection_enabled = optional(bool, false)
  })
  default = null
}

variable "kms_key_arn" {
  description = "KMS Key ARN used for encrypting AWS Batch CloudWatch logs and compute storage. Strictly required."
  type        = string
}
