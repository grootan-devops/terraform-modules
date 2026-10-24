mock_provider "aws" {}

variables {
  application = "core"
  environment = "prod"
  name        = "assets"
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
}

run "verify_naming" {
  command = plan

  assert {
    condition     = aws_s3_bucket.this.bucket == "core-prod-assets"
    error_message = "Bucket name must render as <application>-<environment>-<name>."
  }

  assert {
    condition     = aws_s3_bucket.this.tags["Name"] == "core-prod-assets"
    error_message = "Bucket Name tag must match the rendered bucket name."
  }
}

run "verify_name_fallback_when_null" {
  command = plan

  variables {
    name = null
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "core-prod"
    error_message = "Bucket name must fall back to <application>-<environment> when name is null."
  }
}

run "verify_name_fallback_when_empty" {
  command = plan

  variables {
    name = ""
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "core-prod"
    error_message = "Bucket name must fall back to <application>-<environment> when name is empty."
  }
}

run "verify_bucket_name_override" {
  command = plan

  variables {
    bucket_name_override = "core-prod-assets-us-west-2-123456789012"
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "core-prod-assets-us-west-2-123456789012"
    error_message = "bucket_name_override must replace the rendered bucket name verbatim."
  }

  assert {
    condition     = aws_s3_bucket.this.tags["Name"] == "core-prod-assets-us-west-2-123456789012"
    error_message = "Bucket Name tag must follow bucket_name_override."
  }
}

run "verify_tags" {
  command = plan

  variables {
    tags = {
      DataClassification = "Confidential"
      CostCenter         = "1234"
    }
  }

  assert {
    condition     = aws_s3_bucket.this.tags["Application"] == "core" && aws_s3_bucket.this.tags["Environment"] == "prod" && aws_s3_bucket.this.tags["Name"] == "core-prod-assets"
    error_message = "Bucket must carry Application, Environment and Name governance tags."
  }

  assert {
    condition     = aws_s3_bucket.this.tags["DataClassification"] == "Confidential" && aws_s3_bucket.this.tags["CostCenter"] == "1234"
    error_message = "Caller tags must be preserved on the bucket."
  }
}

run "verify_security_defaults" {
  command = plan

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "aws:kms"
    error_message = "Bucket default encryption must be SSE-KMS."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default[0].kms_master_key_id == var.kms_key_arn
    error_message = "Bucket default encryption must use the caller-supplied KMS key."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule).bucket_key_enabled == true
    error_message = "S3 Bucket Keys must be enabled (bucket_key_enabled = true)."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_acls && aws_s3_bucket_public_access_block.this.block_public_policy && aws_s3_bucket_public_access_block.this.ignore_public_acls && aws_s3_bucket_public_access_block.this.restrict_public_buckets
    error_message = "All four public access blocks must be enabled."
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning must be enabled by default."
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].mfa_delete == "Disabled"
    error_message = "MFA delete must be explicitly set to Disabled."
  }

  assert {
    condition     = aws_s3_bucket_ownership_controls.this.rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "Object ownership must default to BucketOwnerEnforced (ACLs disabled)."
  }

  assert {
    condition     = aws_s3_bucket.this.force_destroy == false && aws_s3_bucket.this.object_lock_enabled == false
    error_message = "Bucket must not be force-destroyable and object lock must be off by default."
  }
}

