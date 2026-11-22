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
  description = "Queue name."
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

variable "fifo" {
  description = "FIFO queues: deduplication and high throughput."
  type = object({
    enabled                     = optional(bool, false)
    content_based_deduplication = optional(bool, false)
    high_throughput             = optional(bool, false)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.fifo.enabled || !(var.fifo.content_based_deduplication || var.fifo.high_throughput)
    error_message = "fifo: options need enabled = true."
  }
}

variable "visibility_timeout_seconds" {
  description = "Visibility timeout in seconds (0-43200)."
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition     = var.visibility_timeout_seconds >= 0 && var.visibility_timeout_seconds <= 43200
    error_message = "visibility_timeout_seconds: 0-43200."
  }
}

variable "message_retention_seconds" {
  description = "Message retention in seconds (60-1209600)."
  type        = number
  default     = 345600
  nullable    = false

  validation {
    condition     = var.message_retention_seconds >= 60 && var.message_retention_seconds <= 1209600
    error_message = "message_retention_seconds: 60-1209600."
  }
}

variable "max_message_size" {
  description = "Maximum message size in bytes (1024-1048576)."
  type        = number
  default     = 262144
  nullable    = false

  validation {
    condition     = var.max_message_size >= 1024 && var.max_message_size <= 1048576
    error_message = "max_message_size: 1024-1048576."
  }
}

variable "delay_seconds" {
  description = "Delivery delay in seconds (0-900)."
  type        = number
  default     = 0
  nullable    = false

  validation {
    condition     = var.delay_seconds >= 0 && var.delay_seconds <= 900
    error_message = "delay_seconds: 0-900."
  }
}

variable "receive_wait_time_seconds" {
  description = "Long polling wait in seconds (0-20)."
  type        = number
  default     = 0
  nullable    = false

  validation {
    condition     = var.receive_wait_time_seconds >= 0 && var.receive_wait_time_seconds <= 20
    error_message = "receive_wait_time_seconds: 0-20."
  }
}

variable "kms" {
  description = "Encryption: {} SSE-SQS, create = true module key, key_id your key (ARN or ID)."
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

variable "kms_data_key_reuse_period_seconds" {
  description = "KMS data key reuse in seconds (60-86400)."
  type        = number
  default     = 300
  nullable    = false

  validation {
    condition     = var.kms_data_key_reuse_period_seconds >= 60 && var.kms_data_key_reuse_period_seconds <= 86400
    error_message = "kms_data_key_reuse_period_seconds: 60-86400."
  }
}

variable "dead_letter_queue" {
  description = "Dead-letter queue and redrive."
  type = object({
    enabled                   = optional(bool, true)
    max_receive_count         = optional(number, 3)
    message_retention_seconds = optional(number, 1209600)
    allowed_publishers = optional(map(object({
      principal  = string
      source_arn = string
    })), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for p in values(var.dead_letter_queue.allowed_publishers) : contains(["events.amazonaws.com", "sns.amazonaws.com"], p.principal)])
    error_message = "dead_letter_queue.allowed_publishers[*].principal: events or sns.amazonaws.com."
  }

  validation {
    condition     = var.dead_letter_queue.enabled || length(var.dead_letter_queue.allowed_publishers) == 0
    error_message = "dead_letter_queue.allowed_publishers: needs enabled = true."
  }

  validation {
    condition     = var.dead_letter_queue.max_receive_count >= 1 && var.dead_letter_queue.max_receive_count <= 1000
    error_message = "dead_letter_queue.max_receive_count: 1-1000."
  }

  validation {
    condition     = var.dead_letter_queue.message_retention_seconds >= 60 && var.dead_letter_queue.message_retention_seconds <= 1209600
    error_message = "dead_letter_queue.message_retention_seconds: 60-1209600."
  }
}

variable "allowed_publishers" {
  description = "Services allowed to send, by key: principal and source ARN."
  type = map(object({
    principal  = string
    source_arn = string
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for p in values(var.allowed_publishers) : contains(["events.amazonaws.com", "sns.amazonaws.com", "s3.amazonaws.com"], p.principal)])
    error_message = "allowed_publishers[*].principal: events, sns or s3.amazonaws.com."
  }
}

variable "policy_statements" {
  description = "Extra queue policy statements; resources default to the queue."
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

variable "alarms" {
  description = "Built-in CloudWatch alarms: switch, topics by severity, per-alarm overrides."
  type = object({
    enabled    = optional(bool, true)
    topic_arns = optional(map(string), {})
    overrides = optional(object({
      age_of_oldest_message = optional(object({ enabled = optional(bool), threshold = optional(number), evaluation_periods = optional(number), datapoints_to_alarm = optional(number), period = optional(number), severity = optional(string) }), {})
      messages_visible      = optional(object({ enabled = optional(bool), threshold = optional(number), evaluation_periods = optional(number), datapoints_to_alarm = optional(number), period = optional(number), severity = optional(string) }), {})
      dlq_messages_visible  = optional(object({ enabled = optional(bool), threshold = optional(number), evaluation_periods = optional(number), datapoints_to_alarm = optional(number), period = optional(number), severity = optional(string) }), {})
    }), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for s, arn in var.alarms.topic_arns : can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]+$", arn))])
    error_message = "alarms.topic_arns: SNS topic ARNs by severity."
  }
}
