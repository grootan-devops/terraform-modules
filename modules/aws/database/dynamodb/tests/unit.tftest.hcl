mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "eu-west-1"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    }
  }

  mock_resource "aws_dynamodb_table" {
    defaults = {
      arn        = "arn:aws:dynamodb:eu-west-1:123456789012:table/core-prod-orders"
      stream_arn = "arn:aws:dynamodb:eu-west-1:123456789012:table/core-prod-orders/stream/2026-01-01T00:00:00.000"
    }
  }
}

variables {
  application = "core"
  environment = "prod"
  name        = "orders"
  hash_key    = "order_id"
  tags        = { Team = "payments" }
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = aws_dynamodb_table.this.name == "core-prod-orders" && aws_dynamodb_table.this.billing_mode == "PAY_PER_REQUEST" && aws_dynamodb_table.this.table_class == "STANDARD"
    error_message = "Defaults: <application>-<environment>-<name>, on demand, STANDARD class."
  }

  assert {
    condition     = aws_dynamodb_table.this.point_in_time_recovery[0].enabled && aws_dynamodb_table.this.point_in_time_recovery[0].recovery_period_in_days == 35
    error_message = "Point-in-time recovery must be on for 35 days (DynamoDB.2)."
  }

  assert {
    condition     = aws_dynamodb_table.this.server_side_encryption[0].enabled && module.encryption.key_arn == null && output.kms_key_arn == null
    error_message = "No kms input means server-side encryption with the AWS managed key."
  }

  assert {
    condition     = aws_dynamodb_table.this.deletion_protection_enabled && !aws_dynamodb_table.this.stream_enabled
    error_message = "Deletion protection on (DynamoDB.6); no stream by default."
  }

  assert {
    condition     = [for a in aws_dynamodb_table.this.attribute : "${a.name}:${a.type}"] == ["order_id:S"]
    error_message = "Only the hash key is defined, as a string; no provisioned capacity."
  }

  assert {
    condition     = length(aws_appautoscaling_target.this) + length(aws_appautoscaling_policy.this) + length(aws_dynamodb_contributor_insights.this) == 0
    error_message = "No autoscaling or Contributor Insights by default."
  }

  assert {
    condition     = length(aws_dynamodb_table.this.replica) + length(aws_dynamodb_table.this.global_table_witness) + length(aws_dynamodb_table.this.on_demand_throughput) + length(aws_dynamodb_table.this.warm_throughput) == 0
    error_message = "No replicas, witness or throughput limits by default."
  }

  assert {
    condition     = aws_dynamodb_table.this.tags["Name"] == "core-prod-orders" && aws_dynamodb_table.this.tags["Team"] == "payments" && aws_dynamodb_table.this.tags["ManagedBy"] == "Terraform" && aws_dynamodb_table.this.tags["Environment"] == "prod"
    error_message = "Caller and governance tags must be applied (DynamoDB.5)."
  }
}

run "governance_tags_win" {
  command = plan

  variables {
    tags = { Environment = "dev", Owner = "data" }
  }

  assert {
    condition     = aws_dynamodb_table.this.tags["Environment"] == "prod" && aws_dynamodb_table.this.tags["Owner"] == "data"
    error_message = "Governance tags must override caller tags."
  }
}

run "outputs" {
  command = apply

  assert {
    condition     = output.arn == "arn:aws:dynamodb:eu-west-1:123456789012:table/core-prod-orders" && output.name == "core-prod-orders" && output.id == aws_dynamodb_table.this.id
    error_message = "id, arn and name must come from the table."
  }

  assert {
    condition     = output.stream_arn == null && length(output.global_secondary_index_names) == 0
    error_message = "No stream ARN and no index names by default."
  }
}

run "module_key_is_planned_safely" {
  command   = plan
  state_key = "module_key"

  variables {
    kms = { create = true }
  }

  assert {
    condition     = module.encryption.created
    error_message = "kms.create must plan without knowing the key ARN."
  }
}