run "verify_tls_bucket_policy" {
  command = apply

  override_resource {
    target = aws_s3_bucket.this
    values = {
      id  = "core-prod-assets"
      arn = "arn:aws:s3:::core-prod-assets"
    }
  }

  assert {
    condition     = aws_s3_bucket_policy.this.bucket == "core-prod-assets"
    error_message = "Bucket policy must be attached to the module's bucket."
  }

  assert {
    condition     = length(jsondecode(aws_s3_bucket_policy.this.policy).Statement) == 2
    error_message = "Bucket policy must contain exactly the two TLS deny statements when no custom statements are given."
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement :
      s.Sid == "EnforceTLSRequestsOnly" && s.Effect == "Deny" && s.Principal == "*" && s.Action == "s3:*" && s.Condition.Bool["aws:SecureTransport"] == "false"
    ])
    error_message = "Bucket policy must deny all s3 actions when aws:SecureTransport is false."
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement :
      s.Sid == "EnforceTLSVersion" && s.Effect == "Deny" && s.Principal == "*" && s.Action == "s3:*" && s.Condition.NumericLessThan["s3:TlsVersion"] == "1.2"
    ])
    error_message = "Bucket policy must deny all s3 actions when s3:TlsVersion is below 1.2."
  }

  assert {
    condition = alltrue([
      for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement :
      s.Resource == ["arn:aws:s3:::core-prod-assets", "arn:aws:s3:::core-prod-assets/*"]
    ])
    error_message = "TLS deny statements must cover both the bucket and every object in it."
  }

  assert {
    condition     = output.bucket_arn == "arn:aws:s3:::core-prod-assets" && output.bucket_name == "core-prod-assets"
    error_message = "bucket_arn and bucket_name outputs must expose the bucket."
  }
}

run "verify_deprecated_public_access_block_ignored" {
  command = plan

  variables {
    public_access_block = {
      block_public_acls       = false
      block_public_policy     = false
      ignore_public_acls      = false
      restrict_public_buckets = false
    }
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.this.block_public_acls && aws_s3_bucket_public_access_block.this.block_public_policy && aws_s3_bucket_public_access_block.this.ignore_public_acls && aws_s3_bucket_public_access_block.this.restrict_public_buckets
    error_message = "The deprecated public_access_block input must be ignored; all four public access blocks must stay enabled."
  }
}

run "verify_parameter_defaults" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this.rule) == 1
    error_message = "Exactly one default lifecycle rule must be configured."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this.rule[0].id == "abort-incomplete-multipart" && aws_s3_bucket_lifecycle_configuration.this.rule[0].status == "Enabled"
    error_message = "Default lifecycle rule must be the enabled abort-incomplete-multipart rule."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this.rule[0].abort_incomplete_multipart_upload[0].days_after_initiation == 7
    error_message = "Default lifecycle rule must abort incomplete multipart uploads after 7 days."
  }

  assert {
    condition     = length(aws_s3_bucket_cors_configuration.this) == 0
    error_message = "No CORS configuration must be created by default."
  }

  assert {
    condition     = length(aws_s3_bucket_acl.this) == 0
    error_message = "No bucket ACL must be created by default."
  }

  assert {
    condition     = length(aws_s3_bucket_replication_configuration.this) == 0
    error_message = "No replication configuration must be created by default."
  }

  assert {
    condition     = length(aws_iam_role.replication) == 0 && length(aws_iam_policy.replication) == 0 && length(aws_iam_role_policy_attachment.replication) == 0
    error_message = "No replication IAM resources must be created by default."
  }
}

