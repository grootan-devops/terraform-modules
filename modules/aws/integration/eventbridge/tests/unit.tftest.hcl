mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      name   = "us-west-2"
      region = "us-west-2"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  application = "core"
  environment = "prod"
  name        = "bus"
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
}

run "verify_naming" {
  command = plan

  assert {
    condition     = aws_cloudwatch_event_bus.this[0].name == "core-prod-bus"
    error_message = "Event bus name must render as <application>-<environment>-<name>."
  }

  assert {
    condition     = output.bus_name == "core-prod-bus"
    error_message = "bus_name output must expose the custom bus name."
  }
}

run "verify_name_fallback_when_empty" {
  command = plan

  variables {
    name = ""
  }

  assert {
    condition     = aws_cloudwatch_event_bus.this[0].name == "core-prod"
    error_message = "Event bus name must fall back to <application>-<environment> when name is empty."
  }

  assert {
    condition     = aws_cloudwatch_event_bus.this[0].tags["Name"] == "core-prod"
    error_message = "Event bus Name tag must fall back to <application>-<environment> when name is empty."
  }
}

run "verify_name_fallback_when_null" {
  command = plan

  variables {
    name = null
  }

  assert {
    condition     = aws_cloudwatch_event_bus.this[0].name == "core-prod"
    error_message = "Event bus name must fall back to <application>-<environment> when name is null."
  }
}

run "verify_bus_name_override" {
  command = plan

  variables {
    bus_name = "orders-bus"
  }

  assert {
    condition     = aws_cloudwatch_event_bus.this[0].name == "orders-bus"
    error_message = "bus_name must override the rendered event bus name."
  }
}

run "verify_security_defaults" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_event_bus.this) == 1
    error_message = "A custom event bus must be created by default."
  }

  assert {
    condition     = aws_cloudwatch_event_bus.this[0].kms_key_identifier == var.kms_key_arn
    error_message = "Custom event bus must be encrypted with the caller-supplied KMS key."
  }
}

run "verify_optional_features_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_event_rule.this) == 0 && length(aws_cloudwatch_event_target.this) == 0
    error_message = "No rules or targets must be created by default."
  }

  assert {
    condition     = length(aws_cloudwatch_event_bus_policy.this) == 0
    error_message = "No bus policy must be created by default."
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.this) == 0 && length(aws_cloudwatch_log_resource_policy.this) == 0
    error_message = "No log group or log resource policy must be created by default."
  }
}

run "verify_tags" {
  command = plan

  variables {
    tags = {
      Messaging  = "EnterpriseBus"
      CostCenter = "1234"
    }
    bus_tags = {
      Tier = "core"
    }
    rules = {
      order_created = {
        event_pattern = "{\"source\":[\"app.orders\"]}"
        tags = {
          RuleOwner = "orders"
        }
      }
    }
    cloudwatch_logs = {
      retention_in_days = 30
      kms_key_arn       = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
    }
  }

  assert {
    condition     = aws_cloudwatch_event_bus.this[0].tags["Application"] == "core" && aws_cloudwatch_event_bus.this[0].tags["Environment"] == "prod" && aws_cloudwatch_event_bus.this[0].tags["Name"] == "core-prod-bus"
    error_message = "Event bus must carry Application, Environment and Name governance tags."
  }

  assert {
    condition     = aws_cloudwatch_event_bus.this[0].tags["Messaging"] == "EnterpriseBus" && aws_cloudwatch_event_bus.this[0].tags["CostCenter"] == "1234"
    error_message = "Caller tags must be preserved on the event bus."
  }

  assert {
    condition     = aws_cloudwatch_event_bus.this[0].tags["Tier"] == "core"
    error_message = "bus_tags must be applied to the event bus."
  }

  assert {
    condition     = aws_cloudwatch_event_rule.this["order_created"].tags["Application"] == "core" && aws_cloudwatch_event_rule.this["order_created"].tags["Environment"] == "prod"
    error_message = "Event rules must carry Application and Environment governance tags."
  }

  assert {
    condition     = aws_cloudwatch_event_rule.this["order_created"].tags["Name"] == "core-prod-bus-order_created"
    error_message = "Event rules must override the Name tag with <rendered_name>-<rule key>."
  }

  assert {
    condition     = aws_cloudwatch_event_rule.this["order_created"].tags["Messaging"] == "EnterpriseBus" && aws_cloudwatch_event_rule.this["order_created"].tags["RuleOwner"] == "orders"
    error_message = "Caller tags and per-rule tags must be preserved on event rules."
  }

  assert {
    condition     = !contains(keys(aws_cloudwatch_event_rule.this["order_created"].tags), "Tier")
    error_message = "bus_tags must only apply to the event bus."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].tags["Application"] == "core" && aws_cloudwatch_log_group.this[0].tags["Environment"] == "prod" && aws_cloudwatch_log_group.this[0].tags["Messaging"] == "EnterpriseBus"
    error_message = "Log group must carry governance and caller tags."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].tags["Name"] == "/aws/events/core-prod-bus"
    error_message = "Log group must override the Name tag with its log group name."
  }
}

