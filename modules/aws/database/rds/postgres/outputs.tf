output "id" {
  description = "The RDS instance identifier"
  value       = aws_db_instance.this.identifier
}

output "username" {
  description = "The master username for the database"
  value       = aws_db_instance.this.username
}

output "address" {
  description = "The RDS instance hostname."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "The RDS instance port."
  value       = aws_db_instance.this.port
}
