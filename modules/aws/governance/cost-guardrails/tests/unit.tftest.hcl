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

  mock_resource "aws_budgets_budget" {
    defaults = {
      arn = "arn:aws:budgets::123456789012:budget/platform-prod-account"
    }
  }

  mock_resource "aws_ce_anomaly_monitor" {
    defaults = {
      arn = "arn:aws:ce::123456789012:anomalymonitor/11111111-2222-3333-4444-555555555555"
    }
  }

  mock_resource "aws_ce_anomaly_subscription" {
    defaults = {
      arn = "arn:aws:ce::123456789012:anomalysubscription/66666666-7777-8888-9999-000000000000"
    }
  }
}

variables {
  environment   = "prod"
  tags          = { Team = "finops" }
  notifications = { emails = ["finops@example.com"] }
}

run "defaults_service_monitor_and_daily_email" {
  command = plan

  assert {
    condition     = length(aws_budgets_budget.this) == 0 && length(aws_ce_anomaly_monitor.custom) == 0 && length(aws_ce_cost_allocation_tag.this) == 0
    error_message = "No budgets, custom monitors or cost allocation tags by default."
  }

  assert {
    condition     = aws_ce_anomaly_monitor.services[0].monitor_type == "DIMENSIONAL" && aws_ce_anomaly_monitor.services[0].monitor_dimension == "SERVICE" && aws_ce_anomaly_monitor.services[0].monitor_specification == null
    error_message = "One AWS services monitor by default."
  }

  assert {
    condition     = keys(aws_ce_anomaly_subscription.this) == ["daily"] && aws_ce_anomaly_subscription.this["daily"].frequency == "DAILY"
    error_message = "Emails get a daily summary; no immediate subscription without SNS."
  }

  assert {
    condition     = [for s in aws_ce_anomaly_subscription.this["daily"].subscriber : { type = s.type, address = s.address }] == [{ type = "EMAIL", address = "finops@example.com" }]
    error_message = "Each email is a subscriber."
  }

  assert {
    condition     = aws_ce_anomaly_subscription.this["daily"].threshold_expression[0].dimension[0].key == "ANOMALY_TOTAL_IMPACT_ABSOLUTE" && aws_ce_anomaly_subscription.this["daily"].threshold_expression[0].dimension[0].values == toset(["100"]) && aws_ce_anomaly_subscription.this["daily"].threshold_expression[0].dimension[0].match_options == toset(["GREATER_THAN_OR_EQUAL"]) && length(aws_ce_anomaly_subscription.this["daily"].threshold_expression[0].or) == 0
    error_message = "Default threshold: total impact >= 100 USD."
  }
}

