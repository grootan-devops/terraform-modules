mock_provider "aws" {}

variables {
  application = "core"
  environment = "prod"
  name        = "db-credentials"
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
}

run "verify_security_defaults" {
  command = plan

  assert {
    condition     = aws_secretsmanager_secret.this.name == "core-prod-db-credentials"
    error_message = "Secret name did not match expected rendered name."
  }

  assert {
    condition     = aws_secretsmanager_secret.this.kms_key_id == var.kms_key_arn
    error_message = "KMS encryption key ARN was not properly assigned."
  }

  assert {
    condition     = aws_secretsmanager_secret.this.recovery_window_in_days == 30
    error_message = "Default recovery window must be 30 days."
  }

  assert {
    condition     = aws_secretsmanager_secret.this.tags["Application"] == "core" && aws_secretsmanager_secret.this.tags["Environment"] == "prod" && aws_secretsmanager_secret.this.tags["ManagedBy"] == "Terraform"
    error_message = "Governance tags (Application, Environment, ManagedBy) were not correctly merged."
  }
}

run "verify_tag_governance_precedence" {
  command = plan

  variables {
    tags = {
      Application = "hacked-app"
      ManagedBy   = "Manual"
      CustomTag   = "Allowed"
    }
  }

  assert {
    condition     = aws_secretsmanager_secret.this.tags["Application"] == "core"
    error_message = "Consumer tag should not overwrite Application governance tag."
  }

  assert {
    condition     = aws_secretsmanager_secret.this.tags["ManagedBy"] == "Terraform"
    error_message = "Consumer tag should not overwrite ManagedBy governance tag."
  }

  assert {
    condition     = aws_secretsmanager_secret.this.tags["CustomTag"] == "Allowed"
    error_message = "Consumer metadata tags must be preserved."
  }
}

run "verify_invalid_environment_fails" {
  command = plan

  variables {
    environment = "INVALID_UPPERCASE"
  }

  expect_failures = [
    var.environment
  ]
}

run "verify_invalid_recovery_window_fails" {
  command = plan

  variables {
    recovery_window_in_days = 5
  }

  expect_failures = [
    var.recovery_window_in_days
  ]
}

run "verify_name_and_prefix_conflict_fails" {
  command = plan

  variables {
    name        = "db"
    name_prefix = "db-prefix-"
  }

  expect_failures = [
    var.name
  ]
}

run "verify_secret_policy_and_block_public" {
  command = plan

  variables {
    policy = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }

  assert {
    condition     = aws_secretsmanager_secret_policy.this[0].block_public_policy == true
    error_message = "Secret policy must default block_public_policy to true."
  }
}

run "verify_payload_mutual_exclusivity_fails" {
  command = plan

  variables {
    secret_string    = "sensitive-data"
    secret_string_wo = "write-only-data"
  }

  expect_failures = [
    aws_secretsmanager_secret_version.this
  ]
}
