# Coverage is limited to input validation for now. With a KMS key set, every plan
# of this module fails provider validation, because hashicorp/aws declares
# kms_master_key_id and sqs_managed_sse_enabled as conflicting arguments
# (main.tf lines 12-13 and 29-30). Naming, tag, security-default and parameter
# runs can be added once the module plans.

mock_provider "aws" {}

variables {
  application = "core"
  environment = "prod"
  name        = "events"
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
}

run "verify_invalid_environment_fails" {
  command = plan

  variables {
    environment = "INVALID_UPPERCASE"
  }

  expect_failures = [var.environment]
}