run "budgets_with_filters_and_default_notifications" {
  command = plan

  variables {
    budgets = {
      account = { amount = 5000 }
      core = {
        amount = 1500
        filter = { tags = { Team = ["orders", "payments"], Application = ["core"] }, services = ["Amazon Relational Database Service"] }
      }
      rds  = { amount = 800, filter = { services = ["Amazon Relational Database Service"] } }
      team = { amount = 300, unit = "USD", time_unit = "QUARTERLY", metric = "AmortizedCost", filter = { tags = { Team = ["data"] } } }
    }
  }

  assert {
    condition     = aws_budgets_budget.this["account"].budget_type == "COST" && aws_budgets_budget.this["account"].time_unit == "MONTHLY" && aws_budgets_budget.this["account"].limit_amount == "5000" && aws_budgets_budget.this["account"].limit_unit == "USD"
    error_message = "A monthly USD cost budget by default."
  }

  assert {
    condition     = length(aws_budgets_budget.this["account"].filter_expression) == 0 && aws_budgets_budget.this["account"].metrics == null && length(aws_budgets_budget.this["account"].auto_adjust_data) == 0
    error_message = "No filter, metric or auto-adjust without a filter."
  }

  assert {
    condition = toset([for n in aws_budgets_budget.this["account"].notification : "${n.notification_type}/${n.comparison_operator}/${n.threshold}/${n.threshold_type}"]) == toset([
      "ACTUAL/GREATER_THAN/80/PERCENTAGE", "ACTUAL/GREATER_THAN/100/PERCENTAGE", "FORECASTED/GREATER_THAN/100/PERCENTAGE",
    ])
    error_message = "Default notifications: actual 80 %, actual 100 %, forecasted 100 %."
  }

  assert {
    condition     = alltrue([for n in aws_budgets_budget.this["core"].notification : n.subscriber_email_addresses == toset(["finops@example.com"]) && length(n.subscriber_sns_topic_arns) == 0])
    error_message = "Every notification reaches the emails; no SNS unless enabled."
  }

  assert {
    condition     = aws_budgets_budget.this["core"].metrics == tolist(["UnblendedCost"]) && length(aws_budgets_budget.this["core"].filter_expression[0].and) == 3
    error_message = "Several filters are combined with AND and use the metric."
  }

  assert {
    condition = [for a in aws_budgets_budget.this["core"].filter_expression[0].and : length(a.dimensions) > 0 ? "${a.dimensions[0].key}=${join(",", a.dimensions[0].values)}" : "tag:${a.tags[0].key}=${join(",", a.tags[0].values)}"] == [
      "SERVICE=Amazon Relational Database Service", "tag:Application=core", "tag:Team=orders,payments",
    ]
    error_message = "Services first, then tags by key."
  }

  assert {
    condition     = aws_budgets_budget.this["rds"].filter_expression[0].dimensions[0].key == "SERVICE" && aws_budgets_budget.this["rds"].filter_expression[0].dimensions[0].values == tolist(["Amazon Relational Database Service"]) && length(aws_budgets_budget.this["rds"].filter_expression[0].and) == 0
    error_message = "A single service filter is a plain dimension."
  }

  assert {
    condition     = aws_budgets_budget.this["team"].filter_expression[0].tags[0].key == "Team" && aws_budgets_budget.this["team"].filter_expression[0].tags[0].values == tolist(["data"]) && aws_budgets_budget.this["team"].metrics == tolist(["AmortizedCost"]) && aws_budgets_budget.this["team"].time_unit == "QUARTERLY"
    error_message = "A single tag filter is a plain tag expression."
  }
}

run "linked_account_filter_and_custom_notifications" {
  command = plan

  variables {
    budgets = {
      members = {
        amount        = 2000
        filter        = { linked_accounts = ["111122223333"] }
        notifications = [{ type = "ACTUAL", threshold = 1500, threshold_type = "ABSOLUTE_VALUE" }]
      }
    }
  }

  assert {
    condition     = aws_budgets_budget.this["members"].filter_expression[0].dimensions[0].key == "LINKED_ACCOUNT" && aws_budgets_budget.this["members"].filter_expression[0].dimensions[0].values == tolist(["111122223333"])
    error_message = "Linked accounts filter on LINKED_ACCOUNT."
  }

  assert {
    condition     = [for n in aws_budgets_budget.this["members"].notification : "${n.notification_type}/${n.comparison_operator}/${n.threshold}/${n.threshold_type}"] == ["ACTUAL/GREATER_THAN/1500/ABSOLUTE_VALUE"]
    error_message = "Custom notifications replace the defaults."
  }
}

run "auto_adjusting_budget" {
  command = plan

  variables {
    budgets = { trend = { auto_adjust = { enabled = true, lookback_periods = 6 } } }
  }

  assert {
    condition     = aws_budgets_budget.this["trend"].auto_adjust_data[0].auto_adjust_type == "HISTORICAL" && aws_budgets_budget.this["trend"].auto_adjust_data[0].historical_options[0].budget_adjustment_period == 6
    error_message = "Auto-adjust uses the historical average of lookback_periods."
  }
}

