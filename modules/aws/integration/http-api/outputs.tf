output "id" {
  description = "HTTP API ID (ApiId dimension)."
  value       = aws_apigatewayv2_api.this.id
}

output "arn" {
  description = "HTTP API ARN."
  value       = aws_apigatewayv2_api.this.arn
}

output "name" {
  description = "HTTP API name."
  value       = aws_apigatewayv2_api.this.name
}

output "api_endpoint" {
  description = "Default execute-api endpoint."
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "execution_arn" {
  description = "Execution ARN for invoke permissions."
  value       = aws_apigatewayv2_api.this.execution_arn
}

output "stage_name" {
  description = "Stage name (Stage dimension)."
  value       = aws_apigatewayv2_stage.this.name
}

output "invoke_url" {
  description = "Stage invoke URL."
  value       = aws_apigatewayv2_stage.this.invoke_url
}

output "authorizer_ids" {
  description = "Authorizer IDs by key."
  value       = { for k, a in aws_apigatewayv2_authorizer.this : k => a.id }
}

output "log_group_name" {
  description = "Access log group name."
  value       = module.access_log_group.name
}

output "log_group_arn" {
  description = "Access log group ARN."
  value       = module.access_log_group.arn
}

output "kms_key_arn" {
  description = "Log key ARN in use; null for service encryption."
  value       = local.kms_key_arn
}

output "vpc_link_id" {
  description = "VPC link ID; null without a VPC link."
  value       = try(aws_apigatewayv2_vpc_link.this[0].id, null)
}

output "security_group_id" {
  description = "VPC link security group ID; null without one."
  value       = try(module.vpc_link_security_group[0].id, null)
}

output "domain_target_name" {
  description = "Custom domain target for Route 53 aliases; null without a domain."
  value       = try(aws_apigatewayv2_domain_name.this[0].domain_name_configuration[0].target_domain_name, null)
}

output "domain_zone_id" {
  description = "Custom domain hosted zone ID for Route 53 aliases; null without a domain."
  value       = try(aws_apigatewayv2_domain_name.this[0].domain_name_configuration[0].hosted_zone_id, null)
}
