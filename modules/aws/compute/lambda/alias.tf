resource "aws_lambda_alias" "this" {
  name = var.alias_name

  function_name    = aws_lambda_function.this.function_name
  function_version = aws_lambda_function.this.version

  lifecycle {
    ignore_changes = [
      function_version,
      description
    ]
  }
}

resource "aws_lambda_function_recursion_config" "this" {
  function_name  = aws_lambda_function.this.function_name
  recursive_loop = "Terminate"
}

resource "aws_lambda_provisioned_concurrency_config" "this" {
  count = var.provisioned_concurrency != null ? 1 : 0

  function_name                     = aws_lambda_function.this.function_name
  provisioned_concurrent_executions = var.provisioned_concurrency
  qualifier                         = aws_lambda_alias.this.name
}

resource "aws_lambda_runtime_management_config" "this" {
  count = var.package_type == "Zip" ? 1 : 0

  function_name = aws_lambda_function.this.function_name

  update_runtime_on = var.runtime_management_config
  qualifier         = "$LATEST"
}