run "verify_rules_and_targets" {
  command = plan

  variables {
    rules = {
      order_created = {
        description   = "Route newly created order events"
        event_pattern = "{\"source\":[\"app.orders\"],\"detail-type\":[\"OrderCreated\"]}"
      }
      nightly = {
        schedule_expression = "cron(0 2 * * ? *)"
        state               = "DISABLED"
        role_arn            = "arn:aws:iam::123456789012:role/core-prod-scheduler"
      }
    }
    targets = {
      dispatch_queue = {
        rule_name       = "order_created"
        arn             = "arn:aws:sqs:us-west-2:123456789012:core-prod-orders.fifo"
        dead_letter_arn = "arn:aws:sqs:us-west-2:123456789012:core-prod-orders-dlq"
        retry_policy = {
          maximum_event_age_in_seconds = 86400
          maximum_retry_attempts       = 5
        }
        sqs_target = {
          message_group_id = "orders"
        }
      }
      nightly_job = {
        rule_name = "nightly"
        arn       = "arn:aws:states:us-west-2:123456789012:stateMachine:core-prod-nightly"
        role_arn  = "arn:aws:iam::123456789012:role/core-prod-invoke-sfn"
        input_transformer = {
          input_paths = {
            time = "$.time"
          }
          input_template = "{\"time\": <time>}"
        }
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_event_rule.this["order_created"].name == "order_created" && aws_cloudwatch_event_rule.this["order_created"].event_bus_name == "core-prod-bus"
    error_message = "Rules must be named after their map key and attached to the custom bus."
  }

  assert {
    condition     = aws_cloudwatch_event_rule.this["order_created"].description == "Route newly created order events" && aws_cloudwatch_event_rule.this["order_created"].event_pattern == var.rules["order_created"].event_pattern
    error_message = "Rule description and event pattern must flow through."
  }

  assert {
    condition     = aws_cloudwatch_event_rule.this["order_created"].state == "ENABLED" && aws_cloudwatch_event_rule.this["order_created"].force_destroy == false
    error_message = "Rules must default to state ENABLED and force_destroy false."
  }

  assert {
    condition     = aws_cloudwatch_event_rule.this["nightly"].schedule_expression == "cron(0 2 * * ? *)" && aws_cloudwatch_event_rule.this["nightly"].state == "DISABLED" && aws_cloudwatch_event_rule.this["nightly"].role_arn == "arn:aws:iam::123456789012:role/core-prod-scheduler"
    error_message = "Rule schedule expression, state and role must flow through."
  }

  assert {
    condition     = aws_cloudwatch_event_target.this["dispatch_queue"].rule == "order_created" && aws_cloudwatch_event_target.this["dispatch_queue"].target_id == "dispatch_queue" && aws_cloudwatch_event_target.this["dispatch_queue"].event_bus_name == "core-prod-bus"
    error_message = "Targets must attach to their rule on the custom bus with the map key as target id."
  }

  assert {
    condition     = aws_cloudwatch_event_target.this["dispatch_queue"].arn == "arn:aws:sqs:us-west-2:123456789012:core-prod-orders.fifo"
    error_message = "Target ARN must flow through."
  }

  assert {
    condition     = aws_cloudwatch_event_target.this["dispatch_queue"].dead_letter_config[0].arn == "arn:aws:sqs:us-west-2:123456789012:core-prod-orders-dlq"
    error_message = "Target dead-letter queue must flow through."
  }

  assert {
    condition     = aws_cloudwatch_event_target.this["dispatch_queue"].retry_policy[0].maximum_event_age_in_seconds == 86400 && aws_cloudwatch_event_target.this["dispatch_queue"].retry_policy[0].maximum_retry_attempts == 5
    error_message = "Target retry policy must flow through."
  }

  assert {
    condition     = aws_cloudwatch_event_target.this["dispatch_queue"].sqs_target[0].message_group_id == "orders"
    error_message = "Target SQS message group id must flow through."
  }

  assert {
    condition     = length(aws_cloudwatch_event_target.this["dispatch_queue"].input_transformer) == 0
    error_message = "input_transformer must be omitted when not supplied."
  }

  assert {
    condition     = aws_cloudwatch_event_target.this["nightly_job"].role_arn == "arn:aws:iam::123456789012:role/core-prod-invoke-sfn"
    error_message = "Target role ARN must flow through."
  }

  assert {
    condition     = aws_cloudwatch_event_target.this["nightly_job"].input_transformer[0].input_paths["time"] == "$.time" && aws_cloudwatch_event_target.this["nightly_job"].input_transformer[0].input_template == "{\"time\": <time>}"
    error_message = "Target input transformer must flow through."
  }

  assert {
    condition     = length(aws_cloudwatch_event_target.this["nightly_job"].dead_letter_config) == 0 && length(aws_cloudwatch_event_target.this["nightly_job"].retry_policy) == 0 && length(aws_cloudwatch_event_target.this["nightly_job"].sqs_target) == 0
    error_message = "dead_letter_config, retry_policy and sqs_target must be omitted when not supplied."
  }
}

run "verify_default_bus_when_create_bus_false" {
  command = plan

  variables {
    create_bus = false
    rules = {
      heartbeat = {
        schedule_expression = "rate(5 minutes)"
      }
    }
    bus_policy = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"AllowAccountPut\",\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"arn:aws:iam::123456789012:root\"},\"Action\":\"events:PutEvents\",\"Resource\":\"arn:aws:events:us-west-2:123456789012:event-bus/default\"}]}"
  }

  assert {
    condition     = length(aws_cloudwatch_event_bus.this) == 0
    error_message = "No custom event bus must be created when create_bus is false."
  }

  assert {
    condition     = aws_cloudwatch_event_rule.this["heartbeat"].event_bus_name == "default"
    error_message = "Rules must attach to the default bus when create_bus is false."
  }

  assert {
    condition     = output.bus_name == "default" && output.bus_arn == null
    error_message = "bus_name must be default and bus_arn null when create_bus is false."
  }

  assert {
    condition     = length(aws_cloudwatch_event_bus_policy.this) == 1 && aws_cloudwatch_event_bus_policy.this[0].event_bus_name == "default"
    error_message = "Bus policy must be attached to the default bus when create_bus is false."
  }

  assert {
    condition     = aws_cloudwatch_event_bus_policy.this[0].policy == var.bus_policy
    error_message = "Bus policy document must flow through."
  }
}

run "verify_bus_policy_on_custom_bus" {
  command = plan

  variables {
    bus_policy = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"AllowAccountPut\",\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"arn:aws:iam::123456789012:root\"},\"Action\":\"events:PutEvents\",\"Resource\":\"*\"}]}"
  }

  assert {
    condition     = length(aws_cloudwatch_event_bus_policy.this) == 1 && aws_cloudwatch_event_bus_policy.this[0].event_bus_name == "core-prod-bus"
    error_message = "Bus policy must be attached to the custom bus."
  }
}

run "verify_cloudwatch_logs_enabled" {
  command = apply

  variables {
    cloudwatch_logs = {
      retention_in_days           = 90
      kms_key_arn                 = "arn:aws:kms:us-west-2:123456789012:key/87654321-4321-4321-4321-210987654321"
      deletion_protection_enabled = true
    }
  }

  override_resource {
    target = aws_cloudwatch_log_group.this
    values = {
      arn = "arn:aws:logs:us-west-2:123456789012:log-group:/aws/events/core-prod-bus"
    }
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].name == "/aws/events/core-prod-bus"
    error_message = "Log group must be named /aws/events/<rendered_name>."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].kms_key_id == "arn:aws:kms:us-west-2:123456789012:key/87654321-4321-4321-4321-210987654321"
    error_message = "Log group must be encrypted with cloudwatch_logs.kms_key_arn."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].retention_in_days == 90
    error_message = "Log group retention must follow cloudwatch_logs.retention_in_days."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].deletion_protection_enabled == true && aws_cloudwatch_log_group.this[0].log_group_class == "STANDARD"
    error_message = "Log group must honour deletion protection and use the STANDARD class."
  }

  assert {
    condition     = aws_cloudwatch_log_resource_policy.this[0].policy_name == "core-prod-bus-eb-log-policy"
    error_message = "Log resource policy must be named <rendered_name>-eb-log-policy."
  }

  assert {
    condition     = aws_cloudwatch_log_resource_policy.this[0].policy_document == data.aws_iam_policy_document.eventbridge_log_policy[0].json
    error_message = "Log resource policy must be rendered from the module's policy document."
  }

  assert {
    condition     = toset(data.aws_iam_policy_document.eventbridge_log_policy[0].statement[0].resources) == toset(["arn:aws:logs:us-west-2:123456789012:log-group:/aws/events/core-prod-bus:*"])
    error_message = "Log resource policy must be scoped to the module's log group."
  }

  assert {
    condition     = toset(data.aws_iam_policy_document.eventbridge_log_policy[0].statement[0].actions) == toset(["logs:CreateLogStream", "logs:PutLogEvents"])
    error_message = "Log resource policy must only grant CreateLogStream and PutLogEvents."
  }

  assert {
    condition     = toset(flatten([for p in data.aws_iam_policy_document.eventbridge_log_policy[0].statement[0].principals : p.identifiers])) == toset(["events.amazonaws.com", "delivery.logs.amazonaws.com"])
    error_message = "Log resource policy must only trust the EventBridge and log delivery service principals."
  }
}

run "verify_invalid_environment_fails" {
  command = plan

  variables {
    environment = "INVALID_UPPERCASE"
  }

  expect_failures = [var.environment]
}
