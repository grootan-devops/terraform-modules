mock_provider "aws" {}

variables {
  application                  = "core"
  environment                  = "prod"
  name                         = "sessions"
  billing_mode                 = "PAY_PER_REQUEST"
  hash_key                     = "session_id"
  table_class                  = "STANDARD"
  kms_key_arn                  = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
  pitr_recovery_period_in_days = 35
  enable_contributor_insights  = false

  attributes = [
    { name = "session_id", type = "S" }
  ]
}

# ------------------------------------------------------------------------------
# Naming
# ------------------------------------------------------------------------------

run "verify_rendered_name" {
  command = plan

  assert {
    condition     = aws_dynamodb_table.this.name == "core-prod-sessions"
    error_message = "Table name must render as <application>-<environment>-<name>."
  }

  assert {
    condition     = output.table_name == "core-prod-sessions"
    error_message = "table_name output must expose the rendered table name."
  }
}

run "verify_name_fallback_when_empty" {
  command = plan

  variables {
    name = ""
  }

  assert {
    condition     = aws_dynamodb_table.this.name == "core-prod"
    error_message = "An empty name must fall back to <application>-<environment>."
  }

  assert {
    condition     = aws_dynamodb_table.this.tags["Name"] == "core-prod"
    error_message = "The Name tag must follow the <application>-<environment> fallback."
  }
}

run "verify_name_fallback_when_null" {
  command = plan

  variables {
    name = null
  }

  assert {
    condition     = aws_dynamodb_table.this.name == "core-prod"
    error_message = "A null name must fall back to <application>-<environment>."
  }
}

# ------------------------------------------------------------------------------
# Tags
# ------------------------------------------------------------------------------

run "verify_governance_tags" {
  command = plan

  assert {
    condition     = aws_dynamodb_table.this.tags["Application"] == "core"
    error_message = "Application tag must be set from var.application."
  }

  assert {
    condition     = aws_dynamodb_table.this.tags["Environment"] == "prod"
    error_message = "Environment tag must be set from var.environment."
  }

  assert {
    condition     = aws_dynamodb_table.this.tags["Name"] == "core-prod-sessions"
    error_message = "Name tag must be the rendered table name."
  }
}

run "verify_caller_tags_preserved" {
  command = plan

  variables {
    tags = {
      Compliance = "SOC2"
      CostCenter = "1234"
    }
  }

  assert {
    condition     = aws_dynamodb_table.this.tags["Compliance"] == "SOC2" && aws_dynamodb_table.this.tags["CostCenter"] == "1234"
    error_message = "Caller tags from var.tags must be preserved on the table."
  }

  assert {
    condition     = aws_dynamodb_table.this.tags["Application"] == "core" && aws_dynamodb_table.this.tags["Environment"] == "prod" && aws_dynamodb_table.this.tags["Name"] == "core-prod-sessions"
    error_message = "Governance tags must still be present alongside caller tags."
  }
}

# ------------------------------------------------------------------------------
# Security defaults
# ------------------------------------------------------------------------------

run "verify_security_defaults" {
  command = plan

  assert {
    condition     = aws_dynamodb_table.this.server_side_encryption[0].enabled == true
    error_message = "Server-side encryption must be enabled."
  }

  assert {
    condition     = aws_dynamodb_table.this.server_side_encryption[0].kms_key_arn == var.kms_key_arn
    error_message = "Server-side encryption must use the caller's KMS key."
  }

  assert {
    condition     = aws_dynamodb_table.this.point_in_time_recovery[0].enabled == true
    error_message = "Point-in-time recovery must be enabled."
  }

  assert {
    condition     = aws_dynamodb_table.this.point_in_time_recovery[0].recovery_period_in_days == 35
    error_message = "PITR recovery period must come from pitr_recovery_period_in_days."
  }

  assert {
    condition     = aws_dynamodb_table.this.deletion_protection_enabled == true
    error_message = "Deletion protection must be enabled by default."
  }
}

# ------------------------------------------------------------------------------
# Parameters
# ------------------------------------------------------------------------------