run "verify_parameter_overrides" {
  command = apply

  variables {
    enable_versioning = false
    object_ownership  = "BucketOwnerPreferred"

    lifecycle_rules = [
      {
        id     = "transition-cold-storage"
        status = "Enabled"
        filter = {
          prefix = "logs/"
        }
        transition = {
          days          = 30
          storage_class = "STANDARD_IA"
        }
        noncurrent_version_expiration = {
          noncurrent_days = 90
        }
        expiration = {
          days = 365
        }
      }
    ]

    cors_rules = [
      {
        allowed_headers = ["*"]
        allowed_methods = ["GET", "HEAD"]
        allowed_origins = ["https://app.example.com"]
        expose_headers  = ["ETag"]
        max_age_seconds = 3600
      }
    ]

    custom_policy_statements = [
      {
        Sid       = "AllowWorkerRole"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::123456789012:role/core-prod-worker" }
        Action    = ["s3:GetObject", "s3:PutObject"]
      }
    ]

    access_control_policy = {
      owner = {
        id = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
      }
      grants = [
        {
          grantee = {
            type = "CanonicalUser"
            id   = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
          }
          permission = "FULL_CONTROL"
        }
      ]
    }
  }

  override_resource {
    target = aws_s3_bucket.this
    values = {
      id  = "core-prod-assets"
      arn = "arn:aws:s3:::core-prod-assets"
    }
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Suspended"
    error_message = "enable_versioning = false must suspend versioning."
  }

  assert {
    condition     = aws_s3_bucket_ownership_controls.this.rule[0].object_ownership == "BucketOwnerPreferred"
    error_message = "object_ownership must flow through to the ownership controls."
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this.rule) == 1 && aws_s3_bucket_lifecycle_configuration.this.rule[0].id == "transition-cold-storage"
    error_message = "Caller lifecycle_rules must replace the default lifecycle rule."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this.rule[0].filter[0].prefix == "logs/"
    error_message = "Lifecycle rule filter prefix must flow through."
  }

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this.rule[0].transition).days == 30 && one(aws_s3_bucket_lifecycle_configuration.this.rule[0].transition).storage_class == "STANDARD_IA"
    error_message = "Lifecycle rule transition must flow through."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this.rule[0].noncurrent_version_expiration[0].noncurrent_days == 90 && aws_s3_bucket_lifecycle_configuration.this.rule[0].expiration[0].days == 365
    error_message = "Lifecycle rule noncurrent version expiration and expiration must flow through."
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this.rule[0].abort_incomplete_multipart_upload) == 0
    error_message = "abort_incomplete_multipart_upload must be omitted when the rule does not set it."
  }

  assert {
    condition     = length(aws_s3_bucket_cors_configuration.this) == 1
    error_message = "A CORS configuration must be created when cors_rules are supplied."
  }

  assert {
    condition     = one(aws_s3_bucket_cors_configuration.this[0].cors_rule).allowed_origins == toset(["https://app.example.com"]) && one(aws_s3_bucket_cors_configuration.this[0].cors_rule).allowed_methods == toset(["GET", "HEAD"])
    error_message = "CORS allowed origins and methods must flow through."
  }

  assert {
    condition     = one(aws_s3_bucket_cors_configuration.this[0].cors_rule).max_age_seconds == 3600 && one(aws_s3_bucket_cors_configuration.this[0].cors_rule).expose_headers == toset(["ETag"])
    error_message = "CORS max age and exposed headers must flow through."
  }

  assert {
    condition     = length(aws_s3_bucket_acl.this) == 1 && aws_s3_bucket_acl.this[0].access_control_policy[0].owner[0].id == "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    error_message = "A bucket ACL must be created from access_control_policy."
  }

  assert {
    condition     = one(aws_s3_bucket_acl.this[0].access_control_policy[0].grant).permission == "FULL_CONTROL" && one(aws_s3_bucket_acl.this[0].access_control_policy[0].grant).grantee[0].type == "CanonicalUser"
    error_message = "Bucket ACL grants must flow through."
  }

  assert {
    condition     = length(jsondecode(aws_s3_bucket_policy.this.policy).Statement) == 3
    error_message = "Custom policy statements must be appended after the two TLS deny statements."
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this.policy).Statement[0].Sid == "EnforceTLSRequestsOnly" && jsondecode(aws_s3_bucket_policy.this.policy).Statement[1].Sid == "EnforceTLSVersion"
    error_message = "Custom policy statements must not displace the TLS deny statements."
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this.policy).Statement[2].Sid == "AllowWorkerRole" && jsondecode(aws_s3_bucket_policy.this.policy).Statement[2].Effect == "Allow"
    error_message = "Custom policy statement must be rendered into the bucket policy."
  }

  assert {
    condition     = jsondecode(aws_s3_bucket_policy.this.policy).Statement[2].Resource == ["arn:aws:s3:::core-prod-assets", "arn:aws:s3:::core-prod-assets/*"]
    error_message = "The bucket and object Resource must be injected into custom policy statements."
  }
}

