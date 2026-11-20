output "id" {
  description = "Table ID."
  value       = aws_dynamodb_table.this.id
}

output "arn" {
  description = "Table ARN."
  value       = aws_dynamodb_table.this.arn
}

output "name" {
  description = "Table name."
  value       = aws_dynamodb_table.this.name
}

output "stream_arn" {
  description = "Stream ARN; null without a stream."
  value       = var.stream.enabled ? aws_dynamodb_table.this.stream_arn : null
}

output "global_secondary_index_names" {
  description = "Global secondary index names (GlobalSecondaryIndexName dimension)."
  value       = sort(keys(var.global_secondary_indexes))
  depends_on  = [aws_dynamodb_table.this]
}

output "kms_key_arn" {
  description = "Key ARN in use; null for the AWS managed key."
  value       = local.kms_key_arn
}

output "alarm_arns" {
  description = "Alarm ARN by key."
  value       = try(module.alarms[0].alarm_arns, {})
}

output "alarm_names" {
  description = "Alarm name by key."
  value       = try(module.alarms[0].alarm_names, {})
}
