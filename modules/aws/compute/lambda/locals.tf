locals {
  rendered_name = var.name != null && var.name != "" ? "${var.application}-${var.environment}-${var.name}" : "${var.application}-${var.environment}"
  description   = "Lambda function for ${local.rendered_name}"
  runtime_family = var.package_type == "Image" ? null : (
    startswith(coalesce(var.runtime, ""), "nodejs") ? "nodejs" : (
      startswith(coalesce(var.runtime, ""), "python") ? "python" : null
    )
  )
  effective_handler = var.package_type == "Image" ? null : coalesce(
    var.handler,
    local.runtime_family == "nodejs" ? "index.handler" : "lambda_function.handler"
  )
  use_generated_bootstrap  = var.package_type == "Zip" && var.filename == null && var.s3_bucket == null && var.s3_key == null
  initial_filename         = local.use_generated_bootstrap ? data.archive_file.bootstrap[0].output_path : var.filename
  bootstrap_filename       = local.runtime_family == "nodejs" ? "index.js" : "lambda_function.py"
  bootstrap_response       = jsonencode({ message = var.bootstrap_message })
  node_bootstrap_content   = <<-EOT
    exports.handler = async () => ({
      statusCode: ${var.bootstrap_status_code},
      headers: {
        "Content-Type": "application/json"
      },
      body: ${jsonencode(local.bootstrap_response)}
    });
  EOT
  python_bootstrap_content = <<-EOT
    def handler(event, context):
        return {
            "statusCode": ${var.bootstrap_status_code},
            "headers": {"Content-Type": "application/json"},
            "body": ${jsonencode(local.bootstrap_response)}
        }
  EOT
  bootstrap_content        = local.runtime_family == "nodejs" ? local.node_bootstrap_content : local.python_bootstrap_content
  artifact_prefix          = coalesce(var.artifact_prefix, var.name, local.rendered_name)

  tags = merge(
    {
      Application = var.application
      Environment = var.environment
      Name        = local.rendered_name
    },
    var.tags
  )
}
