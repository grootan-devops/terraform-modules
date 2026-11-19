resource "aws_ssm_association" "inventory" {
  for_each = local.inventory_regions

  region              = each.key
  name                = "AWS-GatherSoftwareInventory"
  association_name    = module.naming.names.inventory
  schedule_expression = var.inventory.schedule_expression
  parameters          = local.inventory_parameters

  targets {
    key    = "InstanceIds"
    values = ["*"]
  }

  tags = merge(module.naming.tags, { Name = module.naming.names.inventory })
}

resource "aws_ssm_resource_data_sync" "this" {
  for_each = local.sync_regions

  region = each.key
  name   = module.naming.names.sync

  s3_destination {
    bucket_name = local.sync_bucket_name
    region      = local.sync_bucket_region
    kms_key_arn = local.sync_kms_key_arn
    prefix      = local.sync_prefix == "" ? null : local.sync_prefix
    sync_format = "JsonSerDe"

    dynamic "destination_data_sharing" {
      for_each = local.sync.organization ? ["Organization"] : []

      content {
        destination_data_sharing_type = destination_data_sharing.value
      }
    }
  }

  depends_on = [module.bucket]

  lifecycle {
    precondition {
      condition     = local.sync_kms_key_arn == null || try(split(":", local.sync_kms_key_arn)[3] == local.sync_bucket_region, false)
      error_message = "inventory.resource_data_sync.kms_key_arn: a key in the bucket Region."
    }
  }
}

resource "aws_ssm_association" "agent_update" {
  for_each = local.agent_update_regions

  region              = each.key
  name                = "AWS-UpdateSSMAgent"
  association_name    = module.naming.names.agent_update
  schedule_expression = var.agent_update.schedule_expression
  parameters          = local.agent_update_parameters
  max_concurrency     = var.agent_update.max_concurrency
  max_errors          = var.agent_update.max_errors

  targets {
    key    = "InstanceIds"
    values = ["*"]
  }

  tags = merge(module.naming.tags, { Name = module.naming.names.agent_update })
}

module "bucket" {
  source = "../../storage/s3"
  count  = local.bucket_enabled ? 1 : 0

  application                            = var.application
  environment                            = var.environment
  name                                   = "ssm-inventory"
  tags                                   = var.tags
  bucket_name                            = local.bucket_name
  kms                                    = { key_id = local.bucket_kms_key_arn }
  policy_statements                      = local.bucket_policy_statements
  abort_incomplete_multipart_upload_days = var.inventory_bucket.lifecycle.abort_incomplete_multipart_upload_days
  noncurrent_version_expiration          = { enabled = true, days = var.inventory_bucket.lifecycle.noncurrent_version_expiration_days }
  lifecycle_rules                        = local.bucket_lifecycle_rules
  access_logs                            = var.inventory_bucket.access_logs
}
