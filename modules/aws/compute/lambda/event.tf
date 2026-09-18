resource "aws_lambda_event_source_mapping" "sqs" {
  for_each = var.sqs_event_sources

  function_name    = aws_lambda_alias.this.arn
  event_source_arn = each.value.arn

  enabled = true

  batch_size                         = each.value.batch_size
  maximum_batching_window_in_seconds = 0

  function_response_types = [
    "ReportBatchItemFailures"
  ]

  scaling_config {
    maximum_concurrency = each.value.maximum_concurrency
  }

  metrics_config {
    metrics = [
      "EventCount"
    ]
  }

  dynamic "filter_criteria" {
    for_each = each.value.filter_criteria_pattern != null ? [1] : []
    content {
      filter {
        pattern = each.value.filter_criteria_pattern
      }
    }
  }

  kms_key_arn = each.value.kms_key_arn

  tags = local.tags
}


resource "aws_lambda_function_event_invoke_config" "this" {
  count = var.async_invoke_config != null ? 1 : 0

  function_name = aws_lambda_function.this.function_name

  maximum_event_age_in_seconds = var.async_invoke_config.maximum_event_age_in_seconds
  maximum_retry_attempts       = var.async_invoke_config.maximum_retry_attempts

  qualifier = "$LATEST"

  destination_config {
    dynamic "on_success" {
      for_each = var.async_invoke_config.on_success_destination_arn != null ? [1] : []
      content {
        destination = var.async_invoke_config.on_success_destination_arn
      }
    }

    dynamic "on_failure" {
      for_each = var.async_invoke_config.on_failure_destination_arn != null ? [1] : []
      content {
        destination = var.async_invoke_config.on_failure_destination_arn
      }
    }
  }
}