run "module_key_encrypts_table" {
  command   = apply
  state_key = "module_key"

  variables {
    kms = { create = true }
  }

  assert {
    condition     = aws_dynamodb_table.this.server_side_encryption[0].kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && output.kms_key_arn == aws_dynamodb_table.this.server_side_encryption[0].kms_key_arn
    error_message = "The module key must encrypt the table."
  }
}

run "caller_key_id" {
  command = plan

  variables {
    kms = { key_id = "11111111-2222-3333-4444-555555555555" }
  }

  assert {
    condition     = aws_dynamodb_table.this.server_side_encryption[0].kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && !module.encryption.created
    error_message = "A key ID must be used as the key ARN."
  }
}

run "indexes_and_stream" {
  command   = apply
  state_key = "indexes"

  variables {
    range_key  = "created_at"
    attributes = { created_at = "N", amount = "N" }
    stream     = { enabled = true }
    global_secondary_indexes = {
      by_status = { hash_key = "status", range_key = "created_at" }
      by_amount = { hash_key = "amount", projection_type = "INCLUDE", non_key_attributes = ["status"] }
    }
    local_secondary_indexes = {
      by_customer = { range_key = "customer_id", projection_type = "KEYS_ONLY" }
    }
  }

  assert {
    condition     = { for a in aws_dynamodb_table.this.attribute : a.name => a.type } == { order_id = "S", created_at = "N", status = "S", amount = "N", customer_id = "S" }
    error_message = "Every key attribute must be defined once; unlisted keys default to S."
  }

  assert {
    condition     = length(aws_dynamodb_table.this.global_secondary_index) == 2 && length(aws_dynamodb_table.this.local_secondary_index) == 1 && output.global_secondary_index_names == tolist(["by_amount", "by_status"])
    error_message = "Indexes must be created from the maps and their names output."
  }

  assert {
    condition     = alltrue([for i in aws_dynamodb_table.this.global_secondary_index : i.name == "by_amount" ? i.non_key_attributes == toset(["status"]) : i.non_key_attributes == null])
    error_message = "Non-key attributes only with INCLUDE."
  }

  assert {
    condition     = aws_dynamodb_table.this.stream_enabled && aws_dynamodb_table.this.stream_view_type == "NEW_AND_OLD_IMAGES" && output.stream_arn == "arn:aws:dynamodb:eu-west-1:123456789012:table/core-prod-orders/stream/2026-01-01T00:00:00.000"
    error_message = "The stream must default to NEW_AND_OLD_IMAGES and its ARN be output."
  }
}

run "provisioned_with_autoscaling" {
  command = plan

  variables {
    billing_mode         = "PROVISIONED"
    provisioned_capacity = { read = 10, write = 5 }
    autoscaling          = { max_read_capacity = 200, max_write_capacity = 50, target_utilization = 60 }
    global_secondary_indexes = {
      by_status = { hash_key = "status", read_capacity = 20 }
    }
  }

  assert {
    condition     = aws_dynamodb_table.this.read_capacity == 10 && aws_dynamodb_table.this.write_capacity == 5 && one(aws_dynamodb_table.this.global_secondary_index).read_capacity == 20 && one(aws_dynamodb_table.this.global_secondary_index).write_capacity == 5
    error_message = "Provisioned capacity must apply to the table and fall back to it for indexes."
  }

  assert {
    condition     = toset(keys(aws_appautoscaling_target.this)) == toset(["index-by_status-read", "index-by_status-write", "table-read", "table-write"])
    error_message = "The table and every index must scale read and write capacity (DynamoDB.1)."
  }

  assert {
    condition     = aws_appautoscaling_target.this["table-read"].resource_id == "table/core-prod-orders" && aws_appautoscaling_target.this["table-read"].min_capacity == 10 && aws_appautoscaling_target.this["table-read"].max_capacity == 200
    error_message = "The table read target must scale from the provisioned capacity to the maximum."
  }

  assert {
    condition     = aws_appautoscaling_target.this["index-by_status-read"].resource_id == "table/core-prod-orders/index/by_status" && aws_appautoscaling_target.this["index-by_status-read"].scalable_dimension == "dynamodb:index:ReadCapacityUnits" && aws_appautoscaling_target.this["index-by_status-read"].min_capacity == 20
    error_message = "Index targets must use the index resource ID and dimension."
  }

  assert {
    condition     = aws_appautoscaling_policy.this["table-write"].target_tracking_scaling_policy_configuration[0].target_value == 60 && aws_appautoscaling_policy.this["table-write"].target_tracking_scaling_policy_configuration[0].predefined_metric_specification[0].predefined_metric_type == "DynamoDBWriteCapacityUtilization"
    error_message = "Policies must track the configured utilization."
  }

  assert {
    condition     = aws_appautoscaling_target.this["table-read"].tags["Name"] == "core-prod-orders-table-read" && aws_appautoscaling_target.this["table-read"].tags["ManagedBy"] == "Terraform"
    error_message = "Scalable targets carry the governance tags."
  }
}

