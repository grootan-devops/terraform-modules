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
    condition     = output.role_names == ["shop-dev-api-exec-eu-west-1", "shop-dev-worker-exec-eu-west-1"]
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
}
