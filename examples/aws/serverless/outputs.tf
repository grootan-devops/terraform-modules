output "invoke_url" {
  description = "API invoke URL."
  value       = module.api.invoke_url
}

output "http_api_endpoint" {
  description = "HTTP API endpoint."
  value       = module.http_api.api_endpoint
}

output "function_names" {
  description = "Function names."
  value       = [module.api_fn.name, module.worker_fn.name]
}

output "role_names" {
  description = "Execution role names."
  value       = [module.api_fn.role_name, module.worker_fn.role_name]
}

output "queue_name" {
  description = "Queue name."
  value       = module.orders_queue.name
}

output "rule_arns" {
  description = "Rule ARNs."
  value       = module.events.rule_arns
}
