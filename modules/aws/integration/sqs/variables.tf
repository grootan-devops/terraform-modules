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
  description = "The name suffix for SQS resources."
  type        = string
}

variable "visibility_timeout_seconds" {
  description = "The visibility timeout for the queue in seconds."
  type        = number
  default     = 30
}

variable "message_retention_seconds" {
  description = "The number of seconds Amazon SQS retains a message."
  type        = number
  default     = 345600 # 4 days
}

variable "max_message_size" {
  description = "The limit of how many bytes a message can contain before Amazon SQS rejects it."
  type        = number
  default     = 262144 # 256 KiB
}

variable "delay_seconds" {
  description = "The time in seconds that the delivery of all messages in the queue will be delayed."
  type        = number
  default     = 0
}

variable "receive_wait_time_seconds" {
  description = "The time for which a ReceiveMessage call will wait for a message to arrive before returning."
  type        = number
  default     = 0
}

variable "policy" {
  description = "The JSON policy document to apply to the queue."
  type        = string
  default     = null
}

variable "allow_eventbridge" {
  description = "Whether to allow EventBridge to send messages to this SQS queue."
  type        = bool
  default     = false
}

variable "redrive_policy" {
  description = "The JSON policy to set up the Dead Letter Queue redrive."
  type        = string
  default     = null
}

variable "redrive_allow_policy" {
  description = "The JSON policy to set up the Dead Letter Queue redrive allow."
  type        = string
  default     = null
}

variable "fifo_queue" {
  description = "Boolean designating a FIFO queue."
  type        = bool
  default     = false
}

variable "content_based_deduplication" {
  description = "Enables content-based deduplication for FIFO queues."
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "The ARN of a KMS customer managed key (CMK) for Amazon SQS encryption at rest."
  type        = string
}

variable "kms_data_key_reuse_period_seconds" {
  description = "The length of time, in seconds, for which Amazon SQS can reuse a data key to encrypt or decrypt messages before calling AWS KMS again."
  type        = number
  default     = 300
}

variable "tags" {
  description = "A map of tags to assign to the SQS queue."
  type        = map(string)
  default     = {}
}

variable "create_dlq" {
  description = "Controls whether to create a Dead Letter Queue (DLQ) for this SQS queue."
  type        = bool
  default     = true
}

variable "max_receive_count" {
  description = "The number of times a message is delivered to the source queue before being moved to the dead-letter queue."
  type        = number
  default     = 3
}