run "sns_immediate_subscription" {
  command = plan

  variables {
    notifications = { sns = { enabled = true, topic_arn = "arn:aws:sns:us-east-1:123456789012:platform-prod-warning" } }
    budgets       = { account = { amount = 1000 } }
  }

  assert {
    condition     = keys(aws_ce_anomaly_subscription.this) == ["immediate"] && aws_ce_anomaly_subscription.this["immediate"].frequency == "IMMEDIATE"
    error_message = "SNS gets individual alerts; no daily summary without emails."
  }

  assert {
    condition     = [for s in aws_ce_anomaly_subscription.this["immediate"].subscriber : { type = s.type, address = s.address }] == [{ type = "SNS", address = "arn:aws:sns:us-east-1:123456789012:platform-prod-warning" }]
    error_message = "The topic is the only immediate subscriber."
  }

  assert {
    condition     = alltrue([for n in aws_budgets_budget.this["account"].notification : n.subscriber_sns_topic_arns == toset(["arn:aws:sns:us-east-1:123456789012:platform-prod-warning"]) && length(n.subscriber_email_addresses) == 0])
    error_message = "Budget notifications publish to the topic."
  }
}

run "sns_and_emails" {
  command = plan

  variables {
    notifications = {
      sns    = { enabled = true, topic_arn = "arn:aws:sns:us-east-1:123456789012:platform-prod-warning" }
      emails = ["finops@example.com", "finops@example.com", "cfo@example.com"]
    }
  }

  assert {
    condition     = keys(aws_ce_anomaly_subscription.this) == ["daily", "immediate"]
    error_message = "SNS and emails get one subscription each."
  }

  assert {
    condition     = toset([for s in aws_ce_anomaly_subscription.this["daily"].subscriber : s.address]) == toset(["finops@example.com", "cfo@example.com"]) && alltrue([for s in aws_ce_anomaly_subscription.this["daily"].subscriber : s.type == "EMAIL"])
    error_message = "Duplicate emails subscribe once."
  }
}

run "existing_service_monitor" {
  command = plan

  variables {
    anomaly_detection = { service_monitor = { create = false, arn = "arn:aws:ce::123456789012:anomalymonitor/abcdef12-1234-4ea0-84cc-918a97d736ef" } }
  }

  assert {
    condition     = length(aws_ce_anomaly_monitor.services) == 0
    error_message = "No services monitor is created when one exists."
  }

  assert {
    condition     = aws_ce_anomaly_subscription.this["daily"].monitor_arn_list == tolist(["arn:aws:ce::123456789012:anomalymonitor/abcdef12-1234-4ea0-84cc-918a97d736ef"])
    error_message = "The subscription uses the existing monitor."
  }

  assert {
    condition     = output.anomaly_monitor_arns == { services = "arn:aws:ce::123456789012:anomalymonitor/abcdef12-1234-4ea0-84cc-918a97d736ef" }
    error_message = "The existing monitor is in the output."
  }
}

run "custom_monitors" {
  command = plan

  variables {
    anomaly_detection = {
      custom_monitors = {
        core    = { tag = { key = "Application", values = ["core", "orders"] } }
        members = { linked_accounts = ["111122223333", "444455556666"] }
        retail  = { cost_category = { key = "BusinessUnit", value = "retail" } }
      }
    }
  }

  assert {
    condition     = alltrue([for k, m in aws_ce_anomaly_monitor.custom : m.monitor_type == "CUSTOM" && m.monitor_dimension == null]) && length(aws_ce_anomaly_monitor.services) == 1
    error_message = "Custom monitors next to the services monitor."
  }

  assert {
    condition = jsondecode(aws_ce_anomaly_monitor.custom["core"].monitor_specification) == {
      And               = null
      CostCategories    = null
      Dimensions        = null
      Not               = null
      Or                = null
      ProductAttributes = null
      Tags              = { Key = "Application", MatchOptions = null, Values = ["core", "orders"] }
    }
    error_message = "A tag monitor tracks one key and its values; every Expression field is present."
  }

  assert {
    condition     = jsondecode(aws_ce_anomaly_monitor.custom["members"].monitor_specification).Dimensions == { Key = "LINKED_ACCOUNT", MatchOptions = null, Values = ["111122223333", "444455556666"] } && jsondecode(aws_ce_anomaly_monitor.custom["members"].monitor_specification).Tags == null
    error_message = "A linked account monitor uses the LINKED_ACCOUNT dimension."
  }

  assert {
    condition     = jsondecode(aws_ce_anomaly_monitor.custom["retail"].monitor_specification).CostCategories == { Key = "BusinessUnit", MatchOptions = null, Values = ["retail"] }
    error_message = "A cost category monitor tracks one value."
  }

  assert {
    condition     = aws_ce_anomaly_monitor.custom["core"].name == "platform-prod-core" && aws_ce_anomaly_monitor.custom["retail"].tags["Name"] == "platform-prod-retail"
    error_message = "Custom monitors are <application>-<environment>-<key>."
  }
}