run "provisioned_without_autoscaling" {
  command = plan

  variables {
    billing_mode = "PROVISIONED"
    autoscaling  = { enabled = false }
  }

  assert {
    condition     = aws_dynamodb_table.this.read_capacity == 5 && length(aws_appautoscaling_target.this) == 0
    error_message = "autoscaling.enabled = false must leave fixed capacity."
  }
}

run "on_demand_limits_ignore_autoscaling" {
  command = plan

  variables {
    on_demand_throughput = { max_read_request_units = 1000 }
    warm_throughput      = { read_units_per_second = 12000, write_units_per_second = 4000 }
  }

  assert {
    condition     = aws_dynamodb_table.this.on_demand_throughput[0].max_read_request_units == 1000 && aws_dynamodb_table.this.warm_throughput[0].write_units_per_second == 4000 && length(aws_appautoscaling_target.this) == 0
    error_message = "On-demand tables take throughput limits and never get scalable targets."
  }
}

run "global_table_with_witness" {
  command = plan

  variables {
    kms            = { create = true }
    stream         = { enabled = true }
    replicas       = { east = { region_name = "eu-central-1", kms_key_arn = "arn:aws:kms:eu-central-1:123456789012:key/22222222-2222-3333-4444-555555555555", consistency_mode = "STRONG" } }
    witness_region = "eu-west-2"
  }

  assert {
    condition     = one(aws_dynamodb_table.this.replica).region_name == "eu-central-1" && one(aws_dynamodb_table.this.replica).point_in_time_recovery && one(aws_dynamodb_table.this.replica).deletion_protection_enabled && one(aws_dynamodb_table.this.replica).propagate_tags
    error_message = "Replicas keep point-in-time recovery, deletion protection and tags."
  }

  assert {
    condition     = one(aws_dynamodb_table.this.replica).consistency_mode == "STRONG" && aws_dynamodb_table.this.global_table_witness[0].region_name == "eu-west-2"
    error_message = "The witness Region must be set with a STRONG replica."
  }
}

run "contributor_insights" {
  command = plan

  variables {
    global_secondary_indexes = { by_status = { hash_key = "status" } }
    contributor_insights     = { enabled = true, index_names = ["by_status"], mode = "THROTTLED_KEYS" }
  }

  assert {
    condition     = toset(keys(aws_dynamodb_contributor_insights.this)) == toset(["index-by_status", "table"]) && aws_dynamodb_contributor_insights.this["table"].index_name == null && aws_dynamodb_contributor_insights.this["index-by_status"].index_name == "by_status"
    error_message = "Contributor Insights must cover the table and the listed indexes."
  }

  assert {
    condition     = aws_dynamodb_contributor_insights.this["table"].mode == "THROTTLED_KEYS" && aws_dynamodb_contributor_insights.this["table"].table_name == "core-prod-orders"
    error_message = "Contributor Insights must use the configured mode on this table."
  }
}

run "deletion_protection_off" {
  command = plan

  variables {
    deletion_protection = false
  }

  assert {
    condition     = !aws_dynamodb_table.this.deletion_protection_enabled
    error_message = "deletion_protection = false must reach the table."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Orders_Table"
  }

  expect_failures = [var.name]
}

