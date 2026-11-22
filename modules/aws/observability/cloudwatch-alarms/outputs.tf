output "alarm_arns" {
  description = "Alarm ARN by key."
  value       = { for k, a in aws_cloudwatch_metric_alarm.this : k => a.arn }
}

output "alarm_names" {
  description = "Alarm name by key."
  value       = { for k, a in aws_cloudwatch_metric_alarm.this : k => a.alarm_name }
}

output "metric_filter_names" {
  description = "Metric filter name by key."
  value = merge(
    { for k, f in aws_cloudwatch_log_metric_filter.this : "log-${k}" => f.name },
    { for k, f in aws_cloudwatch_log_metric_filter.cis : k => f.name },
  )
}

output "presets" {
  description = "Alarm keys created by each input."
  value       = { for p in local.preset_names : p => sort([for k, s in local.enabled_alarms : k if s.preset == p]) }
}

output "alarm_routes" {
  description = "Region, severity and topic ARN by alarm key."
  value = {
    for k, s in local.enabled_alarms : k => {
      region    = local.alarm_regions[k]
      severity  = s.severity
      topic_arn = var.notifications.enabled ? one(local.alarm_topic_arns[k]) : null
    }
  }
}

output "alarm_settings" {
  description = "Threshold, periods and datapoints by alarm key."
  value = {
    for k, s in local.enabled_alarms : k => {
      threshold           = s.threshold
      evaluation_periods  = s.evaluation_periods
      datapoints_to_alarm = s.datapoints_to_alarm
      period              = s.period
    }
  }
}
