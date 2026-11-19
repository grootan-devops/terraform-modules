module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  tags        = var.tags
  names = merge(
    { for key in keys(var.budgets) : "budget-${key}" => { suffix = key, uniqueness = "region", max_length = 100 } },
    { for key in keys(var.anomaly_detection.custom_monitors) : "monitor-${key}" => { suffix = key, uniqueness = "region", max_length = 1024 } },
    {
      services  = { suffix = "services", uniqueness = "region", max_length = 1024 }
      immediate = { suffix = "anomalies-immediate", uniqueness = "region", max_length = 1024 }
      daily     = { suffix = "anomalies-daily", uniqueness = "region", max_length = 1024 }
    },
  )
}

resource "aws_budgets_budget" "this" {
  for_each = var.budgets

  name         = module.naming.names["budget-${each.key}"]
  budget_type  = each.value.type
  time_unit    = each.value.time_unit
  limit_amount = each.value.auto_adjust.enabled ? null : tostring(each.value.amount)
  limit_unit   = each.value.auto_adjust.enabled ? null : each.value.unit
  metrics      = length(local.budget_filters[each.key]) > 0 ? [each.value.metric] : null

  dynamic "auto_adjust_data" {
    for_each = each.value.auto_adjust.enabled ? [each.value.auto_adjust.lookback_periods] : []

    content {
      auto_adjust_type = "HISTORICAL"

      historical_options {
        budget_adjustment_period = auto_adjust_data.value
      }
    }
  }

  dynamic "filter_expression" {
    for_each = length(local.budget_filters[each.key]) > 0 ? [local.budget_filters[each.key]] : []

    content {
      dynamic "and" {
        for_each = length(filter_expression.value) > 1 ? filter_expression.value : []
        iterator = operand

        content {
          dynamic "dimensions" {
            for_each = operand.value.kind == "dimensions" ? [operand.value] : []

            content {
              key    = dimensions.value.key
              values = dimensions.value.values
            }
          }

          dynamic "tags" {
            for_each = operand.value.kind == "tags" ? [operand.value] : []

            content {
              key    = tags.value.key
              values = tags.value.values
            }
          }
        }
      }

      dynamic "dimensions" {
        for_each = length(filter_expression.value) == 1 && filter_expression.value[0].kind == "dimensions" ? filter_expression.value : []

        content {
          key    = dimensions.value.key
          values = dimensions.value.values
        }
      }

      dynamic "tags" {
        for_each = length(filter_expression.value) == 1 && filter_expression.value[0].kind == "tags" ? filter_expression.value : []

        content {
          key    = tags.value.key
          values = tags.value.values
        }
      }
    }
  }

  dynamic "notification" {
    for_each = each.value.notifications

    content {
      notification_type          = notification.value.type
      comparison_operator        = notification.value.comparison_operator
      threshold                  = notification.value.threshold
      threshold_type             = notification.value.threshold_type
      subscriber_email_addresses = local.emails
      subscriber_sns_topic_arns  = local.sns_topic_arns
    }
  }

  tags = merge(module.naming.tags, { Name = module.naming.names["budget-${each.key}"] })

  lifecycle {
    precondition {
      condition     = !var.notifications.sns.enabled || try(split(":", var.notifications.sns.topic_arn)[4], "") == module.naming.account_id
      error_message = "notifications.sns.topic_arn: a topic in this account."
    }
  }
}

resource "aws_ce_anomaly_monitor" "services" {
  count = var.anomaly_detection.enabled && var.anomaly_detection.service_monitor.create ? 1 : 0

  name              = module.naming.names["services"]
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"

  tags = merge(module.naming.tags, { Name = module.naming.names["services"] })
}

resource "aws_ce_anomaly_monitor" "custom" {
  for_each = var.anomaly_detection.enabled ? var.anomaly_detection.custom_monitors : {}

  name                  = module.naming.names["monitor-${each.key}"]
  monitor_type          = "CUSTOM"
  monitor_specification = local.monitor_specifications[each.key]

  tags = merge(module.naming.tags, { Name = module.naming.names["monitor-${each.key}"] })
}

resource "aws_ce_anomaly_subscription" "this" {
  for_each = local.anomaly_subscriptions

  name             = module.naming.names[each.key]
  frequency        = each.value.frequency
  monitor_arn_list = local.monitor_arns

  dynamic "subscriber" {
    for_each = each.value.addresses

    content {
      type    = each.value.type
      address = subscriber.value
    }
  }

  threshold_expression {
    dynamic "dimension" {
      for_each = length(local.threshold_dimensions) == 1 ? local.threshold_dimensions : []

      content {
        key           = dimension.value.key
        match_options = ["GREATER_THAN_OR_EQUAL"]
        values        = dimension.value.values
      }
    }

    dynamic "or" {
      for_each = length(local.threshold_dimensions) > 1 ? local.threshold_dimensions : []
      iterator = operand

      content {
        dimension {
          key           = operand.value.key
          match_options = ["GREATER_THAN_OR_EQUAL"]
          values        = operand.value.values
        }
      }
    }
  }

  tags = merge(module.naming.tags, { Name = module.naming.names[each.key] })
}

resource "aws_ce_cost_allocation_tag" "this" {
  for_each = local.cost_allocation_tag_keys

  tag_key = each.key
  status  = "Active"
}
