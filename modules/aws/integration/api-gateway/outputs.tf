output "rest_api_id" {
  description = "The ID of the REST API Gateway"
  value       = aws_api_gateway_rest_api.this.id
}

output "stage_name" {
  description = "The deployed stage name"
  value       = aws_api_gateway_stage.this.stage_name
}

output "execution_arn" {
  description = "The execution ARN of the REST API Gateway"
  value       = aws_api_gateway_rest_api.this.execution_arn
}

output "invoke_url" {
  description = "The URL to invoke the API pointing to the stage."
  value       = aws_api_gateway_stage.this.invoke_url
}
