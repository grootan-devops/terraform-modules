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
  description = "Bucket name."
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

variable "bucket_name" {
  description = "Exact bucket name. Null: derived."
  type        = string
  default     = null

  validation {
    condition     = var.bucket_name == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name: 3-63 chars, a-z 0-9 . -."
  }
}

variable "source_account_ids" {
  description = "Accounts that deliver logs. Empty: this account."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for a in var.source_account_ids : can(regex("^[0-9]{12}$", a))])
    error_message = "source_account_ids: 12-digit account IDs."
  }
}

variable "expiration_days" {
  description = "Days before log objects expire."
  type        = number
  default     = 365
  nullable    = false

  validation {
    condition     = var.expiration_days >= 1
    error_message = "expiration_days: at least 1."
  }
}

variable "noncurrent_version_expiration_days" {
  description = "Days before expired log versions are deleted."
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition     = var.noncurrent_version_expiration_days >= 1
    error_message = "noncurrent_version_expiration_days: at least 1."
  }
}

variable "transitions" {
  description = "Storage class transitions for log objects."
  type = list(object({
    days          = number
    storage_class = string
  }))
  default  = []
  nullable = false

  validation {
    condition     = alltrue([for t in var.transitions : contains(["STANDARD_IA", "ONEZONE_IA", "INTELLIGENT_TIERING", "GLACIER_IR", "GLACIER", "DEEP_ARCHIVE"], t.storage_class)])
    error_message = "transitions: invalid storage class."
  }
}

variable "s3_access_logs" {
  description = "S3 server access logs; source buckets limit the writers."
  type = object({
    enabled            = optional(bool, true)
    source_bucket_arns = optional(list(string), [])
  })
  default  = {}
  nullable = false
}

variable "elb_logs" {
  description = "Load balancer access and connection logs under prefix."
  type = object({
    enabled = optional(bool, false)
    prefix  = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.elb_logs.prefix == null || !can(regex("AWSLogs", coalesce(var.elb_logs.prefix, "-"))) && !endswith(coalesce(var.elb_logs.prefix, "-"), "/")
    error_message = "elb_logs.prefix: no AWSLogs, no trailing /."
  }
}

variable "vended_logs" {
  description = "Logs from delivery.logs.amazonaws.com (CloudFront, VPC flow logs, WAF, NLB)."
  type = object({
    enabled     = optional(bool, false)
    source_arns = optional(list(string), [])
  })
  default  = {}
  nullable = false
}

variable "access_logs" {
  description = "This bucket's own server access logs to another bucket (S3.9)."
  type = object({
    enabled = optional(bool, false)
    bucket  = optional(string)
    prefix  = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.access_logs.enabled || var.access_logs.bucket != null
    error_message = "access_logs: set bucket when enabled."
  }
}