run "threshold_absolute_or_percentage" {
  command = plan

  variables {
    anomaly_detection = { threshold = { absolute = 250, percentage = 40 } }
  }

  assert {
    condition     = length(aws_ce_anomaly_subscription.this["daily"].threshold_expression[0].dimension) == 0 && length(aws_ce_anomaly_subscription.this["daily"].threshold_expression[0].or) == 2
    error_message = "Two thresholds are combined with OR."
  }

  assert {
    condition = toset([for o in aws_ce_anomaly_subscription.this["daily"].threshold_expression[0].or : "${o.dimension[0].key}>=${one(o.dimension[0].values)}" if o.dimension[0].match_options == toset(["GREATER_THAN_OR_EQUAL"])]) == toset([
      "ANOMALY_TOTAL_IMPACT_ABSOLUTE>=250", "ANOMALY_TOTAL_IMPACT_PERCENTAGE>=40",
    ])
    error_message = "Absolute and percentage impact, both GREATER_THAN_OR_EQUAL."
  }
}

run "threshold_percentage_only" {
  command = plan

  variables {
    anomaly_detection = { threshold = { percentage = 25.5 } }
  }

  assert {
    condition     = aws_ce_anomaly_subscription.this["daily"].threshold_expression[0].dimension[0].key == "ANOMALY_TOTAL_IMPACT_PERCENTAGE" && aws_ce_anomaly_subscription.this["daily"].threshold_expression[0].dimension[0].values == toset(["25.5"]) && length(aws_ce_anomaly_subscription.this["daily"].threshold_expression[0].or) == 0
    error_message = "A single percentage threshold is a plain dimension."
  }
}

run "cost_allocation_tags_default_keys" {
  command = plan

  variables {
    cost_allocation_tags = { enabled = true }
  }

  assert {
    condition     = keys(aws_ce_cost_allocation_tag.this) == ["Application", "Environment", "ManagedBy"] && alltrue([for k, t in aws_ce_cost_allocation_tag.this : t.status == "Active" && t.tag_key == k])
    error_message = "The governance tag keys are activated."
  }
}

run "cost_allocation_tags_custom_keys" {
  command = plan

  variables {
    cost_allocation_tags = { enabled = true, keys = ["CostCenter", "Application", "CostCenter"] }
  }

  assert {
    condition     = keys(aws_ce_cost_allocation_tag.this) == ["Application", "CostCenter"]
    error_message = "Each key is activated once."
  }
}