run "verify_replication_creates_role" {
  command = apply

  variables {
    replication_configuration = {
      rules = [
        {
          id     = "replicate-all"
          status = "Enabled"
          delete_marker_replication = {
            status = "Enabled"
          }
          destination = {
            bucket        = "arn:aws:s3:::core-prod-assets-replica"
            storage_class = "STANDARD_IA"
            encryption_configuration = {
              replica_kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/87654321-4321-4321-4321-210987654321"
            }
          }
        }
      ]
    }
  }

  override_resource {
    target = aws_s3_bucket.this
    values = {
      id  = "core-prod-assets"
      arn = "arn:aws:s3:::core-prod-assets"
    }
  }

  override_resource {
    target = aws_iam_role.replication
    values = {
      arn = "arn:aws:iam::123456789012:role/core-prod-assets-replication-role"
    }
  }

  override_resource {
    target = aws_iam_policy.replication
    values = {
      arn = "arn:aws:iam::123456789012:policy/core-prod-assets-replication-policy"
    }
  }

  assert {
    condition     = length(aws_iam_role.replication) == 1 && aws_iam_role.replication[0].name == "core-prod-assets-replication-role"
    error_message = "A replication role named <rendered_name>-replication-role must be created when no role is supplied."
  }

  assert {
    condition     = aws_iam_role.replication[0].tags["Application"] == "core" && aws_iam_role.replication[0].tags["Environment"] == "prod" && aws_iam_role.replication[0].tags["Name"] == "core-prod-assets"
    error_message = "Replication role must carry the governance tags."
  }

  assert {
    condition     = jsondecode(aws_iam_role.replication[0].assume_role_policy).Statement[0].Principal.Service == "s3.amazonaws.com"
    error_message = "Replication role must only be assumable by the S3 service."
  }

  assert {
    condition     = length(aws_iam_policy.replication) == 1 && aws_iam_policy.replication[0].name == "core-prod-assets-replication-policy"
    error_message = "A replication policy named <rendered_name>-replication-policy must be created."
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_iam_policy.replication[0].policy).Statement :
      contains(s.Action, "s3:ReplicateObject") && s.Resource == ["arn:aws:s3:::core-prod-assets-replica/*"]
    ])
    error_message = "Replication policy must scope replicate actions to the destination bucket objects."
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_iam_policy.replication[0].policy).Statement :
      contains(s.Action, "kms:Decrypt") && s.Resource == [var.kms_key_arn]
    ])
    error_message = "Replication policy must allow decrypting with the source bucket KMS key."
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_iam_policy.replication[0].policy).Statement :
      contains(s.Action, "kms:Encrypt") && s.Resource == ["arn:aws:kms:us-east-1:123456789012:key/87654321-4321-4321-4321-210987654321"]
    ])
    error_message = "Replication policy must allow encrypting with the replica KMS key."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.replication) == 1
    error_message = "Replication policy must be attached to the replication role."
  }

  assert {
    condition     = aws_s3_bucket_replication_configuration.this[0].role == "arn:aws:iam::123456789012:role/core-prod-assets-replication-role"
    error_message = "Replication configuration must use the module-created role."
  }

  assert {
    condition     = aws_s3_bucket_replication_configuration.this[0].rule[0].destination[0].bucket == "arn:aws:s3:::core-prod-assets-replica" && aws_s3_bucket_replication_configuration.this[0].rule[0].destination[0].storage_class == "STANDARD_IA"
    error_message = "Replication destination bucket and storage class must flow through."
  }

  assert {
    condition     = aws_s3_bucket_replication_configuration.this[0].rule[0].delete_marker_replication[0].status == "Enabled"
    error_message = "Replication delete marker setting must flow through."
  }
}

run "verify_replication_with_existing_role" {
  command = plan

  variables {
    replication_configuration = {
      role = "arn:aws:iam::123456789012:role/core-prod-existing-replication"
      rules = [
        {
          status = "Enabled"
          destination = {
            bucket = "arn:aws:s3:::core-prod-assets-replica"
          }
        }
      ]
    }
  }

  assert {
    condition     = length(aws_iam_role.replication) == 0 && length(aws_iam_policy.replication) == 0 && length(aws_iam_role_policy_attachment.replication) == 0
    error_message = "No replication IAM resources must be created when a role is supplied."
  }

  assert {
    condition     = aws_s3_bucket_replication_configuration.this[0].role == "arn:aws:iam::123456789012:role/core-prod-existing-replication"
    error_message = "Replication configuration must use the caller-supplied role."
  }
}

run "verify_invalid_environment_fails" {
  command = plan

  variables {
    environment = "INVALID_UPPERCASE"
  }

  expect_failures = [var.environment]
}
