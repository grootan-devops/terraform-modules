output "function_arn" {
  description = "The Amazon Resource Name (ARN) identifying your Lambda Function."
  value       = aws_lambda_function.this.arn
}

output "alias_arn" {
  description = "The ARN of the stable Lambda release alias."
  value       = aws_lambda_alias.this.arn
}

output "function_name" {
  description = "The unique name of the Lambda Function."
  value       = aws_lambda_function.this.function_name
}

output "role_arn" {
  description = "The ARN of the IAM role attached to the Lambda Function."
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "The name of the IAM role attached to the Lambda Function."
  value       = aws_iam_role.this.name
}
