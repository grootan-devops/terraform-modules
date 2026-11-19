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

  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:eu-west-1:123456789012:platform-prod-critical"
    }
  }

  mock_resource "aws_sns_topic_subscription" {
    defaults = {
      arn = "arn:aws:sns:eu-west-1:123456789012:platform-prod-critical:00000000-0000-0000-0000-000000000000"
    }
  }
}

variables {
  environment = "prod"
}

run "defaults_three_topics_in_provider_region" {
  command = plan

  assert {
    condition     = toset(keys(aws_sns_topic.this)) == toset(["eu-west-1/critical", "eu-west-1/warning", "eu-west-1/info"]) && alltrue([for k, t in aws_sns_topic.this : t.region == "eu-west-1"])
    error_message = "One topic per severity in the provider Region."
  }

  assert {
    condition     = length(aws_sns_topic_policy.this) == 3 && alltrue([for k, p in aws_sns_topic_policy.this : p.region == aws_sns_topic.this[k].region])
    error_message = "Every topic gets a policy in its Region."
  }

  assert {
    condition     = length(aws_sns_topic_subscription.email) + length(aws_sns_topic_subscription.https) == 0
    error_message = "No subscriptions by default."
  }

  assert {
    condition     = alltrue([for k, t in aws_sns_topic.this : t.signature_version == 2])
    error_message = "Topics sign with SignatureVersion 2."
  }
}

run "naming_and_tags" {
  command = plan

  variables {
    application = "core"
    tags        = { Team = "platform", Environment = "override-attempt" }
  }

  assert {
    condition     = aws_sns_topic.this["eu-west-1/critical"].name == "core-prod-critical" && aws_sns_topic.this["eu-west-1/info"].display_name == "core-prod-info"
    error_message = "Topics are <application>-<environment>-<severity>."
  }

  assert {
    condition     = alltrue([for k, t in aws_sns_topic.this : t.tags["Application"] == "core" && t.tags["Environment"] == "prod" && t.tags["ManagedBy"] == "Terraform" && t.tags["Name"] == t.name && t.tags["Team"] == "platform"])
    error_message = "Caller tags kept, governance tags win, Name is the topic name."
  }
}

run "default_application_is_platform" {
  command = plan

  assert {
    condition     = aws_sns_topic.this["eu-west-1/warning"].name == "platform-prod-warning"
    error_message = "application defaults to platform."
  }
}

run "longest_names_stay_whole" {
  command = plan

  variables {
    application = "abcdefghijklmnopqrstuvwx"
    severities  = ["sev-aaaaaaaaaaaaaaaaaaaaaaaaaaaa"]
  }

  assert {
    condition     = aws_sns_topic.this["eu-west-1/sev-aaaaaaaaaaaaaaaaaaaaaaaaaaaa"].name == "abcdefghijklmnopqrstuvwx-prod-sev-aaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    error_message = "Names under 256 characters are kept whole."
  }
}

run "module_key_by_default_plans_with_unknown_arn" {
  command = plan

  assert {
    condition     = length(aws_sns_topic.this) == 3 && keys(module.encryption) == ["eu-west-1"]
    error_message = "kms.create plans without knowing the key ARN."
  }
}

