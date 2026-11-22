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

variable "kms" {
  description = "Encryption: {} SSE-S3, create = true module key, key_id your key (ARN or ID)."
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

variable "policy_statements" {
  description = "Extra bucket policy statements; resources default to the bucket and its objects."
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

variable "lifecycle_rules" {
  description = "Lifecycle rules by id; filter by prefix and tags."
  type = list(object({
    id                                 = string
    enabled                            = optional(bool, true)
    prefix                             = optional(string)
    tags                               = optional(map(string), {})
    expiration_days                    = optional(number)
    noncurrent_version_expiration_days = optional(number)
    transitions = optional(list(object({
      days          = number
      storage_class = string
    })), [])
    noncurrent_version_transitions = optional(list(object({
      days          = number
      storage_class = string
    })), [])
  }))
  default  = []
  nullable = false

  validation {
    condition     = length(distinct([for r in var.lifecycle_rules : r.id])) == length(var.lifecycle_rules) && alltrue([for r in var.lifecycle_rules : !contains(["abort-incomplete-multipart-uploads", "expire-noncurrent-versions"], r.id)])
    error_message = "lifecycle_rules: unique ids, not a module rule id."
  }

  validation {
    condition     = alltrue([for r in var.lifecycle_rules : r.expiration_days != null || r.noncurrent_version_expiration_days != null || length(r.transitions) + length(r.noncurrent_version_transitions) > 0])
    error_message = "lifecycle_rules: each rule needs an action."
  }

  validation {
    condition     = alltrue(flatten([for r in var.lifecycle_rules : [for t in concat(r.transitions, r.noncurrent_version_transitions) : contains(["STANDARD_IA", "ONEZONE_IA", "INTELLIGENT_TIERING", "GLACIER_IR", "GLACIER", "DEEP_ARCHIVE"], t.storage_class)]]))
    error_message = "lifecycle_rules: invalid transition storage class."
  }
}

variable "abort_incomplete_multipart_upload_days" {
  description = "Days before incomplete multipart uploads are aborted."
  type        = number
  default     = 7
  nullable    = false

  validation {
    condition     = var.abort_incomplete_multipart_upload_days >= 1
    error_message = "abort_incomplete_multipart_upload_days: at least 1."
  }
}

variable "noncurrent_version_expiration" {
  description = "Delete noncurrent versions after days."
  type = object({
    enabled                   = optional(bool, false)
    days                      = optional(number, 90)
    newer_noncurrent_versions = optional(number)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.noncurrent_version_expiration.days >= 1
    error_message = "noncurrent_version_expiration.days: at least 1."
  }
}

variable "cors_rules" {
  description = "CORS rules."
  type = list(object({
    allowed_methods = list(string)
    allowed_origins = list(string)
    allowed_headers = optional(list(string), [])
    expose_headers  = optional(list(string), [])
    max_age_seconds = optional(number)
  }))
  default  = []
  nullable = false
}

variable "access_logs" {
  description = "Server access logs to a log bucket (S3.9)."
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

variable "notifications" {
  description = "Event notifications (S3.11): EventBridge, SNS, SQS, Lambda."
  type = object({
    eventbridge = optional(bool, false)
    topics = optional(map(object({
      arn           = string
      events        = list(string)
      filter_prefix = optional(string)
      filter_suffix = optional(string)
    })), {})
    queues = optional(map(object({
      arn           = string
      events        = list(string)
      filter_prefix = optional(string)
      filter_suffix = optional(string)
    })), {})
    functions = optional(map(object({
      arn           = string
      events        = list(string)
      filter_prefix = optional(string)
      filter_suffix = optional(string)
    })), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue(flatten([for t in concat(values(var.notifications.topics), values(var.notifications.queues), values(var.notifications.functions)) : [for e in t.events : startswith(e, "s3:")]]))
    error_message = "notifications: events start with s3:."
  }
}

variable "object_lock" {
  description = "Object Lock (set at creation) and default retention."
  type = object({
    enabled = optional(bool, false)
    mode    = optional(string)
    days    = optional(number)
    years   = optional(number)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.object_lock.mode == null || contains(["GOVERNANCE", "COMPLIANCE"], coalesce(var.object_lock.mode, "none"))
    error_message = "object_lock.mode: GOVERNANCE or COMPLIANCE."
  }

  validation {
    condition     = var.object_lock.mode == null || (var.object_lock.days == null) != (var.object_lock.years == null)
    error_message = "object_lock: set days or years with mode."
  }

  validation {
    condition     = var.object_lock.enabled || var.object_lock.mode == null
    error_message = "object_lock: mode needs enabled."
  }
}

variable "replication" {
  description = "Replication rules and role."
  type = object({
    enabled = optional(bool, false)
    rules = optional(list(object({
      id                        = string
      destination_bucket_arn    = string
      priority                  = optional(number)
      prefix                    = optional(string)
      destination_account_id    = optional(string)
      storage_class             = optional(string)
      replica_kms_key_arn       = optional(string)
      delete_marker_replication = optional(bool, true)
      replication_time          = optional(bool, false)
    })), [])
    iam_role = optional(object({
      create                   = optional(bool, true)
      arn                      = optional(string)
      path                     = optional(string, "/")
      permissions_boundary_arn = optional(string)
    }), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.replication.enabled || length(var.replication.rules) > 0
    error_message = "replication: set rules when enabled."
  }

  validation {
    condition     = var.replication.iam_role.create || var.replication.iam_role.arn != null
    error_message = "replication.iam_role: set arn when create = false."
  }

  validation {
    condition     = !(var.kms.create || var.kms.key_id != null) || alltrue([for r in var.replication.rules : r.replica_kms_key_arn != null])
    error_message = "replication: set replica_kms_key_arn with a KMS key."
  }

  validation {
    condition     = alltrue([for r in var.replication.rules : r.storage_class == null || contains(["STANDARD", "STANDARD_IA", "ONEZONE_IA", "INTELLIGENT_TIERING", "GLACIER_IR", "GLACIER", "DEEP_ARCHIVE"], coalesce(r.storage_class, "none"))])
    error_message = "replication: invalid storage_class."
  }
}
