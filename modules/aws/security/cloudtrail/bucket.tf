locals {
  bucket_name     = var.bucket.enabled ? coalesce(var.bucket.name, module.naming.names.bucket) : var.bucket.name
  bucket_arn      = "${local.arn_prefix}:s3:::${coalesce(local.bucket_name, "none")}"
  key_prefix      = var.bucket.key_prefix == null ? null : (trim(var.bucket.key_prefix, "/") == "" ? null : trim(var.bucket.key_prefix, "/"))
  key_prefix_path = local.key_prefix == null ? "" : "${local.key_prefix}/"
  organization_id = var.bucket.organization_id != null ? var.bucket.organization_id : try(data.aws_organizations_organization.this[0].id, null)

  lifecycle_transitions = [
    for transition in [
      { days = var.bucket.lifecycle.transition_to_glacier_days, storage_class = "GLACIER" },
      { days = var.bucket.lifecycle.transition_to_deep_archive_days, storage_class = "DEEP_ARCHIVE" },
    ] : transition if transition.days > 0
  ]

  bucket_lifecycle_rules = [
    for rule in [{
      id                                 = "cloudtrail-log-retention"
      expiration_days                    = var.bucket.lifecycle.expiration_days > 0 ? var.bucket.lifecycle.expiration_days : null
      noncurrent_version_expiration_days = var.bucket.lifecycle.noncurrent_expiration_days > 0 ? var.bucket.lifecycle.noncurrent_expiration_days : null
      transitions                        = local.lifecycle_transitions
    }] : rule if rule.expiration_days != null || rule.noncurrent_version_expiration_days != null || length(rule.transitions) > 0
  ]

  bucket_object_lock = {
    enabled = var.bucket.object_lock.enabled
    mode    = var.bucket.object_lock.enabled ? var.bucket.object_lock.mode : null
    days    = var.bucket.object_lock.enabled ? var.bucket.object_lock.days : null
  }

  bucket_statement_candidates = [
    {
      when = local.trail_writers
      statement = {
        sid        = "AWSCloudTrailAclCheck"
        effect     = "Allow"
        actions    = ["s3:GetBucketAcl"]
        resources  = [local.bucket_arn]
        principals = { Service = ["cloudtrail.amazonaws.com"] }
        conditions = [{ test = "StringEquals", variable = "aws:SourceArn", values = local.trail_arns }]
      }
    },
    {
      when = local.trail_writers
      statement = {
        sid        = "AWSCloudTrailWrite"
        effect     = "Allow"
        actions    = ["s3:PutObject"]
        resources  = [for account_id in local.trail_owner_accounts : "${local.bucket_arn}/${local.key_prefix_path}AWSLogs/${account_id}/*"]
        principals = { Service = ["cloudtrail.amazonaws.com"] }
        conditions = [
          { test = "StringEquals", variable = "s3:x-amz-acl", values = ["bucket-owner-full-control"] },
          { test = "StringEquals", variable = "aws:SourceArn", values = local.trail_arns },
        ]
      }
    },
    {
      when = local.trail_writers && local.organization_id != null
      statement = {
        sid        = "AWSCloudTrailOrganizationWrite"
        effect     = "Allow"
        actions    = ["s3:PutObject"]
        resources  = ["${local.bucket_arn}/${local.key_prefix_path}AWSLogs/${coalesce(local.organization_id, "none")}/*"]
        principals = { Service = ["cloudtrail.amazonaws.com"] }
        conditions = [
          { test = "StringEquals", variable = "s3:x-amz-acl", values = ["bucket-owner-full-control"] },
          { test = "StringEquals", variable = "aws:SourceArn", values = local.trail_arns },
        ]
      }
    },
  ]

  bucket_statements = [for c in local.bucket_statement_candidates : c.statement if c.when]
}

data "aws_organizations_organization" "this" {
  count = var.bucket.enabled && var.trail.enabled && var.trail.is_organization_trail ? 1 : 0

  return_organization_only = true
}

module "bucket" {
  source = "../../storage/s3"
  count  = var.bucket.enabled ? 1 : 0

  application                            = var.application
  environment                            = var.environment
  name                                   = "cloudtrail"
  tags                                   = var.tags
  bucket_name                            = var.bucket.name
  kms                                    = { key_id = local.kms_key_arn }
  policy_statements                      = concat(local.bucket_statements, var.bucket.policy_statements)
  lifecycle_rules                        = local.bucket_lifecycle_rules
  abort_incomplete_multipart_upload_days = var.bucket.lifecycle.abort_incomplete_multipart_days
  object_lock                            = local.bucket_object_lock
  access_logs                            = var.bucket.access_logs
}
