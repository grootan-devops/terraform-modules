output "endpoint" {
  description = "Default RDS Proxy endpoint."
  value       = aws_db_proxy.this.endpoint
}

output "arn" {
  description = "RDS Proxy ARN."
  value       = aws_db_proxy.this.arn
}
