mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "eu-west-1"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }
}

mock_provider "archive" {
  mock_data "archive_file" {
    defaults = {
      output_path = "placeholder.zip"
    }
  }
}

run "plans_with_unknown_arns" {
  command = plan

  assert {
    condition     = output.function_names == ["shop-dev-api", "shop-dev-worker"]
    error_message = "Two functions of one application must get distinct names."
  }

  assert {
    condition     = output.role_names == ["shop-dev-api-lambda-eu-west-1", "shop-dev-worker-lambda-eu-west-1"]
    error_message = "Execution roles must be distinct and carry the Region."
  }

  assert {
    condition     = module.events.schedule_group_name == "shop-dev-orders" && keys(module.events.schedule_arns) == ["nightly"] && keys(module.events.rule_arns) == ["order-created"]
    error_message = "The nightly job must be a schedule in the events group, not a scheduled rule."
  }

  assert {
    condition     = module.http_api.name == "shop-dev-public" && module.http_api.stage_name == "$default"
    error_message = "The HTTP API serves the same function behind the Cognito JWT authorizer."
  }

  assert {
    condition     = output.state_machine_name == "shop-dev-fulfilment" && module.fulfilment.log_group_name == "/aws/vendedlogs/states/shop-dev-fulfilment"
    error_message = "The fulfilment state machine and its vended log group follow the naming standard."
  }

  assert {
    condition     = module.fulfilment.role_name == "shop-dev-fulfilment-sfn-eu-west-1" && !contains(output.role_names, module.fulfilment.role_name)
    error_message = "The state machine has its own execution role, never a function's."
  }

  assert {
    condition     = sort(keys(module.worker_fn.alarm_names)) == tolist(["lambda-function-duration-p99", "lambda-function-error-rate", "lambda-function-iterator-age", "lambda-function-throttles"]) && length(module.api_fn.alarm_names) == 3
    error_message = "Each function gets its built-in alarms; the stream consumer also watches iterator age."
  }

  assert {
    condition     = contains(keys(module.orders_queue.alarm_names), "sqs-queue-dlq-messages-visible") && length(module.events.alarm_names) == 6 && length(module.api.alarm_names) == 4 && length(module.http_api.alarm_names) == 2 && length(module.orders_table.alarm_names) == 3
    error_message = "Queue, rule, schedule group, both APIs and the table get their built-in alarms without hand wiring."
  }

  assert {
    condition     = length(module.fulfilment.alarm_names) == 4
    error_message = "The state machine gets its built-in alarms."
  }
}
