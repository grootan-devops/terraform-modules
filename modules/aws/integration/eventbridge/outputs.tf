output "event_rules" {
  description = "Map of created EventBridge rules containing their ARNs."
  value = {
    for k, v in aws_cloudwatch_event_rule.this : k => {
      arn = v.arn
    }
  }
}

output "bus_arn" {
  description = "The ARN of the EventBridge bus."
  value       = var.create_bus ? aws_cloudwatch_event_bus.this[0].arn : null
}

output "bus_name" {
  description = "The name of the EventBridge bus."
  value       = local.bus_name
}
