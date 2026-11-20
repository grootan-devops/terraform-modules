locals {
  emails = distinct(var.notifications.emails)

  sns_topic_arns = var.notifications.sns.enabled ? [var.notifications.sns.topic_arn] : []

  budget_filters = {
    for key, budget in var.budgets : key => concat(
      [for c in [
        { when = length(budget.filter.services) > 0, kind = "dimensions", key = "SERVICE", values = budget.filter.services },
        { when = length(budget.filter.linked_accounts) > 0, kind = "dimensions", key = "LINKED_ACCOUNT", values = budget.filter.linked_accounts },
      ] : { kind = c.kind, key = c.key, values = c.values } if c.when],
      [for tag in sort(keys(budget.filter.tags)) : { kind = "tags", key = tag, values = budget.filter.tags[tag] }],
    )
  }

  service_monitor_arns = var.anomaly_detection.service_monitor.create ? aws_ce_anomaly_monitor.services[*].arn : compact([var.anomaly_detection.service_monitor.arn])

  monitor_arns = concat(local.service_monitor_arns, [for key in sort(keys(aws_ce_anomaly_monitor.custom)) : aws_ce_anomaly_monitor.custom[key].arn])

  monitor_specifications = {
    for key, monitor in var.anomaly_detection.custom_monitors : key => jsonencode({
      And               = null
      Not               = null
      Or                = null
      ProductAttributes = null
      Dimensions        = length(monitor.linked_accounts) > 0 ? { Key = "LINKED_ACCOUNT", MatchOptions = null, Values = monitor.linked_accounts } : null
      Tags              = monitor.tag == null ? null : { Key = monitor.tag.key, MatchOptions = null, Values = monitor.tag.values }
      CostCategories    = monitor.cost_category == null ? null : { Key = monitor.cost_category.key, MatchOptions = null, Values = [monitor.cost_category.value] }
    })
  }

  anomaly_subscriptions = {
    for key, subscription in {
      immediate = { when = var.anomaly_detection.enabled && var.notifications.sns.enabled, frequency = "IMMEDIATE", type = "SNS", addresses = local.sns_topic_arns }
      daily     = { when = var.anomaly_detection.enabled && length(var.notifications.emails) > 0, frequency = "DAILY", type = "EMAIL", addresses = local.emails }
    } : key => subscription if subscription.when
  }

  threshold_dimensions = [for c in [
    { when = var.anomaly_detection.threshold.absolute != null, key = "ANOMALY_TOTAL_IMPACT_ABSOLUTE", value = var.anomaly_detection.threshold.absolute },
    { when = var.anomaly_detection.threshold.percentage != null, key = "ANOMALY_TOTAL_IMPACT_PERCENTAGE", value = var.anomaly_detection.threshold.percentage },
  ] : { key = c.key, values = [tostring(c.value)] } if c.when]

  cost_allocation_tag_keys = var.cost_allocation_tags.enabled ? toset(var.cost_allocation_tags.keys) : toset([])
}
