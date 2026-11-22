locals {
  create_bucket        = var.bucket.enabled && var.recorder.enabled
  bucket_name          = local.create_bucket ? coalesce(var.bucket.name, module.naming.names.bucket) : var.bucket.name
  bucket_arn           = "arn:${local.partition}:s3:::${coalesce(local.bucket_name, "none")}"
  bucket_key_prefix    = var.bucket.key_prefix == null ? "" : trim(var.bucket.key_prefix, "/")
  config_object_prefix = local.bucket_key_prefix == "" ? "AWSLogs" : "${local.bucket_key_prefix}/AWSLogs"

  bucket_lifecycle_rules = [{
    id                                 = "config-history-retention"
    expiration_days                    = var.bucket.lifecycle.expiration_days
    noncurrent_version_expiration_days = var.bucket.lifecycle.noncurrent_version_expiration_days
    transitions                        = var.bucket.lifecycle.transitions
  }]

  bucket_statement_candidates = [
    {
      when = true
      statement = {
        sid        = "AWSConfigBucketPermissionsCheck"
        effect     = "Allow"
        actions    = ["s3:GetBucketAcl"]
        resources  = [local.bucket_arn]
        principals = { Service = ["config.amazonaws.com"] }
        conditions = [{ test = "StringEquals", variable = "aws:SourceAccount", values = local.delivery_source_accounts }]
      }
    },
    {
      when = true
      statement = {
        sid        = "AWSConfigBucketExistenceCheck"
        effect     = "Allow"
        actions    = ["s3:ListBucket"]
        resources  = [local.bucket_arn]
        principals = { Service = ["config.amazonaws.com"] }
        conditions = [{ test = "StringEquals", variable = "aws:SourceAccount", values = local.delivery_source_accounts }]
      }
    },
    {
      when = true
      statement = {
        sid        = "AWSConfigBucketDelivery"
        effect     = "Allow"
        actions    = ["s3:PutObject"]
        resources  = [for account_id in local.delivery_source_accounts : "${local.bucket_arn}/${local.config_object_prefix}/${account_id}/Config/*"]
        principals = { Service = ["config.amazonaws.com"] }
        conditions = [
          { test = "StringEquals", variable = "s3:x-amz-acl", values = ["bucket-owner-full-control"] },
          { test = "StringEquals", variable = "aws:SourceAccount", values = local.delivery_source_accounts },
        ]
      }
    },
    {
      when = var.bucket.organization_id != null
      statement = {
        sid        = "AWSConfigBucketPermissionsCheckOrganization"
        effect     = "Allow"
        actions    = ["s3:GetBucketAcl"]
        resources  = [local.bucket_arn]
        principals = { Service = ["config.amazonaws.com"] }
        conditions = [{ test = "StringEquals", variable = "aws:SourceOrgID", values = [coalesce(var.bucket.organization_id, "none")] }]
      }
    },
    {
      when = var.bucket.organization_id != null
      statement = {
        sid        = "AWSConfigBucketExistenceCheckOrganization"
        effect     = "Allow"
        actions    = ["s3:ListBucket"]
        resources  = [local.bucket_arn]
        principals = { Service = ["config.amazonaws.com"] }
        conditions = [{ test = "StringEquals", variable = "aws:SourceOrgID", values = [coalesce(var.bucket.organization_id, "none")] }]
      }
    },
    {
      when = var.bucket.organization_id != null
      statement = {
        sid        = "AWSConfigBucketDeliveryOrganization"
        effect     = "Allow"
        actions    = ["s3:PutObject"]
        resources  = ["${local.bucket_arn}/${local.config_object_prefix}/*/Config/*"]
        principals = { Service = ["config.amazonaws.com"] }
        conditions = [
          { test = "StringEquals", variable = "s3:x-amz-acl", values = ["bucket-owner-full-control"] },
          { test = "StringEquals", variable = "aws:SourceOrgID", values = [coalesce(var.bucket.organization_id, "none")] },
        ]
      }
    },
  ]

  bucket_statements = [for c in local.bucket_statement_candidates : c.statement if c.when]
}

module "bucket" {
  source = "../../storage/s3"
  count  = local.create_bucket ? 1 : 0

  application                            = var.application
  environment                            = var.environment
  name                                   = "config"
  tags                                   = var.tags
  bucket_name                            = var.bucket.name
  kms                                    = { key_id = local.kms_key_arn }
  policy_statements                      = local.bucket_statements
  lifecycle_rules                        = local.bucket_lifecycle_rules
  abort_incomplete_multipart_upload_days = var.bucket.lifecycle.abort_incomplete_multipart_upload_days
  access_logs                            = var.bucket.access_logs
}
