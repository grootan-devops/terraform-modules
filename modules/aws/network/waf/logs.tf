module "log_group" {
  source = "../../observability/log-group"
  count  = local.logs_to_s3 ? 0 : 1

  application                 = var.application
  environment                 = var.environment
  name                        = var.name
  tags                        = var.tags
  region                      = local.region
  log_group_name              = local.log_group_name
  retention_in_days           = var.cloudwatch_logs.retention_in_days
  log_group_class             = var.cloudwatch_logs.log_group_class
  deletion_protection_enabled = var.cloudwatch_logs.deletion_protection_enabled
  kms_key_arn                 = try(coalesce(var.cloudwatch_logs.kms_key_arn, local.kms_key_arn), null)
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  region                  = local.region
  resource_arn            = aws_wafv2_web_acl.this.arn
  log_destination_configs = [local.logs_to_s3 ? var.logging.s3_bucket_arn : one(module.log_group[*].arn)]

  dynamic "redacted_fields" {
    for_each = var.redacted_fields.headers
    content {
      single_header {
        name = lower(redacted_fields.value)
      }
    }
  }

  dynamic "redacted_fields" {
    for_each = var.redacted_fields.query_string ? [1] : []
    content {
      query_string {}
    }
  }

  dynamic "redacted_fields" {
    for_each = var.redacted_fields.uri_path ? [1] : []
    content {
      uri_path {}
    }
  }
}
