module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags
  names = {
    table = { max_length = 255 }
  }
}

module "encryption" {
  source = "../../core/encryption"

  purpose = "dynamodb"

  application        = var.application
  environment        = var.environment
  name               = var.name
  tags               = var.tags
  kms                = var.kms
  service_statements = local.kms_service_statements
}

resource "aws_dynamodb_table" "this" {
  name                        = local.table_name
  billing_mode                = var.billing_mode
  hash_key                    = var.hash_key
  range_key                   = var.range_key
  read_capacity               = local.provisioned ? var.provisioned_capacity.read : null
  write_capacity              = local.provisioned ? var.provisioned_capacity.write : null
  table_class                 = var.table_class
  deletion_protection_enabled = var.deletion_protection
  stream_enabled              = var.stream.enabled
  stream_view_type            = var.stream.enabled ? var.stream.view_type : null

  dynamic "attribute" {
    for_each = local.attributes
    content {
      name = attribute.key
      type = attribute.value
    }
  }

  dynamic "global_secondary_index" {
    for_each = var.global_secondary_indexes
    content {
      name               = global_secondary_index.key
      projection_type    = global_secondary_index.value.projection_type
      non_key_attributes = global_secondary_index.value.projection_type == "INCLUDE" ? global_secondary_index.value.non_key_attributes : null
      read_capacity      = local.provisioned ? local.scaled_capacity["index-${global_secondary_index.key}"].read : null
      write_capacity     = local.provisioned ? local.scaled_capacity["index-${global_secondary_index.key}"].write : null

      key_schema {
        attribute_name = global_secondary_index.value.hash_key
        key_type       = "HASH"
      }

      dynamic "key_schema" {
        for_each = global_secondary_index.value.range_key == null ? [] : [global_secondary_index.value.range_key]
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
      name               = local_secondary_index.key
      range_key          = local_secondary_index.value.range_key
      projection_type    = local_secondary_index.value.projection_type
      non_key_attributes = local_secondary_index.value.projection_type == "INCLUDE" ? local_secondary_index.value.non_key_attributes : null
    }
  }

  point_in_time_recovery {
    enabled                 = true
    recovery_period_in_days = var.point_in_time_recovery_days
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = local.kms_key_arn
  }

  dynamic "on_demand_throughput" {
    for_each = !local.provisioned && (var.on_demand_throughput.max_read_request_units != null || var.on_demand_throughput.max_write_request_units != null) ? [1] : []
    content {
      max_read_request_units  = var.on_demand_throughput.max_read_request_units
      max_write_request_units = var.on_demand_throughput.max_write_request_units
    }
  }

  dynamic "warm_throughput" {
    for_each = var.warm_throughput.read_units_per_second != null || var.warm_throughput.write_units_per_second != null ? [1] : []
    content {
      read_units_per_second  = var.warm_throughput.read_units_per_second
      write_units_per_second = var.warm_throughput.write_units_per_second
    }
  }

  dynamic "replica" {
    for_each = var.replicas
    content {
      region_name                 = replica.value.region_name
      kms_key_arn                 = replica.value.kms_key_arn
      consistency_mode            = replica.value.consistency_mode
      point_in_time_recovery      = true
      deletion_protection_enabled = var.deletion_protection
      propagate_tags              = true
    }
  }

  dynamic "global_table_witness" {
    for_each = var.witness_region == null ? [] : [var.witness_region]
    content {
      region_name = global_table_witness.value
    }
  }

  tags = merge(module.naming.tags, { Name = local.table_name })
}

resource "aws_dynamodb_contributor_insights" "this" {
  for_each = local.contributor_insights

  table_name = aws_dynamodb_table.this.name
  index_name = each.value
  mode       = var.contributor_insights.mode
}
