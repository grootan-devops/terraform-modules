output "user_pool_id" {
  description = "Cognito user pool identifier."
  value       = aws_cognito_user_pool.this.id
}

output "user_pool_arn" {
  description = "Cognito user pool ARN."
  value       = aws_cognito_user_pool.this.arn
}

output "client_ids" {
  description = "Map of client key (from var.clients) -> Cognito app client id."
  value       = { for k, c in aws_cognito_user_pool_client.this : k => c.id }
}

output "user_pool_endpoint" {
  description = "The endpoint name of the user pool."
  value       = aws_cognito_user_pool.this.endpoint
}
