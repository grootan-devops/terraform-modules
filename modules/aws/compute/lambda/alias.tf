resource "aws_lambda_alias" "this" {
  name             = var.alias_name
  function_name    = aws_lambda_function.this.function_name
  function_version = aws_lambda_function.this.version

  lifecycle {
    ignore_changes = [function_version, description, routing_config]
  }
}

resource "aws_lambda_provisioned_concurrency_config" "this" {
  count = var.concurrency.provisioned > 0 ? 1 : 0

  function_name                     = aws_lambda_function.this.function_name
  qualifier                         = aws_lambda_alias.this.name
  provisioned_concurrent_executions = var.concurrency.provisioned
}

resource "aws_lambda_function_recursion_config" "this" {
  function_name  = aws_lambda_function.this.function_name
  recursive_loop = "Terminate"
}

resource "aws_lambda_runtime_management_config" "this" {
  count = local.zip && var.runtime_update_mode != "Auto" ? 1 : 0

  function_name     = aws_lambda_function.this.function_name
  qualifier         = "$LATEST"
  update_runtime_on = var.runtime_update_mode
}
