module "replication_role" {
  source = "../../security/iam-role"
  count  = var.replication.enabled && var.replication.iam_role.create ? 1 : 0

  application              = var.application
  environment              = var.environment
  name                     = var.name
  purpose                  = "replication"
  tags                     = var.tags
  path                     = var.replication.iam_role.path
  permissions_boundary_arn = var.replication.iam_role.permissions_boundary_arn
  policy_documents         = [jsonencode({ Version = "2012-10-17", Statement = local.replication_statements })]
  trust = {
    services = ["s3.${module.naming.dns_suffix}"]
    conditions = [
      { test = "StringEquals", variable = "aws:SourceAccount", values = [module.naming.account_id] },
      { test = "ArnLike", variable = "aws:SourceArn", values = [local.arn] }
    ]
  }
}

resource "aws_s3_bucket_replication_configuration" "this" {
  count = var.replication.enabled ? 1 : 0

  bucket = aws_s3_bucket.this.id
  role   = local.role_arn

  dynamic "rule" {
    for_each = var.replication.rules

    content {
      id       = rule.value.id
      priority = coalesce(rule.value.priority, rule.key)
      status   = "Enabled"

      filter {
        prefix = rule.value.prefix
      }

      delete_marker_replication {
        status = rule.value.delete_marker_replication ? "Enabled" : "Disabled"
      }

      source_selection_criteria {
        sse_kms_encrypted_objects {
          status = local.uses_kms ? "Enabled" : "Disabled"
        }
      }

      destination {
        bucket        = rule.value.destination_bucket_arn
        account       = rule.value.destination_account_id
        storage_class = rule.value.storage_class

        dynamic "access_control_translation" {
          for_each = rule.value.destination_account_id == null ? [] : [1]

          content {
            owner = "Destination"
          }
        }

        dynamic "encryption_configuration" {
          for_each = local.uses_kms ? [1] : []

          content {
            replica_kms_key_id = rule.value.replica_kms_key_arn
          }
        }

        dynamic "metrics" {
          for_each = rule.value.replication_time ? [1] : []

          content {
            status = "Enabled"

            event_threshold {
              minutes = 15
            }
          }
        }

        dynamic "replication_time" {
          for_each = rule.value.replication_time ? [1] : []

          content {
            status = "Enabled"

            time {
              minutes = 15
            }
          }
        }
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}
