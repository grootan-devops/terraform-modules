resource "aws_cloudwatch_log_group" "this" {
  name                        = "/aws/lambda/${local.rendered_name}"
  retention_in_days           = var.cloudwatch_logs.retention_in_days
  kms_key_id                  = coalesce(var.cloudwatch_logs.kms_key_id, var.kms_key_arn)
  deletion_protection_enabled = var.cloudwatch_logs.deletion_protection_enabled
  tags                        = local.tags
}

resource "aws_lambda_function" "this" {
  function_name = local.rendered_name
  description   = local.description
  role          = aws_iam_role.this.arn

  architectures = var.architectures

  dynamic "dead_letter_config" {
    for_each = var.dead_letter_config_target_arn != null ? [1] : []
    content {
      target_arn = var.dead_letter_config_target_arn
    }
  }

  dynamic "environment" {
    for_each = length(var.environment_variables) > 0 ? [1] : []
    content {
      variables = var.environment_variables
    }
  }

  ephemeral_storage {
    size = 512
  }

  filename  = var.package_type == "Image" ? null : (var.s3_bucket == null ? local.initial_filename : null)
  s3_bucket = var.package_type == "Image" ? null : var.s3_bucket
  s3_key    = var.package_type == "Image" ? null : var.s3_key

  handler      = var.package_type == "Image" ? null : local.effective_handler
  package_type = var.package_type
  image_uri    = var.package_type == "Image" ? var.image_uri : null

  kms_key_arn = var.kms_key_arn

  memory_size = var.memory_size

  publish = true

  runtime = var.package_type == "Image" ? null : var.runtime

  skip_destroy                   = false
  reserved_concurrent_executions = var.reserved_concurrent_executions

  source_kms_key_arn = var.source_kms_key_arn

  timeout = var.timeout

  tags = local.tags

  layers = concat(
    var.additional_layers,
    var.enable_lambda_insights ? ["arn:aws:lambda:${data.aws_region.current.region}:580247275435:layer:LambdaInsightsExtension${var.architectures[0] == "arm64" ? "-Arm64" : ""}:33"] : []
  )

  logging_config {
    application_log_level = "INFO"
    log_format            = "JSON"
    log_group             = aws_cloudwatch_log_group.this.name
    system_log_level      = "INFO"
  }

  dynamic "vpc_config" {
    for_each = var.vpc_config != null ? [1] : []
    content {
      security_group_ids = var.vpc_config.security_group_ids
      subnet_ids         = var.vpc_config.subnet_ids
    }
  }

  tracing_config {
    mode = var.tracing_config_mode
  }

  replace_security_groups_on_destroy = false

  depends_on = [
    aws_iam_role_policy_attachment.this,
    aws_iam_role_policy_attachment.custom,
  ]

  dynamic "durable_config" {
    for_each = var.durable_config != null ? [1] : []
    content {
      execution_timeout = var.durable_config.execution_timeout
      retention_period  = var.durable_config.retention_period
    }
  }

  lifecycle {
    ignore_changes = [
      filename,
      s3_bucket,
      s3_key,
      source_code_hash,
      image_uri,
      tags,
      tags_all
    ]

    precondition {
      condition = var.package_type == "Image" ? var.image_uri != null : ((
        var.filename != null &&
        var.s3_bucket == null &&
        var.s3_key == null
        ) || (
        var.filename == null &&
        var.s3_bucket != null &&
        var.s3_key != null
        ) || (
        var.filename == null &&
        var.s3_bucket == null &&
        var.s3_key == null
      ))
      error_message = "Provide image_uri when package_type is Image, or valid zip package inputs when package_type is Zip."
    }
  }
}
