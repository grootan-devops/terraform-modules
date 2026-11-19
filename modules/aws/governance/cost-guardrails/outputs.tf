output "budget_names" {
  description = "Budget name by key."
  value       = { for key, budget in aws_budgets_budget.this : key => budget.name }
}

output "budget_arns" {
  description = "Budget ARN by key."
  value       = { for key, budget in aws_budgets_budget.this : key => budget.arn }
}

output "anomaly_monitor_arns" {
  description = "Anomaly monitor ARN by key; services is the AWS services monitor."
  value = merge(
    var.anomaly_detection.enabled ? { for arn in local.service_monitor_arns : "services" => arn } : {},
    { for key, monitor in aws_ce_anomaly_monitor.custom : key => monitor.arn },
  )
}

output "anomaly_subscription_arns" {
  description = "Anomaly subscription ARN by frequency (immediate, daily)."
  value       = { for key, subscription in aws_ce_anomaly_subscription.this : key => subscription.arn }
}

output "cost_allocation_tag_keys" {
  description = "Activated cost allocation tag keys."
  value       = sort([for tag in aws_ce_cost_allocation_tag.this : tag.tag_key])
}
