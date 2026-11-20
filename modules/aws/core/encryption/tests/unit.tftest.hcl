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

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    }
  }
}

variables {
  application = "core"
  environment = "prod"
  name        = "orders"
  purpose     = "sqs"
}

run "aws_managed_key_by_default" {
  command = plan

  assert {
    condition     = output.key_arn == null && output.created == false && length(module.key) == 0
    error_message = "No input must mean the AWS managed key."
  }
}

run "module_key_with_service_statements" {
  command = apply

  variables {
    kms = { create = true, policy_statements = [{ sid = "Extra", actions = ["kms:Decrypt"], principals = { AWS = ["arn:aws:iam::123456789012:role/reader"] } }] }
    service_statements = [{
      sid        = "AllowLogs"
      actions    = ["kms:Encrypt*", "kms:Decrypt*"]
      principals = { Service = ["logs.eu-west-1.amazonaws.com"] }
    }]
  }

  assert {
    condition     = output.key_arn == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && output.created
    error_message = "create = true must return the module key."
  }

  assert {
    condition     = [for s in jsondecode(module.key[0].policy_json).Statement : s.Sid] == ["EnableIAMPolicies", "AllowLogs", "Extra"]
    error_message = "Service statements must come before caller statements."
  }
}

run "key_id_becomes_an_arn" {
  command = plan

  variables {
    kms = { key_id = "mrk-1234abcd12ab34cd56ef1234567890ab" }
  }

  assert {
    condition     = output.key_arn == "arn:aws:kms:eu-west-1:123456789012:key/mrk-1234abcd12ab34cd56ef1234567890ab"
    error_message = "A key ID must be turned into the key ARN."
  }
}

run "key_arn_passes_through" {
  command = plan

  variables {
    kms = { key_id = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555" }
  }

  assert {
    condition     = output.key_arn == "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    error_message = "A key ARN must pass through unchanged."
  }
}

run "rejects_create_and_key_id" {
  command = plan

  variables {
    kms = { create = true, key_id = "mrk-1234abcd12ab34cd56ef1234567890ab" }
  }

  expect_failures = [var.kms]
}

run "rejects_alias" {
  command = plan

  variables {
    kms = { key_id = "alias/aws/s3" }
  }

  expect_failures = [var.kms]
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
