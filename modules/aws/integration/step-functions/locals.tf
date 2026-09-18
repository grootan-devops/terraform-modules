locals {
  rendered_name = "${var.application}-${var.environment}-${var.name}"

  invoke_resources = var.lambda_function_arns != null && length(var.lambda_function_arns) > 0 ? flatten([
    for arn in var.lambda_function_arns : [arn, "${arn}:*"]
  ]) : ["*"]

  tags = merge(
    {
      Application = var.application
      Environment = var.environment
      Name        = local.rendered_name
    },
    var.tags
  )
}
