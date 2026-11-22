variable "application" {
  description = "Application name."
  type        = string
  default     = "platform"
  nullable    = false

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

variable "kms" {
  description = "Encryption: {} module key, or key_id your key (ARN or ID) with create = false."
  type = object({
    key_id                  = optional(string)
    create                  = optional(bool, true)
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
    condition     = var.kms.create != (var.kms.key_id != null)
    error_message = "kms: create, or key_id with create = false."
  }

  validation {
    condition     = var.kms.key_id == null || can(regex("^(arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/)?(mrk-[a-f0-9]{32}|[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})$", var.kms.key_id))
    error_message = "kms.key_id: a KMS key ARN or key ID."
  }
}

variable "trail" {
  description = "Multi-Region trail: organization scope, data events and Insights."
  type = object({
    enabled                          = optional(bool, true)
    is_organization_trail            = optional(bool, true)
    management_account_id            = optional(string)
    exclude_management_event_sources = optional(set(string), [])
    data_events = optional(object({
      s3_objects = optional(object({
        enabled         = optional(bool, false)
        bucket_arns     = optional(list(string), [])
        read_write_type = optional(string, "All")
      }), {})
      lambda_functions = optional(object({
        enabled         = optional(bool, false)
        function_arns   = optional(list(string), [])
        read_write_type = optional(string, "All")
      }), {})
      dynamodb_tables = optional(object({
        enabled         = optional(bool, false)
        table_arns      = optional(list(string), [])
        read_write_type = optional(string, "All")
      }), {})
    }), {})
    insight_types = optional(set(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.trail.management_account_id == null || can(regex("^[0-9]{12}$", var.trail.management_account_id))
    error_message = "trail.management_account_id: 12 digits."
  }

  validation {
    condition     = alltrue([for source in var.trail.exclude_management_event_sources : contains(["kms.amazonaws.com", "rdsdata.amazonaws.com"], source)])
    error_message = "trail.exclude_management_event_sources: kms.amazonaws.com or rdsdata.amazonaws.com."
  }

  validation {
    condition = alltrue([
      for selector in [var.trail.data_events.s3_objects, var.trail.data_events.lambda_functions, var.trail.data_events.dynamodb_tables] :
      contains(["All", "ReadOnly", "WriteOnly"], selector.read_write_type)
    ])
    error_message = "trail.data_events.*.read_write_type: All, ReadOnly or WriteOnly."
  }

  validation {
    condition     = alltrue([for insight in var.trail.insight_types : contains(["ApiCallRateInsight", "ApiErrorRateInsight"], insight)])
    error_message = "trail.insight_types: ApiCallRateInsight or ApiErrorRateInsight."
  }
}

variable "cloudwatch_logs" {
  description = "CloudWatch log group for trail events."
  type = object({
    enabled                     = optional(bool, true)
    retention_in_days           = optional(number, 365)
    log_group_class             = optional(string, "STANDARD")
    deletion_protection_enabled = optional(bool, true)
    kms_key_arn                 = optional(string)
  })
  default  = {}
  nullable = false
}

variable "iam_role" {
  description = "Log delivery role: extend it or bring your own."
  type = object({
    create                   = optional(bool, true)
    arn                      = optional(string)
    name                     = optional(string)
    path                     = optional(string, "/")
    permissions_boundary_arn = optional(string)
    managed_policy_arns      = optional(list(string), [])
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
    condition     = var.iam_role.create || var.iam_role.arn != null
    error_message = "iam_role: set arn when create = false."
  }
}

variable "bucket" {
  description = "Log bucket: create one or name an existing one."
  type = object({
    enabled               = optional(bool, true)
    name                  = optional(string)
    key_prefix            = optional(string)
    organization_id       = optional(string)
    additional_trail_arns = optional(list(string), [])
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
    lifecycle = optional(object({
      transition_to_glacier_days      = optional(number, 90)
      transition_to_deep_archive_days = optional(number, 365)
      expiration_days                 = optional(number, 2557)
      noncurrent_expiration_days      = optional(number, 365)
      abort_incomplete_multipart_days = optional(number, 7)
    }), {})
    object_lock = optional(object({
      enabled = optional(bool, false)
      mode    = optional(string, "GOVERNANCE")
      days    = optional(number, 365)
    }), {})
    access_logs = optional(object({
      enabled = optional(bool, false)
      bucket  = optional(string)
      prefix  = optional(string)
    }), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.bucket.enabled || !var.trail.enabled || var.bucket.name != null
    error_message = "bucket.name: required when bucket.enabled = false."
  }

  validation {
    condition     = var.bucket.name == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket.name))
    error_message = "bucket.name: a valid S3 bucket name."
  }

  validation {
    condition     = var.bucket.organization_id == null || can(regex("^o-[a-z0-9]{10,32}$", var.bucket.organization_id))
    error_message = "bucket.organization_id: o- and 10-32 chars."
  }

  validation {
    condition     = alltrue([for arn in var.bucket.additional_trail_arns : can(regex("^arn:aws[a-z-]*:cloudtrail:[a-z0-9-]+:[0-9]{12}:trail/[A-Za-z0-9._-]+$", arn))])
    error_message = "bucket.additional_trail_arns: CloudTrail trail ARNs."
  }

  validation {
    condition     = !var.bucket.enabled || var.trail.enabled || length(var.bucket.additional_trail_arns) > 0
    error_message = "bucket: needs trail.enabled or additional_trail_arns."
  }

  validation {
    condition = (
      alltrue([for days in values(var.bucket.lifecycle) : days >= 0 && floor(days) == days]) &&
      var.bucket.lifecycle.abort_incomplete_multipart_days >= 1 &&
      (var.bucket.lifecycle.transition_to_glacier_days > 0 && var.bucket.lifecycle.transition_to_deep_archive_days > 0 ? var.bucket.lifecycle.transition_to_deep_archive_days >= var.bucket.lifecycle.transition_to_glacier_days + 90 : true) &&
      (var.bucket.lifecycle.expiration_days > 0 ? var.bucket.lifecycle.expiration_days > max(var.bucket.lifecycle.transition_to_glacier_days, var.bucket.lifecycle.transition_to_deep_archive_days) : true)
    )
    error_message = "bucket.lifecycle: whole days, abort 1+, Deep Archive 90+ days after Glacier, expiration last."
  }

  validation {
    condition     = contains(["GOVERNANCE", "COMPLIANCE"], var.bucket.object_lock.mode) && var.bucket.object_lock.days > 0
    error_message = "bucket.object_lock: GOVERNANCE or COMPLIANCE, days > 0."
  }

  validation {
    condition     = !var.bucket.access_logs.enabled || var.bucket.access_logs.bucket != null
    error_message = "bucket.access_logs.bucket: required when enabled."
  }
}

variable "organization_admin" {
  description = "Management account call: trusted access and delegated administrators."
  type = object({
    enabled               = optional(bool, false)
    account_ids           = optional(list(string), [])
    manage_trusted_access = optional(bool, true)
  })
  default  = {}
  nullable = false

  validation {
    condition     = length(var.organization_admin.account_ids) <= 3 && alltrue([for id in var.organization_admin.account_ids : can(regex("^[0-9]{12}$", id))])
    error_message = "organization_admin.account_ids: up to 3 account IDs."
  }

  validation {
    condition     = var.organization_admin.enabled || length(var.organization_admin.account_ids) == 0
    error_message = "organization_admin: set enabled with account_ids."
  }
}