run "module_key_is_the_default" {
  command   = apply
  state_key = "module_key"

  assert {
    condition     = alltrue([for k, t in aws_sns_topic.this : t.kms_master_key_id == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"])
    error_message = "Every topic uses the module key."
  }

  assert {
    condition     = output.kms_key_arns == { "eu-west-1" = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" }
    error_message = "kms_key_arns maps Region to key."
  }
}

run "caller_key_arn_single_region" {
  command = plan

  variables {
    kms = { key_id = "arn:aws:kms:eu-west-1:123456789012:key/12345678-1234-1234-1234-123456789012" }
  }

  assert {
    condition     = alltrue([for k, t in aws_sns_topic.this : t.kms_master_key_id == "arn:aws:kms:eu-west-1:123456789012:key/12345678-1234-1234-1234-123456789012"])
    error_message = "A key ARN is used as given."
  }
}

run "multi_region_key_id_resolves_per_region" {
  command = plan

  variables {
    regions    = ["eu-west-1", "us-east-1"]
    severities = ["critical", "warning"]
    kms        = { key_id = "mrk-1234567890abcdef1234567890abcdef" }
  }

  assert {
    condition     = toset(keys(aws_sns_topic.this)) == toset(["eu-west-1/critical", "eu-west-1/warning", "us-east-1/critical", "us-east-1/warning"])
    error_message = "One topic per Region and severity."
  }

  assert {
    condition     = aws_sns_topic.this["us-east-1/warning"].kms_master_key_id == "arn:aws:kms:us-east-1:123456789012:key/mrk-1234567890abcdef1234567890abcdef" && aws_sns_topic.this["eu-west-1/warning"].kms_master_key_id == "arn:aws:kms:eu-west-1:123456789012:key/mrk-1234567890abcdef1234567890abcdef"
    error_message = "An mrk- key ID resolves to the replica in each Region."
  }

  assert {
    condition     = jsondecode(aws_sns_topic_policy.this["us-east-1/critical"].policy).Statement[0].Condition.ArnLike["aws:SourceArn"] == "arn:aws:cloudwatch:us-east-1:123456789012:alarm:*"
    error_message = "The us-east-1 topic accepts only us-east-1 alarms."
  }
}

run "multi_region_module_keys_plan" {
  command = plan

  variables {
    regions = ["eu-west-1", "us-east-1"]
    kms     = { create = true }
  }

  assert {
    condition     = toset(keys(module.encryption)) == toset(["eu-west-1", "us-east-1"]) && alltrue([for r, e in module.encryption : e.created])
    error_message = "One module key per Region."
  }
}

run "key_in_another_region_fails" {
  command = plan

  variables {
    kms = { key_id = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012" }
  }

  expect_failures = [aws_sns_topic.this]
}

run "topic_policy_allows_only_cloudwatch_from_this_account" {
  command = plan

  assert {
    condition     = [for s in jsondecode(aws_sns_topic_policy.this["eu-west-1/critical"].policy).Statement : s.Sid] == ["AllowCloudWatchAlarmsPublish", "DenyInsecureTransport", "DenyPlaintextHttpSubscriptions"]
    error_message = "Default policy: CloudWatch allow and two denies."
  }

  assert {
    condition = jsondecode(aws_sns_topic_policy.this["eu-west-1/critical"].policy).Statement[0] == {
      Sid       = "AllowCloudWatchAlarmsPublish"
      Effect    = "Allow"
      Principal = { Service = "cloudwatch.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = "arn:aws:sns:eu-west-1:123456789012:platform-prod-critical"
      Condition = {
        StringEquals = { "aws:SourceAccount" = "123456789012" }
        ArnLike      = { "aws:SourceArn" = "arn:aws:cloudwatch:eu-west-1:123456789012:alarm:*" }
      }
    }
    error_message = "CloudWatch may publish only from this account's alarms in the topic Region."
  }

  assert {
    condition     = jsondecode(aws_sns_topic_policy.this["eu-west-1/critical"].policy).Statement[1].Condition == { Bool = { "aws:SecureTransport" = "false" } } && jsondecode(aws_sns_topic_policy.this["eu-west-1/critical"].policy).Statement[1].Effect == "Deny"
    error_message = "Publishing without TLS is denied."
  }

  assert {
    condition     = jsondecode(aws_sns_topic_policy.this["eu-west-1/critical"].policy).Statement[2].Action == "sns:Subscribe" && jsondecode(aws_sns_topic_policy.this["eu-west-1/critical"].policy).Statement[2].Condition == { StringEquals = { "sns:Protocol" = "http" } }
    error_message = "Plaintext http subscriptions are denied."
  }

  assert {
    condition     = alltrue(flatten([for k, p in aws_sns_topic_policy.this : [for s in jsondecode(p.policy).Statement : !(s.Effect == "Allow" && s.Principal == "*")]]))
    error_message = "No Allow for principal * (SNS.4)."
  }
}

run "additional_publishers" {
  command = plan

  variables {
    additional_publisher_service_principals = ["backup.amazonaws.com", "events.amazonaws.com"]
  }

  assert {
    condition     = [for s in jsondecode(aws_sns_topic_policy.this["eu-west-1/warning"].policy).Statement : s.Sid] == ["AllowCloudWatchAlarmsPublish", "AllowServicePublishFromThisAccount", "DenyInsecureTransport", "DenyPlaintextHttpSubscriptions"]
    error_message = "Additional publishers get their own statement."
  }

  assert {
    condition     = jsondecode(aws_sns_topic_policy.this["eu-west-1/warning"].policy).Statement[1].Principal.Service == ["backup.amazonaws.com", "events.amazonaws.com"] && jsondecode(aws_sns_topic_policy.this["eu-west-1/warning"].policy).Statement[1].Condition == { StringEquals = { "aws:SourceAccount" = "123456789012" } }
    error_message = "Additional publishers are limited to this account."
  }
}

run "cost_alert_publishers" {
  command = plan

  variables {
    additional_publisher_service_principals = ["costalerts.amazonaws.com", "backup.amazonaws.com", "budgets.amazonaws.com"]
  }

  assert {
    condition     = [for s in jsondecode(aws_sns_topic_policy.this["eu-west-1/warning"].policy).Statement : s.Sid] == ["AllowCloudWatchAlarmsPublish", "AllowBudgetsPublish", "AllowCostAnomalyDetectionPublish", "AllowServicePublishFromThisAccount", "DenyInsecureTransport", "DenyPlaintextHttpSubscriptions"]
    error_message = "Budgets and Cost Anomaly Detection get their own statements."
  }

  assert {
    condition = jsondecode(aws_sns_topic_policy.this["eu-west-1/warning"].policy).Statement[1] == {
      Sid       = "AllowBudgetsPublish"
      Effect    = "Allow"
      Principal = { Service = "budgets.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = "arn:aws:sns:eu-west-1:123456789012:platform-prod-warning"
      Condition = {
        StringEquals = { "aws:SourceAccount" = "123456789012" }
        ArnLike      = { "aws:SourceArn" = "arn:aws:budgets::123456789012:*" }
      }
    }
    error_message = "Budgets may publish only for this account's budgets."
  }

  assert {
    condition = jsondecode(aws_sns_topic_policy.this["eu-west-1/warning"].policy).Statement[2] == {
      Sid       = "AllowCostAnomalyDetectionPublish"
      Effect    = "Allow"
      Principal = { Service = "costalerts.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = "arn:aws:sns:eu-west-1:123456789012:platform-prod-warning"
      Condition = {
        StringEquals = { "aws:SourceAccount" = "123456789012" }
        ArnLike      = { "aws:SourceArn" = "arn:aws:ce::123456789012:*" }
      }
    }
    error_message = "Cost Anomaly Detection may publish only for this account's subscriptions."
  }

  assert {
    condition     = jsondecode(aws_sns_topic_policy.this["eu-west-1/warning"].policy).Statement[3].Principal.Service == ["backup.amazonaws.com"]
    error_message = "Other publishers keep the account-scoped statement."
  }

  assert {
    condition     = [for s in local.kms_service_statements : s.sid] == ["AllowCloudWatchAlarms", "AllowBudgets", "AllowCostAnomalyDetection", "AllowServicePublishers"]
    error_message = "The module key grants both cost services."
  }

  assert {
    condition = local.kms_service_statements[1].principals == { Service = ["budgets.amazonaws.com"] } && local.kms_service_statements[1].actions == ["kms:Decrypt", "kms:GenerateDataKey*"] && local.kms_service_statements[1].conditions == [
      { test = "StringEquals", variable = "aws:SourceAccount", values = ["123456789012"] },
      { test = "ArnLike", variable = "aws:SourceArn", values = ["arn:aws:budgets::123456789012:*"] },
    ]
    error_message = "Budgets uses the key only for this account's budgets."
  }

  assert {
    condition = local.kms_service_statements[2].principals == { Service = ["costalerts.amazonaws.com"] } && local.kms_service_statements[2].actions == ["kms:Decrypt", "kms:GenerateDataKey*"] && local.kms_service_statements[2].conditions == [
      { test = "StringEquals", variable = "aws:SourceAccount", values = ["123456789012"] },
      { test = "ArnLike", variable = "aws:SourceArn", values = ["arn:aws:ce::123456789012:*"] },
    ]
    error_message = "Cost Anomaly Detection uses the key only for this account's subscriptions."
  }

  assert {
    condition     = local.kms_service_statements[3].principals == { Service = ["backup.amazonaws.com"] }
    error_message = "Other publishers keep the account-scoped key statement."
  }
}

run "cost_alert_publishers_only" {
  command = plan

  variables {
    additional_publisher_service_principals = ["budgets.amazonaws.com", "costalerts.amazonaws.com"]
  }

  assert {
    condition     = [for s in jsondecode(aws_sns_topic_policy.this["eu-west-1/critical"].policy).Statement : s.Sid] == ["AllowCloudWatchAlarmsPublish", "AllowBudgetsPublish", "AllowCostAnomalyDetectionPublish", "DenyInsecureTransport", "DenyPlaintextHttpSubscriptions"]
    error_message = "No account-wide statement when only cost services publish."
  }

  assert {
    condition     = [for s in local.kms_service_statements : s.sid] == ["AllowCloudWatchAlarms", "AllowBudgets", "AllowCostAnomalyDetection"]
    error_message = "No extra key statement when only cost services publish."
  }
}

run "email_subscriptions_per_region_and_severity" {
  command = plan

  variables {
    regions = ["eu-west-1", "us-east-1"]
    kms     = { key_id = "mrk-1234567890abcdef1234567890abcdef" }
    email_subscriptions = {
      critical = ["oncall@example.com", "oncall@example.com", "lead@example.com"]
      info     = ["reports@example.com"]
    }
  }

  assert {
    condition = toset(keys(aws_sns_topic_subscription.email)) == toset([
      "eu-west-1/critical/oncall@example.com", "eu-west-1/critical/lead@example.com", "eu-west-1/info/reports@example.com",
      "us-east-1/critical/oncall@example.com", "us-east-1/critical/lead@example.com", "us-east-1/info/reports@example.com",
    ])
    error_message = "Each address subscribes once per Region."
  }

  assert {
    condition     = alltrue([for k, s in aws_sns_topic_subscription.email : s.protocol == "email" && s.region == split("/", k)[0] && s.redrive_policy == null])
    error_message = "Email subscriptions in the topic Region, no redrive by default."
  }
}

run "https_subscriptions_defaults" {
  command = plan

  variables {
    https_subscriptions = {
      critical = [{ url = "https://status.example.com/heartbeat/placeholder-critical" }]
      warning  = [{ url = "https://status.example.com/heartbeat/placeholder-warning", raw_message_delivery = true }]
    }
  }

  assert {
    condition     = toset(keys(aws_sns_topic_subscription.https)) == toset(["eu-west-1/critical/0", "eu-west-1/warning/0"])
    error_message = "HTTPS subscriptions keyed <region>/<severity>/<index>."
  }

  assert {
    condition     = nonsensitive(aws_sns_topic_subscription.https["eu-west-1/critical/0"].endpoint) == "https://status.example.com/heartbeat/placeholder-critical" && aws_sns_topic_subscription.https["eu-west-1/critical/0"].protocol == "https"
    error_message = "The URL is the endpoint."
  }

  assert {
    condition     = aws_sns_topic_subscription.https["eu-west-1/critical/0"].raw_message_delivery == false && aws_sns_topic_subscription.https["eu-west-1/warning/0"].raw_message_delivery == true && aws_sns_topic_subscription.https["eu-west-1/critical/0"].endpoint_auto_confirms == false
    error_message = "raw delivery and auto-confirm default to false."
  }

  assert {
    condition     = aws_sns_topic_subscription.https["eu-west-1/critical/0"].delivery_policy == null && aws_sns_topic_subscription.https["eu-west-1/critical/0"].redrive_policy == null
    error_message = "Delivery and redrive policies off by default."
  }
}

run "https_delivery_policy_and_dead_letter_queue" {
  command = plan

  variables {
    https_subscriptions = {
      critical = [{ url = "https://status.example.com/heartbeat/placeholder", endpoint_auto_confirms = true, confirmation_timeout_in_minutes = 5 }]
    }
    email_subscriptions    = { critical = ["oncall@example.com"] }
    https_delivery_policy  = { enabled = true, max_receives_per_second = 10, header_content_type = "application/json" }
    dead_letter_queue_arns = { "eu-west-1" = "arn:aws:sqs:eu-west-1:123456789012:platform-prod-alerts-dlq" }
  }

  assert {
    condition = jsondecode(aws_sns_topic_subscription.https["eu-west-1/critical/0"].delivery_policy) == {
      healthyRetryPolicy = {
        minDelayTarget     = 1
        maxDelayTarget     = 60
        numRetries         = 50
        numNoDelayRetries  = 3
        numMinDelayRetries = 2
        numMaxDelayRetries = 35
        backoffFunction    = "exponential"
      }
      throttlePolicy = { maxReceivesPerSecond = 10 }
      requestPolicy  = { headerContentType = "application/json" }
    }
    error_message = "Delivery policy renders retry, throttle and request policy."
  }

  assert {
    condition     = jsondecode(aws_sns_topic_subscription.https["eu-west-1/critical/0"].redrive_policy) == { deadLetterTargetArn = "arn:aws:sqs:eu-west-1:123456789012:platform-prod-alerts-dlq" } && jsondecode(aws_sns_topic_subscription.email["eu-west-1/critical/oncall@example.com"].redrive_policy) == { deadLetterTargetArn = "arn:aws:sqs:eu-west-1:123456789012:platform-prod-alerts-dlq" }
    error_message = "Every subscription in the Region gets the dead-letter queue."
  }

  assert {
    condition     = aws_sns_topic_subscription.email["eu-west-1/critical/oncall@example.com"].delivery_policy == null && aws_sns_topic_subscription.https["eu-west-1/critical/0"].confirmation_timeout_in_minutes == 5
    error_message = "Email gets no HTTPS delivery policy; timeout follows the input."
  }
}

run "https_delivery_policy_omits_optional_blocks" {
  command = plan

  variables {
    https_subscriptions   = { info = [{ url = "https://status.example.com/heartbeat/placeholder" }] }
    https_delivery_policy = { enabled = true, num_retries = 10, num_no_delay_retries = 0, num_min_delay_retries = 0, num_max_delay_retries = 0, backoff_function = "linear" }
  }

  assert {
    condition     = keys(jsondecode(aws_sns_topic_subscription.https["eu-west-1/info/0"].delivery_policy)) == ["healthyRetryPolicy"]
    error_message = "Only healthyRetryPolicy without throttle or content type."
  }
}

run "outputs_map_region_severity" {
  command   = apply
  state_key = "outputs"

  variables {
    regions             = ["eu-west-1", "us-east-1"]
    kms                 = { key_id = "mrk-1234567890abcdef1234567890abcdef" }
    email_subscriptions = { critical = ["oncall@example.com"] }
    https_subscriptions = { warning = [{ url = "https://status.example.com/heartbeat/placeholder" }] }
  }

  assert {
    condition     = keys(output.topic_arns) == ["eu-west-1", "us-east-1"] && keys(output.topic_arns["us-east-1"]) == ["critical", "info", "warning"] && output.topic_arns["us-east-1"]["critical"] == aws_sns_topic.this["us-east-1/critical"].arn
    error_message = "topic_arns is Region -> severity -> ARN."
  }

  assert {
    condition     = keys(output.email_subscription_arns) == ["eu-west-1/critical/oncall@example.com", "us-east-1/critical/oncall@example.com"] && keys(output.https_subscription_arns) == ["eu-west-1/warning/0", "us-east-1/warning/0"]
    error_message = "Subscription outputs keyed like the subscriptions."
  }

  assert {
    condition     = output.kms_key_arns["us-east-1"] == "arn:aws:kms:us-east-1:123456789012:key/mrk-1234567890abcdef1234567890abcdef"
    error_message = "kms_key_arns shows the key per Region."
  }
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

run "rejects_invalid_region" {
  command = plan

  variables {
    regions = ["Europe"]
  }

  expect_failures = [var.regions]
}

run "rejects_invalid_severity" {
  command = plan

  variables {
    severities = ["Critical"]
  }

  expect_failures = [var.severities]
}

run "rejects_create_and_key_id" {
  command = plan

  variables {
    kms = { create = true, key_id = "12345678-1234-1234-1234-123456789012" }
  }

  expect_failures = [var.kms]
}

run "rejects_invalid_key_id" {
  command = plan

  variables {
    kms = { key_id = "alias/aws/sns" }
  }

  expect_failures = [var.kms]
}

run "rejects_aws_managed_key" {
  command = plan

  variables {
    kms = {}
  }

  expect_failures = [var.kms]
}

run "rejects_single_region_key_for_several_regions" {
  command = plan

  variables {
    regions = ["eu-west-1", "us-east-1"]
    kms     = { key_id = "arn:aws:kms:eu-west-1:123456789012:key/12345678-1234-1234-1234-123456789012" }
  }

  expect_failures = [var.kms]
}

run "rejects_email_for_unknown_severity" {
  command = plan

  variables {
    email_subscriptions = { page = ["oncall@example.com"] }
  }

  expect_failures = [var.email_subscriptions]
}

run "rejects_plaintext_http_webhook" {
  command = plan

  variables {
    https_subscriptions = { critical = [{ url = "http://status.example.com/heartbeat/placeholder" }] }
  }

  expect_failures = [var.https_subscriptions]
}

run "rejects_invalid_delivery_policy" {
  command = plan

  variables {
    https_delivery_policy = { enabled = true, min_delay_target = 100, max_delay_target = 10 }
  }

  expect_failures = [var.https_delivery_policy]
}

run "rejects_dead_letter_queue_in_wrong_region" {
  command = plan

  variables {
    dead_letter_queue_arns = { "eu-west-1" = "arn:aws:sqs:us-east-1:123456789012:platform-prod-alerts-dlq" }
  }

  expect_failures = [var.dead_letter_queue_arns]
}

run "rejects_cloudwatch_as_additional_publisher" {
  command = plan

  variables {
    additional_publisher_service_principals = ["cloudwatch.amazonaws.com"]
  }

  expect_failures = [var.additional_publisher_service_principals]
}