run "verify_shipped_defaults" {
  command = plan

  assert {
    condition     = aws_dynamodb_table.this.billing_mode == "PAY_PER_REQUEST"
    error_message = "billing_mode must pass through to the table."
  }

  assert {
    condition     = aws_dynamodb_table.this.table_class == "STANDARD"
    error_message = "table_class must pass through to the table."
  }

  assert {
    condition     = aws_dynamodb_table.this.hash_key == "session_id"
    error_message = "hash_key must pass through to the table."
  }

  assert {
    condition     = aws_dynamodb_table.this.range_key == null
    error_message = "range_key must be unset by default."
  }

  assert {
    condition     = length(aws_dynamodb_table.this.attribute) == 1 && contains([for a in aws_dynamodb_table.this.attribute : "${a.name}:${a.type}"], "session_id:S")
    error_message = "Attribute definitions must pass through to the table."
  }

  assert {
    condition     = aws_dynamodb_table.this.stream_enabled == false
    error_message = "Streams must be disabled by default."
  }

  assert {
    condition     = length(aws_dynamodb_table.this.global_secondary_index) == 0
    error_message = "No GSIs must be created by default."
  }

  assert {
    condition     = length(aws_dynamodb_table.this.local_secondary_index) == 0
    error_message = "No LSIs must be created by default."
  }

  assert {
    condition     = length(aws_dynamodb_table.this.replica) == 0
    error_message = "No replicas must be created by default."
  }

  assert {
    condition     = length(aws_dynamodb_table.this.on_demand_throughput) == 0
    error_message = "on_demand_throughput must be unset by default."
  }

  assert {
    condition     = length(aws_dynamodb_table.this.warm_throughput) == 0
    error_message = "warm_throughput must be unset by default."
  }

  assert {
    condition     = length(aws_dynamodb_table.this.global_table_witness) == 0
    error_message = "global_table_witness must be unset by default."
  }

  assert {
    condition     = length(aws_dynamodb_contributor_insights.this) == 0
    error_message = "Contributor insights must not be created when disabled."
  }
}

run "verify_pay_per_request_drops_capacity" {
  command = plan

  variables {
    read_capacity  = 10
    write_capacity = 10
  }

  # Sentinel values for the computed capacity attributes: they only survive the
  # plan if the module leaves read_capacity/write_capacity null.
  override_resource {
    target          = aws_dynamodb_table.this
    override_during = plan
    values = {
      read_capacity  = 0
      write_capacity = 0
    }
  }

  assert {
    condition     = aws_dynamodb_table.this.read_capacity == 0 && aws_dynamodb_table.this.write_capacity == 0
    error_message = "PAY_PER_REQUEST tables must not receive read/write capacity."
  }
}

run "verify_provisioned_overrides" {
  # GSI and replica sets carry computed members, so their size is only known after apply.
  command = apply

  variables {
    name                         = "orders"
    billing_mode                 = "PROVISIONED"
    read_capacity                = 5
    write_capacity               = 3
    hash_key                     = "account_id"
    range_key                    = "order_id"
    table_class                  = "STANDARD_INFREQUENT_ACCESS"
    pitr_recovery_period_in_days = 7
    deletion_protection_enabled  = false

    attributes = [
      { name = "account_id", type = "S" },
      { name = "order_id", type = "S" },
      { name = "status", type = "S" },
      { name = "created_at", type = "N" }
    ]

    stream = {
      enabled   = true
      view_type = "NEW_AND_OLD_IMAGES"
    }

    global_secondary_indexes = [
      {
        name            = "gsi_status_created"
        hash_key        = "status"
        range_key       = "created_at"
        projection_type = "ALL"
      },
      {
        name               = "gsi_created"
        hash_key           = "created_at"
        projection_type    = "INCLUDE"
        non_key_attributes = ["status"]
        read_capacity      = 2
        write_capacity     = 1
      }
    ]

    local_secondary_indexes = [
      {
        name            = "lsi_status"
        range_key       = "status"
        projection_type = "KEYS_ONLY"
      }
    ]

    warm_throughput = {
      read_units_per_second  = 12000
      write_units_per_second = 4000
    }
  }

  assert {
    condition     = aws_dynamodb_table.this.name == "core-prod-orders"
    error_message = "Table name must render with the overridden name."
  }

  assert {
    condition     = aws_dynamodb_table.this.billing_mode == "PROVISIONED"
    error_message = "billing_mode override must pass through."
  }

  assert {
    condition     = aws_dynamodb_table.this.read_capacity == 5 && aws_dynamodb_table.this.write_capacity == 3
    error_message = "PROVISIONED tables must receive read_capacity and write_capacity."
  }

  assert {
    condition     = aws_dynamodb_table.this.range_key == "order_id"
    error_message = "range_key override must pass through."
  }

  assert {
    condition     = aws_dynamodb_table.this.table_class == "STANDARD_INFREQUENT_ACCESS"
    error_message = "table_class override must pass through."
  }

  assert {
    condition     = aws_dynamodb_table.this.point_in_time_recovery[0].recovery_period_in_days == 7
    error_message = "pitr_recovery_period_in_days override must pass through."
  }

  assert {
    condition     = aws_dynamodb_table.this.deletion_protection_enabled == false
    error_message = "deletion_protection_enabled override must pass through."
  }

  assert {
    condition     = length(aws_dynamodb_table.this.attribute) == 4
    error_message = "All attribute definitions must pass through."
  }

  assert {
    condition     = aws_dynamodb_table.this.stream_enabled == true && aws_dynamodb_table.this.stream_view_type == "NEW_AND_OLD_IMAGES"
    error_message = "Enabled streams must carry the requested view type."
  }

  assert {
    condition     = length(aws_dynamodb_table.this.global_secondary_index) == 2
    error_message = "Both GSIs must be created."
  }

  assert {
    condition = length([
      for g in aws_dynamodb_table.this.global_secondary_index : g.name
      if g.name == "gsi_status_created" && g.read_capacity == 5 && g.write_capacity == 3 && g.projection_type == "ALL" &&
      length(g.key_schema) == 2 && g.key_schema[0].attribute_name == "status" && g.key_schema[0].key_type == "HASH" &&
      g.key_schema[1].attribute_name == "created_at" && g.key_schema[1].key_type == "RANGE"
    ]) == 1
    error_message = "A GSI without its own capacity must inherit the table capacity and carry HASH and RANGE keys."
  }

  assert {
    condition = length([
      for g in aws_dynamodb_table.this.global_secondary_index : g.name
      if g.name == "gsi_created" && g.read_capacity == 2 && g.write_capacity == 1 && g.projection_type == "INCLUDE" &&
      length(g.non_key_attributes) == 1 && contains(g.non_key_attributes, "status") &&
      length(g.key_schema) == 1 && g.key_schema[0].attribute_name == "created_at" && g.key_schema[0].key_type == "HASH"
    ]) == 1
    error_message = "A GSI with explicit capacity must keep it, and a GSI without range_key must carry only a HASH key."
  }

  assert {
    condition     = length(aws_dynamodb_table.this.local_secondary_index) == 1 && one(aws_dynamodb_table.this.local_secondary_index).range_key == "status"
    error_message = "The LSI must be created with its range key."
  }

  assert {
    condition     = aws_dynamodb_table.this.warm_throughput[0].read_units_per_second == 12000 && aws_dynamodb_table.this.warm_throughput[0].write_units_per_second == 4000
    error_message = "warm_throughput must pass through when set."
  }
}

