output "id" {
  description = "User pool ID."
  value       = aws_cognito_user_pool.this.id
}

output "arn" {
  description = "User pool ARN."
  value       = aws_cognito_user_pool.this.arn
}

output "name" {
  description = "User pool name."
  value       = aws_cognito_user_pool.this.name
}

output "endpoint" {
  description = "User pool endpoint (issuer host)."
  value       = aws_cognito_user_pool.this.endpoint
}

output "client_ids" {
  description = "App client IDs by name."
  value       = { for k, c in aws_cognito_user_pool_client.this : k => c.id }
}

output "domain" {
  description = "Hosted domain; null when disabled."
  value       = one(aws_cognito_user_pool_domain.this[*].domain)
}

output "domain_dns_name" {
  description = "CloudFront alias target of a custom domain."
  value       = one(aws_cognito_user_pool_domain.this[*].cloudfront_distribution)
}

output "domain_zone_id" {
  description = "Hosted zone ID of the alias target."
  value       = one(aws_cognito_user_pool_domain.this[*].cloudfront_distribution_zone_id)
}

output "log_group_name" {
  description = "Log group name; null when disabled."
  value       = one(module.log_group[*].name)
}

output "log_group_arn" {
  description = "Log group ARN; null when disabled."
  value       = one(module.log_group[*].arn)
}

output "kms_key_arn" {
  description = "Key ARN in use; null without a key."
  value       = local.kms_key_arn
}
