resource "aws_lambda_event_source_mapping" "this" {
  for_each = var.event_sources

  function_name                      = aws_lambda_alias.this.arn
  event_source_arn                   = each.value.arn
  batch_size                         = each.value.batch_size
  maximum_batching_window_in_seconds = each.value.maximum_batching_window_in_seconds
  starting_position                  = each.value.type == "sqs" ? null : each.value.starting_position
  maximum_retry_attempts             = each.value.type == "sqs" ? null : each.value.maximum_retry_attempts
  function_response_types            = ["ReportBatchItemFailures"]

  dynamic "scaling_config" {
    for_each = each.value.type == "sqs" && each.value.maximum_concurrency != null ? [1] : []
    content {
      maximum_concurrency = each.value.maximum_concurrency
    }
  }

  dynamic "filter_criteria" {
    for_each = length(each.value.filter_patterns) > 0 ? [1] : []
    content {
      dynamic "filter" {
        for_each = each.value.filter_patterns
        content {
          pattern = filter.value
        }
      }
    }
  }

  dynamic "destination_config" {
    for_each = each.value.type != "sqs" && each.value.on_failure_destination_arn != null ? [1] : []
    content {
      on_failure {
        destination_arn = each.value.on_failure_destination_arn
      }
    }
  }

  metrics_config {
    metrics = ["EventCount"]
  }

  tags = merge(module.naming.tags, { Name = "${local.function_name}-${each.key}" })
}

resource "aws_lambda_permission" "this" {
  for_each = var.allowed_triggers

  statement_id   = each.key
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.this.function_name
  qualifier      = aws_lambda_alias.this.name
  principal      = each.value.principal
  source_arn     = each.value.source_arn
  source_account = coalesce(each.value.source_account, module.naming.account_id)
}

resource "aws_lambda_function_url" "this" {
  count = var.function_url.enabled ? 1 : 0

  function_name      = aws_lambda_function.this.function_name
  qualifier          = aws_lambda_alias.this.name
  authorization_type = "AWS_IAM"
  invoke_mode        = var.function_url.invoke_mode

  dynamic "cors" {
    for_each = var.function_url.cors == null ? [] : [var.function_url.cors]
    content {
      allow_origins     = cors.value.allow_origins
      allow_methods     = cors.value.allow_methods
      allow_headers     = cors.value.allow_headers
      expose_headers    = cors.value.expose_headers
      allow_credentials = cors.value.allow_credentials
      max_age           = cors.value.max_age
    }
  }
}

resource "aws_lambda_function_event_invoke_config" "this" {
  count = var.async_invoke.enabled ? 1 : 0

  function_name                = aws_lambda_function.this.function_name
  qualifier                    = aws_lambda_alias.this.name
  maximum_retry_attempts       = var.async_invoke.maximum_retry_attempts
  maximum_event_age_in_seconds = var.async_invoke.maximum_event_age_in_seconds

  dynamic "destination_config" {
    for_each = var.async_invoke.on_success_destination_arn == null && var.async_invoke.on_failure_destination_arn == null ? [] : [1]
    content {
      dynamic "on_success" {
        for_each = var.async_invoke.on_success_destination_arn == null ? [] : [1]
        content {
          destination = var.async_invoke.on_success_destination_arn
        }
      }

      dynamic "on_failure" {
        for_each = var.async_invoke.on_failure_destination_arn == null ? [] : [1]
        content {
          destination = var.async_invoke.on_failure_destination_arn
        }
      }
    }
  }
}