run "names_and_tags" {
  command = plan

  variables {
    application = "abcdefghijklmnopqrstuvwx"
    environment = "prod-eu-west"
    tags        = { Team = "finops", Environment = "override-attempt" }
    budgets     = { a2345678901234567890123456789012 = { amount = 100 } }
    notifications = {
      sns    = { enabled = true, topic_arn = "arn:aws:sns:us-east-1:123456789012:platform-prod-warning" }
      emails = ["finops@example.com"]
    }
  }

  assert {
    condition     = aws_budgets_budget.this["a2345678901234567890123456789012"].name == "abcdefghijklmnopqrstuvwx-prod-eu-west-a2345678901234567890123456789012"
    error_message = "Budget names are <application>-<environment>-<key>, kept whole, no Region."
  }

  assert {
    condition     = aws_ce_anomaly_monitor.services[0].name == "abcdefghijklmnopqrstuvwx-prod-eu-west-services" && aws_ce_anomaly_subscription.this["immediate"].name == "abcdefghijklmnopqrstuvwx-prod-eu-west-anomalies-immediate" && aws_ce_anomaly_subscription.this["daily"].name == "abcdefghijklmnopqrstuvwx-prod-eu-west-anomalies-daily"
    error_message = "Monitor and subscription names carry no Region or account."
  }

  assert {
    condition = alltrue([for t in [
      aws_budgets_budget.this["a2345678901234567890123456789012"].tags, aws_ce_anomaly_monitor.services[0].tags,
      aws_ce_anomaly_subscription.this["immediate"].tags, aws_ce_anomaly_subscription.this["daily"].tags,
    ] : t["Application"] == "abcdefghijklmnopqrstuvwx" && t["Environment"] == "prod-eu-west" && t["ManagedBy"] == "Terraform" && t["Team"] == "finops"])
    error_message = "Caller tags kept, governance tags win."
  }

  assert {
    condition     = aws_budgets_budget.this["a2345678901234567890123456789012"].tags["Name"] == aws_budgets_budget.this["a2345678901234567890123456789012"].name && aws_ce_anomaly_subscription.this["daily"].tags["Name"] == aws_ce_anomaly_subscription.this["daily"].name
    error_message = "Name is the resource name."
  }
}

run "default_application_is_platform" {
  command = plan

  variables {
    budgets = { account = { amount = 1000 } }
  }

  assert {
    condition     = aws_budgets_budget.this["account"].name == "platform-prod-account" && aws_ce_anomaly_monitor.services[0].name == "platform-prod-services"
    error_message = "application defaults to platform."
  }
}

run "anomaly_detection_disabled" {
  command = plan

  variables {
    anomaly_detection = { enabled = false }
    notifications     = {}
  }

  assert {
    condition     = length(aws_ce_anomaly_monitor.services) + length(aws_ce_anomaly_monitor.custom) + length(aws_ce_anomaly_subscription.this) + length(aws_budgets_budget.this) == 0
    error_message = "Nothing is created; no subscribers are needed."
  }

  assert {
    condition     = output.anomaly_monitor_arns == {} && output.anomaly_subscription_arns == {}
    error_message = "Empty outputs when disabled."
  }
}

run "apply_outputs" {
  command   = apply
  state_key = "apply"

  variables {
    budgets = { account = { amount = 5000 } }
    notifications = {
      sns    = { enabled = true, topic_arn = "arn:aws:sns:us-east-1:123456789012:platform-prod-warning" }
      emails = ["finops@example.com"]
    }
    anomaly_detection    = { custom_monitors = { core = { tag = { key = "Application", values = ["core"] } } } }
    cost_allocation_tags = { enabled = true, keys = ["Application"] }
  }

  assert {
    condition     = output.budget_arns == { account = "arn:aws:budgets::123456789012:budget/platform-prod-account" } && output.budget_names == { account = "platform-prod-account" }
    error_message = "Budget outputs by key."
  }

  assert {
    condition = output.anomaly_monitor_arns == {
      services = "arn:aws:ce::123456789012:anomalymonitor/11111111-2222-3333-4444-555555555555"
      core     = "arn:aws:ce::123456789012:anomalymonitor/11111111-2222-3333-4444-555555555555"
    }
    error_message = "Monitor outputs by key."
  }

  assert {
    condition     = alltrue([for k, s in aws_ce_anomaly_subscription.this : s.monitor_arn_list == tolist([aws_ce_anomaly_monitor.services[0].arn, aws_ce_anomaly_monitor.custom["core"].arn])])
    error_message = "Every subscription covers every monitor."
  }

  assert {
    condition     = keys(output.anomaly_subscription_arns) == ["daily", "immediate"] && output.anomaly_subscription_arns["daily"] == "arn:aws:ce::123456789012:anomalysubscription/66666666-7777-8888-9999-000000000000"
    error_message = "Subscription outputs by frequency."
  }

  assert {
    condition     = output.cost_allocation_tag_keys == tolist(["Application"])
    error_message = "Activated keys are output."
  }
}