run "rejects_invalid_application" {
  command = plan

  variables {
    application = "Core"
  }

  expect_failures = [var.application]
}

run "rejects_invalid_environment" {
  command = plan

  variables {
    environment = "PROD"
  }

  expect_failures = [var.environment]
}

run "rejects_empty_hash_key" {
  command = plan

  variables {
    hash_key = ""
  }

  expect_failures = [var.hash_key]
}

run "rejects_unknown_attribute_type" {
  command = plan

  variables {
    attributes = { order_id = "X" }
  }

  expect_failures = [var.attributes]
}

run "rejects_unknown_billing_mode" {
  command = plan

  variables {
    billing_mode = "ON_DEMAND"
  }

  expect_failures = [var.billing_mode]
}

run "rejects_zero_capacity" {
  command = plan

  variables {
    provisioned_capacity = { read = 0 }
  }

  expect_failures = [var.provisioned_capacity]
}

run "rejects_target_utilization_out_of_range" {
  command = plan

  variables {
    autoscaling = { target_utilization = 95 }
  }

  expect_failures = [var.autoscaling]
}

run "rejects_max_below_provisioned" {
  command = plan

  variables {
    provisioned_capacity = { read = 50 }
    autoscaling          = { max_read_capacity = 20 }
  }

  expect_failures = [var.autoscaling]
}

run "rejects_unknown_table_class" {
  command = plan

  variables {
    table_class = "GLACIER"
  }

  expect_failures = [var.table_class]
}

run "rejects_recovery_period_over_35" {
  command = plan

  variables {
    point_in_time_recovery_days = 36
  }

  expect_failures = [var.point_in_time_recovery_days]
}

run "rejects_unknown_stream_view_type" {
  command = plan

  variables {
    stream = { enabled = true, view_type = "ALL" }
  }

  expect_failures = [var.stream]
}

run "rejects_unknown_gsi_projection" {
  command = plan

  variables {
    global_secondary_indexes = { by_status = { hash_key = "status", projection_type = "SOME" } }
  }

  expect_failures = [var.global_secondary_indexes]
}

run "rejects_unknown_lsi_projection" {
  command = plan

  variables {
    local_secondary_indexes = { by_customer = { range_key = "customer_id", projection_type = "SOME" } }
  }

  expect_failures = [var.local_secondary_indexes]
}

run "rejects_kms_create_with_key_id" {
  command = plan

  variables {
    kms = { create = true, key_id = "11111111-2222-3333-4444-555555555555" }
  }

  expect_failures = [var.kms]
}

run "rejects_invalid_key_id" {
  command = plan

  variables {
    kms = { key_id = "alias/orders" }
  }

  expect_failures = [var.kms]
}

run "rejects_replicas_without_stream" {
  command = plan

  variables {
    replicas = { east = { region_name = "eu-central-1" } }
  }

  expect_failures = [var.replicas]
}

run "rejects_replica_without_key_for_customer_key" {
  command = plan

  variables {
    kms      = { key_id = "11111111-2222-3333-4444-555555555555" }
    stream   = { enabled = true }
    replicas = { east = { region_name = "eu-central-1" } }
  }

  expect_failures = [var.replicas]
}

run "rejects_unknown_consistency_mode" {
  command = plan

  variables {
    stream   = { enabled = true }
    replicas = { east = { region_name = "eu-central-1", consistency_mode = "SOMETIMES" } }
  }

  expect_failures = [var.replicas]
}

run "rejects_witness_without_strong_replica" {
  command = plan

  variables {
    stream         = { enabled = true }
    replicas       = { east = { region_name = "eu-central-1" } }
    witness_region = "eu-west-2"
  }

  expect_failures = [var.witness_region]
}

run "rejects_unknown_contributor_insights_mode" {
  command = plan

  variables {
    contributor_insights = { enabled = true, mode = "ALL_KEYS" }
  }

  expect_failures = [var.contributor_insights]
}

run "rejects_contributor_insights_on_missing_index" {
  command = plan

  variables {
    contributor_insights = { enabled = true, index_names = ["by_status"] }
  }

  expect_failures = [var.contributor_insights]
}

