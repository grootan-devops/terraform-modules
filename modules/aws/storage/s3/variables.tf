# ==============================================================================
# Base Configuration
# ==============================================================================

variable "name" {
  description = "The name of the S3 bucket"
  type        = string
  default     = null
}

variable "bucket_name_override" {
  description = "Override the default S3 bucket name format with this exact string"
  type        = string
  default     = null
}

variable "application" {
  description = "Name of the product"
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

# ==============================================================================
# Encryption
# ==============================================================================

variable "kms_key_arn" {
  description = "The ARN of the KMS key to use for bucket encryption. This must be a customer-managed AWS KMS Key."
  type        = string
}

# ==============================================================================
# Versioning
# ==============================================================================

variable "enable_versioning" {
  description = "If true, bucket versioning is enabled. If false, it is suspended."
  type        = bool
  default     = true
}

# ==============================================================================
# Replication Setup
# ==============================================================================

variable "replication_configuration" {
  description = "Replication configuration object"
  type = object({
    role = optional(string)
    rules = list(object({
      id       = optional(string)
      priority = optional(number)
      status   = string

      delete_marker_replication = optional(object({
        status = string
      }))

      filter = optional(object({
        prefix = optional(string)
        tag = optional(object({
          key   = string
          value = string
        }))
        and = optional(object({
          prefix = optional(string)
          tags   = optional(map(string))
        }))
      }))

      source_selection_criteria = optional(object({
        replica_modifications = optional(object({
          status = string
        }))
        sse_kms_encrypted_objects = optional(object({
          status = string
        }))
      }))

      destination = object({
        bucket        = string
        account       = optional(string)
        storage_class = optional(string)

        access_control_translation = optional(object({
          owner = string
        }))

        encryption_configuration = optional(object({
          replica_kms_key_id = string
        }))

        metrics = optional(object({
          status = string
          event_threshold = optional(object({
            minutes = number
          }))
        }))

        replication_time = optional(object({
          status = string
          time = object({
            minutes = number
          })
        }))
      })
    }))
  })
  default = null
}

# ==============================================================================
# Access Control Lists
# ==============================================================================

variable "object_ownership" {
  description = "Object ownership. Valid values: BucketOwnerEnforced, BucketOwnerPreferred, ObjectWriter."
  type        = string
  default     = "BucketOwnerEnforced"
}

variable "access_control_policy" {
  description = "Access Control Policy to apply to the S3 bucket."
  type = object({
    owner = object({
      id = string
    })
    grants = list(object({
      grantee = object({
        type          = string
        id            = optional(string)
        uri           = optional(string)
        email_address = optional(string)
      })
      permission = string
    }))
  })
  default = null
}

# ==============================================================================
# Lifecycle Rules
# ==============================================================================

variable "lifecycle_rules" {
  description = "List of lifecycle rules to configure on the S3 bucket."
  type = list(object({
    id     = string
    status = string
    filter = optional(object({
      prefix = optional(string)
    }))
    abort_incomplete_multipart_upload = optional(object({
      days_after_initiation = number
    }))
    noncurrent_version_expiration = optional(object({
      noncurrent_days = number
    }))
    expiration = optional(object({
      days = number
    }))
    transition = optional(object({
      days          = number
      storage_class = string
    }))
  }))
  default = [
    {
      id     = "abort-incomplete-multipart"
      status = "Enabled"
      abort_incomplete_multipart_upload = {
        days_after_initiation = 7
      }
    }
  ]
}

# ==============================================================================
# Public Access Block
# ==============================================================================

variable "public_access_block" {
  description = "Public access block configuration."
  type = object({
    block_public_acls       = bool
    block_public_policy     = bool
    ignore_public_acls      = bool
    restrict_public_buckets = bool
  })
  default = {
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
  }
}

# ==============================================================================
# Bucket Policies
# ==============================================================================

variable "custom_policy_statements" {
  description = "A list of custom bucket policy statements. The `Resource` block is automatically injected into each statement for this bucket."
  type        = list(any)
  default     = []
}

variable "tags" {
  type        = map(string)
  description = "Additional tags to apply to all resources"
  default     = {}
}

# ==============================================================================
# CORS Configuration
# ==============================================================================

variable "cors_rules" {
  description = "List of CORS rules to configure for the bucket"
  type = list(object({
    allowed_headers = list(string)
    allowed_methods = list(string)
    allowed_origins = list(string)
    expose_headers  = optional(list(string))
    max_age_seconds = optional(number)
  }))
  default = []
}
