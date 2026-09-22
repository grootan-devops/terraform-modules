resource "aws_dynamodb_table" "this" {
  name                        = local.rendered_name
  deletion_protection_enabled = var.deletion_protection_enabled
  table_class                 = var.table_class

  stream_enabled   = var.stream.enabled
  stream_view_type = var.stream.enabled ? var.stream.view_type : null

  hash_key  = var.hash_key
  range_key = var.range_key

  dynamic "attribute" {
    for_each = var.attributes
    content {
      name = attribute.value.name
      type = attribute.value.type
    }
  }

  dynamic "global_secondary_index" {
    for_each = var.global_secondary_indexes
    content {
      name               = global_secondary_index.value.name
      projection_type    = global_secondary_index.value.projection_type
      non_key_attributes = global_secondary_index.value.non_key_attributes
      write_capacity     = var.billing_mode == "PROVISIONED" ? coalesce(global_secondary_index.value.write_capacity, var.write_capacity) : null
      read_capacity      = var.billing_mode == "PROVISIONED" ? coalesce(global_secondary_index.value.read_capacity, var.read_capacity) : null

      key_schema {
        attribute_name = global_secondary_index.value.hash_key
        key_type       = "HASH"
      }

      dynamic "key_schema" {
        for_each = global_secondary_index.value.range_key != null ? [global_secondary_index.value.range_key] : []
        content {
          attribute_name = key_schema.value
          key_type       = "RANGE"
        }
      }
    }
  }

  dynamic "local_secondary_index" {
    for_each = var.local_secondary_indexes
    content {
      name               = local_secondary_index.value.name
      projection_type    = local_secondary_index.value.projection_type
      non_key_attributes = local_secondary_index.value.non_key_attributes
      range_key          = local_secondary_index.value.range_key
    }
  }
  dynamic "global_table_witness" {
    for_each = var.global_table_witness != null ? [var.global_table_witness] : []
    content {
      region_name = global_table_witness.value.region_name
    }
  }

  dynamic "replica" {
    for_each = var.replicas
    content {
      region_name                 = replica.value.region_name
      kms_key_arn                 = replica.value.kms_key_arn
      propagate_tags              = true
      point_in_time_recovery      = replica.value.point_in_time_recovery
      deletion_protection_enabled = replica.value.deletion_protection_enabled
      consistency_mode            = replica.value.consistency_mode
    }
  }

  billing_mode = var.billing_mode

  read_capacity  = var.billing_mode == "PROVISIONED" ? var.read_capacity : null
  write_capacity = var.billing_mode == "PROVISIONED" ? var.write_capacity : null

  dynamic "on_demand_throughput" {
    for_each = var.on_demand_throughput != null ? [var.on_demand_throughput] : []
    content {
      max_read_request_units  = on_demand_throughput.value.max_read_request_units
      max_write_request_units = on_demand_throughput.value.max_write_request_units
    }
  }

  dynamic "warm_throughput" {
    for_each = var.warm_throughput != null ? [var.warm_throughput] : []
    content {
      read_units_per_second  = warm_throughput.value.read_units_per_second
      write_units_per_second = warm_throughput.value.write_units_per_second
    }
  }

  point_in_time_recovery {
    enabled                 = true
    recovery_period_in_days = var.pitr_recovery_period_in_days
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = var.kms_key_arn
  }

  tags = local.tags
}

resource "aws_dynamodb_contributor_insights" "this" {
  count      = var.enable_contributor_insights ? 1 : 0
  table_name = aws_dynamodb_table.this.name
  index_name = var.contributor_insights_index_name
}
