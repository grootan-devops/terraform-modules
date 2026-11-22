output "support_role_arn" {
  description = "AWS Support role ARN; null when disabled."
  value       = try(module.support_role[0].arn, null)
}

output "support_role_name" {
  description = "AWS Support role name; null when disabled."
  value       = try(module.support_role[0].name, null)
}

output "api_gateway_role_arn" {
  description = "API Gateway CloudWatch Logs role ARN; null when disabled."
  value       = try(module.api_gateway_role[0].arn, null)
}

output "api_gateway_role_name" {
  description = "API Gateway CloudWatch Logs role name; null when disabled."
  value       = try(module.api_gateway_role[0].name, null)
}
