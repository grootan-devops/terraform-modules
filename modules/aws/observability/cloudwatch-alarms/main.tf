module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.enabled_alarms

  alarm_name          = local.alarm_names[each.key]
  alarm_description   = each.value.description
  region              = each.value.region
  comparison_operator = each.value.comparison_operator
  threshold           = each.value.threshold
  evaluation_periods  = each.value.evaluation_periods
  datapoints_to_alarm = each.value.datapoints_to_alarm
  treat_missing_data  = each.value.treat_missing_data

  namespace          = length(each.value.queries) > 0 ? null : each.value.namespace
  metric_name        = length(each.value.queries) > 0 ? null : each.value.metric_name
  period             = length(each.value.queries) > 0 ? null : each.value.period
  statistic          = length(each.value.queries) > 0 ? null : each.value.statistic
  extended_statistic = length(each.value.queries) > 0 ? null : each.value.extended_statistic
  unit               = length(each.value.queries) > 0 ? null : each.value.unit
  dimensions         = length(each.value.queries) > 0 || length(each.value.dimensions) == 0 ? null : each.value.dimensions

  dynamic "metric_query" {
    for_each = each.value.queries

    content {
      id          = metric_query.value.id
      expression  = metric_query.value.expression
      label       = metric_query.value.label
      return_data = metric_query.value.return_data
      period      = metric_query.value.period

      dynamic "metric" {
        for_each = metric_query.value.metric == null ? [] : [metric_query.value.metric]

        content {
          namespace   = metric.value.namespace
          metric_name = metric.value.metric_name
          dimensions  = length(metric.value.dimensions) == 0 ? null : metric.value.dimensions
          stat        = metric.value.stat
          period      = metric.value.period
          unit        = metric.value.unit
        }
      }
    }
  }

  actions_enabled           = var.notifications.enabled
  alarm_actions             = var.notifications.enabled ? local.alarm_topic_arns[each.key] : []
  ok_actions                = var.notifications.enabled && var.notifications.notify_on_ok ? local.alarm_topic_arns[each.key] : []
  insufficient_data_actions = var.notifications.enabled && var.notifications.notify_on_insufficient_data ? local.alarm_topic_arns[each.key] : []

  tags = merge(module.naming.tags, { Name = local.alarm_names[each.key] })

  depends_on = [
    aws_cloudwatch_log_metric_filter.this,
    aws_cloudwatch_log_metric_filter.cis,
  ]

  lifecycle {
    precondition {
      condition     = each.value.threshold != null
      error_message = "Alarm ${each.key}: threshold required."
    }

    precondition {
      condition     = each.value.datapoints_to_alarm == null ? true : each.value.datapoints_to_alarm <= each.value.evaluation_periods
      error_message = "Alarm ${each.key}: datapoints_to_alarm above evaluation_periods."
    }

    precondition {
      condition     = !var.notifications.enabled || length(local.alarm_topic_arns[each.key]) == 1
      error_message = "Alarm ${each.key}: no topic for ${local.alarm_regions[each.key]}/${each.value.severity}."
    }

    precondition {
      condition     = length(local.duplicate_alarm_keys) == 0
      error_message = "Duplicate alarm keys: ${join(", ", local.duplicate_alarm_keys)}."
    }
  }
}

resource "aws_cloudwatch_log_metric_filter" "this" {
  for_each = var.log_metric_filters

  name           = local.log_filter_names[each.key]
  log_group_name = each.value.log_group_name
  pattern        = each.value.pattern
  region         = each.value.region

  metric_transformation {
    name          = coalesce(each.value.metric_name, each.key)
    namespace     = coalesce(each.value.namespace, local.log_metrics_namespace)
    value         = each.value.metric_value
    default_value = each.value.default_value
    unit          = each.value.unit
  }
}

resource "aws_cloudwatch_log_metric_filter" "cis" {
  for_each = local.cis_filters

  name           = local.cis_filter_names[each.key]
  log_group_name = var.cis_cloudtrail_metric_filters.log_group_name
  pattern        = each.value.pattern
  region         = var.cis_cloudtrail_metric_filters.region

  metric_transformation {
    name          = each.value.metric_name
    namespace     = local.cis_namespace
    value         = "1"
    default_value = "0"
  }
}