run "rejects_topic_in_another_account" {
  command = plan

  variables {
    budgets       = { account = { amount = 1000 } }
    notifications = { sns = { enabled = true, topic_arn = "arn:aws:sns:us-east-1:222222222222:finance-alerts" } }
  }

  expect_failures = [aws_budgets_budget.this]
}

run "rejects_invalid_application" {
  command = plan

  variables {
    application = "Platform"
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

run "rejects_invalid_topic_arn" {
  command = plan

  variables {
    notifications = { sns = { enabled = true, topic_arn = "platform-prod-warning" } }
  }

  expect_failures = [var.notifications]
}

run "rejects_invalid_emails" {
  command = plan

  variables {
    notifications = { emails = ["finops"] }
  }

  expect_failures = [var.notifications]
}

run "rejects_missing_subscribers" {
  command = plan

  variables {
    notifications = {}
  }

  expect_failures = [var.notifications]
}

run "rejects_invalid_budget_key" {
  command = plan

  variables {
    budgets = { a23456789012345678901234567890123 = { amount = 100 } }
  }

  expect_failures = [var.budgets]
}

run "rejects_missing_amount" {
  command = plan

  variables {
    budgets = { account = {} }
  }

  expect_failures = [var.budgets]
}

run "rejects_invalid_time_unit" {
  command = plan

  variables {
    budgets = { account = { amount = 100, time_unit = "WEEKLY" } }
  }

  expect_failures = [var.budgets]
}

run "rejects_invalid_notification" {
  command = plan

  variables {
    budgets = { account = { amount = 100, notifications = [{ type = "PREDICTED", threshold = 90 }] } }
  }

  expect_failures = [var.budgets]
}

run "rejects_invalid_linked_account" {
  command = plan

  variables {
    budgets = { account = { amount = 100, filter = { linked_accounts = ["1234"] } } }
  }

  expect_failures = [var.budgets]
}

run "rejects_invalid_lookback" {
  command = plan

  variables {
    budgets = { trend = { auto_adjust = { enabled = true, lookback_periods = 13 } } }
  }

  expect_failures = [var.budgets]
}

run "rejects_create_and_arn" {
  command = plan

  variables {
    anomaly_detection = { service_monitor = { create = true, arn = "arn:aws:ce::123456789012:anomalymonitor/abcdef12-1234-4ea0-84cc-918a97d736ef" } }
  }

  expect_failures = [var.anomaly_detection]
}

run "rejects_invalid_monitor_arn" {
  command = plan

  variables {
    anomaly_detection = { service_monitor = { create = false, arn = "arn:aws:sns:us-east-1:123456789012:platform-prod-warning" } }
  }

  expect_failures = [var.anomaly_detection]
}

run "rejects_no_monitor" {
  command = plan

  variables {
    anomaly_detection = { service_monitor = { create = false } }
  }

  expect_failures = [var.anomaly_detection]
}

run "rejects_custom_monitor_named_services" {
  command = plan

  variables {
    anomaly_detection = { custom_monitors = { services = { linked_accounts = ["111122223333"] } } }
  }

  expect_failures = [var.anomaly_detection]
}

run "rejects_custom_monitor_with_two_filters" {
  command = plan

  variables {
    anomaly_detection = { custom_monitors = { core = { linked_accounts = ["111122223333"], tag = { key = "Application", values = ["core"] } } } }
  }

  expect_failures = [var.anomaly_detection]
}

run "rejects_missing_threshold" {
  command = plan

  variables {
    anomaly_detection = { threshold = {} }
  }

  expect_failures = [var.anomaly_detection]
}

run "rejects_empty_cost_allocation_tag_keys" {
  command = plan

  variables {
    cost_allocation_tags = { enabled = true, keys = [] }
  }

  expect_failures = [var.cost_allocation_tags]
}
