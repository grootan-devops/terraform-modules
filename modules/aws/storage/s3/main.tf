module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags
  names = {
    bucket = { uniqueness = "global", max_length = 63 }
  }
}

module "encryption" {
  source = "../../core/encryption"

  application = var.application
  environment = var.environment
  name        = var.name
  purpose     = "s3"
  tags        = var.tags
  kms         = var.kms
}

module "policy" {
  source = "../../core/policy-document"

  default_resources = [local.arn, "${local.arn}/*"]
  statements        = concat(local.guard_statements, var.policy_statements)
}

#trivy:ignore:AVD-AWS-0089
resource "aws_s3_bucket" "this" {
  bucket              = local.bucket_name
  force_destroy       = false
  object_lock_enabled = var.object_lock.enabled

  tags = merge(module.naming.tags, { Name = local.bucket_name })
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    bucket_key_enabled       = local.uses_kms
    blocked_encryption_types = ["SSE-C"]

    apply_server_side_encryption_by_default {
      sse_algorithm     = local.uses_kms ? "aws:kms" : "AES256"
      kms_master_key_id = local.kms_key_arn
    }
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = module.policy.json

  depends_on = [aws_s3_bucket_public_access_block.this]
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_multipart_upload_days
    }
  }

  dynamic "rule" {
    for_each = var.noncurrent_version_expiration.enabled ? [var.noncurrent_version_expiration] : []

    content {
      id     = "expire-noncurrent-versions"
      status = "Enabled"

      filter {}

      noncurrent_version_expiration {
        noncurrent_days           = rule.value.days
        newer_noncurrent_versions = rule.value.newer_noncurrent_versions
      }
    }
  }

  dynamic "rule" {
    for_each = local.lifecycle_rules

    content {
      id     = rule.value.id
      status = rule.value.enabled ? "Enabled" : "Disabled"

      filter {
        prefix = rule.value.predicates < 2 ? rule.value.prefix : null

        dynamic "tag" {
          for_each = rule.value.predicates == 1 ? rule.value.tags : {}

          content {
            key   = tag.key
            value = tag.value
          }
        }

        dynamic "and" {
          for_each = rule.value.predicates > 1 ? [1] : []

          content {
            prefix = rule.value.prefix
            tags   = rule.value.tags
          }
        }
      }

      dynamic "expiration" {
        for_each = rule.value.expiration_days == null ? [] : [rule.value.expiration_days]

        content {
          days = expiration.value
        }
      }

      dynamic "transition" {
        for_each = rule.value.transitions

        content {
          days          = transition.value.days
          storage_class = transition.value.storage_class
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = rule.value.noncurrent_version_expiration_days == null ? [] : [rule.value.noncurrent_version_expiration_days]

        content {
          noncurrent_days = noncurrent_version_expiration.value
        }
      }

      dynamic "noncurrent_version_transition" {
        for_each = rule.value.noncurrent_version_transitions

        content {
          noncurrent_days = noncurrent_version_transition.value.days
          storage_class   = noncurrent_version_transition.value.storage_class
        }
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

resource "aws_s3_bucket_cors_configuration" "this" {
  count = length(var.cors_rules) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  dynamic "cors_rule" {
    for_each = var.cors_rules

    content {
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      allowed_headers = cors_rule.value.allowed_headers
      expose_headers  = cors_rule.value.expose_headers
      max_age_seconds = cors_rule.value.max_age_seconds
    }
  }
}

resource "aws_s3_bucket_logging" "this" {
  count = var.access_logs.enabled ? 1 : 0

  bucket        = aws_s3_bucket.this.id
  target_bucket = var.access_logs.bucket
  target_prefix = coalesce(var.access_logs.prefix, "${local.bucket_name}/")
}

resource "aws_s3_bucket_object_lock_configuration" "this" {
  count = var.object_lock.enabled && var.object_lock.mode != null ? 1 : 0

  bucket = aws_s3_bucket.this.id

  rule {
    default_retention {
      mode  = var.object_lock.mode
      days  = var.object_lock.days
      years = var.object_lock.years
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}
