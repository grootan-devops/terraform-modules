variable "application" {
  description = "Application name."
  type        = string
  default     = "platform"

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

variable "tags" {
  description = "Extra tags; governance tags win."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "regions" {
  description = "Regions with topics. Empty: provider Region."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for r in var.regions : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", r))])
    error_message = "regions: Region codes."
  }
}

variable "severities" {
  description = "Severity levels; one topic each per Region."
  type        = list(string)
  default     = ["critical", "warning", "info"]
  nullable    = false

  validation {
    condition     = length(var.severities) > 0 && alltrue([for s in var.severities : can(regex("^[a-z][a-z0-9-]{0,31}$", s))])
    error_message = "severities: 1-32 chars, a-z 0-9 -, starts with a letter."
  }
}

variable "kms" {
  description = "Encryption: create = true module key (default) or key_id your key (ARN or ID)."
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
  default  = { create = true }
  nullable = false

  validation {
    condition     = !(var.kms.create && var.kms.key_id != null)
    error_message = "kms: set create or key_id, not both."
  }

  validation {
    condition     = var.kms.key_id == null || can(regex("^(arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/)?(mrk-[a-f0-9]{32}|[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})$", var.kms.key_id))
    error_message = "kms.key_id: a KMS key ARN or key ID."
  }

  validation {
    condition     = var.kms.create || var.kms.key_id != null
    error_message = "kms: create = true or key_id; alarms cannot use aws/sns."
  }

  validation {
    condition     = var.kms.key_id == null || length(distinct(var.regions)) <= 1 || startswith(coalesce(var.kms.key_id, "-"), "mrk-")
    error_message = "kms.key_id: an mrk- key ID for several Regions."
  }
}

variable "email_subscriptions" {
  description = "Email addresses by severity."
  type        = map(list(string))
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for s, addresses in var.email_subscriptions : contains(var.severities, s) && alltrue([for a in addresses : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", a))])])
    error_message = "email_subscriptions: known severities, email addresses."
  }
}

variable "https_subscriptions" {
  description = "HTTPS endpoints by severity."
  type = map(list(object({
    url                             = string
    raw_message_delivery            = optional(bool, false)
    endpoint_auto_confirms          = optional(bool, false)
    confirmation_timeout_in_minutes = optional(number, 1)
  })))
  default   = {}
  nullable  = false
  sensitive = true

  validation {
    condition     = alltrue([for s, endpoints in var.https_subscriptions : contains(var.severities, s) && alltrue([for e in endpoints : startswith(e.url, "https://") && e.confirmation_timeout_in_minutes >= 1])])
    error_message = "https_subscriptions: known severities, https:// URLs, timeout >= 1."
  }
}

variable "https_delivery_policy" {
  description = "Retry policy for HTTPS subscriptions."
  type = object({
    enabled                 = optional(bool, false)
    min_delay_target        = optional(number, 1)
    max_delay_target        = optional(number, 60)
    num_retries             = optional(number, 50)
    num_no_delay_retries    = optional(number, 3)
    num_min_delay_retries   = optional(number, 2)
    num_max_delay_retries   = optional(number, 35)
    backoff_function        = optional(string, "exponential")
    max_receives_per_second = optional(number)
    header_content_type     = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition = (
      var.https_delivery_policy.min_delay_target >= 1 &&
      var.https_delivery_policy.min_delay_target <= var.https_delivery_policy.max_delay_target &&
      var.https_delivery_policy.max_delay_target <= 3600 &&
      var.https_delivery_policy.num_retries >= 0 && var.https_delivery_policy.num_retries <= 100 &&
      var.https_delivery_policy.num_no_delay_retries >= 0 && var.https_delivery_policy.num_min_delay_retries >= 0 && var.https_delivery_policy.num_max_delay_retries >= 0 &&
      var.https_delivery_policy.num_no_delay_retries + var.https_delivery_policy.num_min_delay_retries + var.https_delivery_policy.num_max_delay_retries <= var.https_delivery_policy.num_retries &&
      contains(["arithmetic", "exponential", "geometric", "linear"], var.https_delivery_policy.backoff_function) &&
      coalesce(var.https_delivery_policy.max_receives_per_second, 1) >= 1
    )
    error_message = "https_delivery_policy: invalid retry settings."
  }
}

variable "dead_letter_queue_arns" {
  description = "SQS dead-letter queue ARN by Region."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for r, arn in var.dead_letter_queue_arns : can(regex("^arn:aws[a-z-]*:sqs:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]+$", arn)) && split(":", arn)[3] == r])
    error_message = "dead_letter_queue_arns: SQS ARNs in their Region."
  }
}

variable "additional_publisher_service_principals" {
  description = "Extra service principals that may publish."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for p in var.additional_publisher_service_principals : can(regex("^[a-z0-9-]+(\\.[a-z0-9-]+)*\\.amazonaws\\.com$", p)) && p != "cloudwatch.amazonaws.com"])
    error_message = "additional_publisher_service_principals: service principals, not cloudwatch."
  }
}