run "alarms_by_default" {
  command = plan

  assert {
    condition     = sort(keys(output.alarm_names)) == tolist(["dynamodb-table-read-throttles", "dynamodb-table-system-errors", "dynamodb-table-write-throttles"])
    error_message = "Default alarms: read and write throttles and system errors."
  }

  assert {
    condition     = alltrue([for n in values(output.alarm_names) : startswith(n, "core-prod-orders-dynamodb-table-")]) && module.alarms[0].alarm_settings["dynamodb-table-read-throttles"].threshold == 0
    error_message = "Alarm names start with the module base name; throttle alarms fire on any throttle."
  }

  assert {
    condition     = alltrue([for k, r in module.alarms[0].alarm_routes : r.topic_arn == null])
    error_message = "Without topic_arns, alarms have no actions."
  }
}

run "alarms_off" {
  command = plan

  variables {
    alarms = { enabled = false }
  }

  assert {
    condition     = length(module.alarms) == 0 && length(output.alarm_names) == 0 && length(output.alarm_arns) == 0
    error_message = "alarms.enabled = false creates no alarms."
  }
}

run "alarms_tuned_and_routed" {
  command = apply

  variables {
    alarms = {
      topic_arns = {
        critical = "arn:aws:sns:eu-west-1:123456789012:platform-prod-critical"
        warning  = "arn:aws:sns:eu-west-1:123456789012:platform-prod-warning"
        info     = "arn:aws:sns:eu-west-1:123456789012:platform-prod-info"
      }
      overrides = {
        system_errors          = { threshold = 2 }
        write_throttles        = { enabled = false }
        consumed_read_capacity = { enabled = true, threshold = 1000 }
      }
    }
  }

  assert {
    condition     = sort(keys(output.alarm_arns)) == tolist(["dynamodb-table-consumed-rcu", "dynamodb-table-read-throttles", "dynamodb-table-system-errors"])
    error_message = "A disabled alarm is dropped; an opt-in alarm is added."
  }

  assert {
    condition     = module.alarms[0].alarm_settings["dynamodb-table-system-errors"].threshold == 2 && module.alarms[0].alarm_settings["dynamodb-table-system-errors"].evaluation_periods == 15 && module.alarms[0].alarm_settings["dynamodb-table-consumed-rcu"].threshold == 1000
    error_message = "Overrides change one setting; the rest keep the preset defaults."
  }

  assert {
    condition     = module.alarms[0].alarm_routes["dynamodb-table-system-errors"].topic_arn == "arn:aws:sns:eu-west-1:123456789012:platform-prod-critical" && module.alarms[0].alarm_routes["dynamodb-table-read-throttles"].topic_arn == "arn:aws:sns:eu-west-1:123456789012:platform-prod-warning" && module.alarms[0].alarm_routes["dynamodb-table-consumed-rcu"].topic_arn == "arn:aws:sns:eu-west-1:123456789012:platform-prod-info"
    error_message = "Each alarm notifies the topic for its severity."
  }
}

run "alarms_cover_indexes" {
  command = plan

  variables {
    global_secondary_indexes = {
      by_status = { hash_key = "status" }
    }
  }

  assert {
    condition     = sort(keys(output.alarm_names)) == tolist(["dynamodb-table-gsi-by_status-read-throttles", "dynamodb-table-gsi-by_status-write-throttles", "dynamodb-table-read-throttles", "dynamodb-table-system-errors", "dynamodb-table-write-throttles"])
    error_message = "Each global secondary index gets read and write throttle alarms."
  }
}

run "alarms_plan_with_unknown_arns" {
  command = plan

  variables {
    kms = { create = true }
  }

  assert {
    condition     = length(module.alarms) == 1 && length(output.alarm_names) == 3
    error_message = "Alarm keys and names must be known at plan with a module key."
  }
}

run "rejects_invalid_alarm_topic" {
  command = plan

  variables {
    alarms = { topic_arns = { critical = "arn:aws:sqs:eu-west-1:123456789012:core-prod-critical" } }
  }

  expect_failures = [var.alarms]
}