run "verify_on_demand_throughput" {
  command = plan

  variables {
    on_demand_throughput = {
      max_read_request_units  = 100
      max_write_request_units = 50
    }
  }

  assert {
    condition     = aws_dynamodb_table.this.on_demand_throughput[0].max_read_request_units == 100 && aws_dynamodb_table.this.on_demand_throughput[0].max_write_request_units == 50
    error_message = "on_demand_throughput must pass through when set."
  }
}

run "verify_replicas" {
  # GSI and replica sets carry computed members, so their size is only known after apply.
  command = apply

  variables {
    stream = {
      enabled   = true
      view_type = "NEW_AND_OLD_IMAGES"
    }

    replicas = {
      east = {
        region_name            = "us-east-1"
        kms_key_arn            = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
        point_in_time_recovery = true
      }
    }
  }

  assert {
    condition     = length(aws_dynamodb_table.this.replica) == 1
    error_message = "One replica must be created per entry in var.replicas."
  }

  assert {
    condition     = one(aws_dynamodb_table.this.replica).region_name == "us-east-1"
    error_message = "Replica region must pass through."
  }

  assert {
    condition     = one(aws_dynamodb_table.this.replica).kms_key_arn == "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
    error_message = "Replica KMS key must pass through."
  }

  assert {
    condition     = one(aws_dynamodb_table.this.replica).point_in_time_recovery == true
    error_message = "Replica point-in-time recovery must pass through."
  }

  assert {
    condition     = one(aws_dynamodb_table.this.replica).deletion_protection_enabled == true
    error_message = "Replica deletion protection must default to true."
  }

  assert {
    condition     = one(aws_dynamodb_table.this.replica).propagate_tags == true
    error_message = "Replicas must propagate table tags."
  }
}

run "verify_contributor_insights_enabled" {
  command = plan

  variables {
    enable_contributor_insights     = true
    contributor_insights_index_name = "gsi_status_created"
  }

  assert {
    condition     = length(aws_dynamodb_contributor_insights.this) == 1
    error_message = "Contributor insights must be created when enabled."
  }

  assert {
    condition     = aws_dynamodb_contributor_insights.this[0].table_name == "core-prod-sessions"
    error_message = "Contributor insights must target the module's table."
  }

  assert {
    condition     = aws_dynamodb_contributor_insights.this[0].index_name == "gsi_status_created"
    error_message = "Contributor insights index name must pass through."
  }
}

# ------------------------------------------------------------------------------
# Validation
# ------------------------------------------------------------------------------

run "verify_invalid_environment_fails" {
  command = plan

  variables {
    environment = "INVALID_UPPERCASE"
  }

  expect_failures = [var.environment]
}
