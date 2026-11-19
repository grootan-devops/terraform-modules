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

variables {
  application    = "core"
  environment    = "prod"
  name           = "orders"
  log_group_name = "/aws/lambda/core-prod-orders"
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 365 && aws_cloudwatch_log_group.this.deletion_protection_enabled && aws_cloudwatch_log_group.this.log_group_class == "STANDARD" && aws_cloudwatch_log_group.this.kms_key_id == null
    error_message = "Defaults: 365 days, deletion protection, STANDARD class, service encryption."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.tags["Name"] == "/aws/lambda/core-prod-orders" && aws_cloudwatch_log_group.this.tags["Application"] == "core"
    error_message = "The log group must be tagged with its name and the governance tags."
  }
}

run "customer_key_and_region" {
  command = plan

  variables {
    kms_key_arn       = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
    region            = "us-east-1"
    retention_in_days = 731
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.kms_key_id == "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012" && aws_cloudwatch_log_group.this.region == "us-east-1" && aws_cloudwatch_log_group.this.retention_in_days == 731
    error_message = "Key, Region and retention must pass through."
  }
}

run "rejects_invalid_retention" {
  command = plan

  variables {
    retention_in_days = 100
  }

  expect_failures = [var.retention_in_days]
}

run "rejects_invalid_class" {
  command = plan

  variables {
    log_group_class = "COLD"
  }

  expect_failures = [var.log_group_class]
}

run "rejects_invalid_log_group_name" {
  command = plan

  variables {
    log_group_name = "bad name"
  }

  expect_failures = [var.log_group_name]
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Orders"
  }

  expect_failures = [var.name]
}

run "rejects_invalid_application" {
  command = plan

  variables {
    application = "Core"
  }

  expect_failures = [var.application]
}

run "rejects_invalid_environment" {
  command = plan

  variables {
    environment = "PROD"
  }

  expect_failures = [var.environment]
}
