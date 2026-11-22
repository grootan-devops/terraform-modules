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

  mock_resource "aws_ecr_repository" {
    defaults = {
      arn            = "arn:aws:ecr:eu-west-1:123456789012:repository/core-prod-orders"
      repository_url = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/core-prod-orders"
      registry_id    = "123456789012"
    }
  }
}

variables {
  application = "core"
  environment = "prod"
  name        = "orders"
  tags        = { Team = "payments" }
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = aws_ecr_repository.this.name == "core-prod-orders" && aws_ecr_repository.this.image_tag_mutability == "IMMUTABLE" && !aws_ecr_repository.this.force_delete
    error_message = "Defaults: <application>-<environment>-<name>, immutable tags, no force delete."
  }

  assert {
    condition     = aws_ecr_repository.this.image_scanning_configuration[0].scan_on_push && length(aws_ecr_repository.this.image_tag_mutability_exclusion_filter) == 0
    error_message = "Images must be scanned on push."
  }

  assert {
    condition     = aws_ecr_repository.this.encryption_configuration[0].encryption_type == "AES256" && output.kms_key_arn == null
    error_message = "No kms input means AES256."
  }

  assert {
    condition     = aws_ecr_repository.this.tags["Name"] == "core-prod-orders" && aws_ecr_repository.this.tags["Team"] == "payments" && aws_ecr_repository.this.tags["ManagedBy"] == "Terraform" && aws_ecr_repository.this.tags["Application"] == "core" && aws_ecr_repository.this.tags["Environment"] == "prod"
    error_message = "Caller and governance tags must be applied."
  }

  assert {
    condition     = length(aws_ecr_lifecycle_policy.this) == 1 && length(aws_ecr_repository_policy.this) == 0
    error_message = "A lifecycle policy by default, no repository policy."
  }
}

run "lifecycle_rules" {
  command = plan

  assert {
    condition     = jsondecode(aws_ecr_lifecycle_policy.this[0].policy).rules[0].selection == { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 14 }
    error_message = "Untagged images must expire after 14 days."
  }

  assert {
    condition     = jsondecode(aws_ecr_lifecycle_policy.this[0].policy).rules[1].selection == { tagStatus = "tagged", tagPatternList = ["*"], countType = "imageCountMoreThan", countNumber = 30 }
    error_message = "The last 30 tagged images must be kept."
  }
}

run "lifecycle_overrides_and_off" {
  command = plan

  variables {
    lifecycle_policy = { keep_tagged_images = 100, untagged_expiry_days = 1, tag_patterns = ["v*", "release-*"] }
  }

  assert {
    condition     = jsondecode(aws_ecr_lifecycle_policy.this[0].policy).rules[1].selection.countNumber == 100 && jsondecode(aws_ecr_lifecycle_policy.this[0].policy).rules[1].selection.tagPatternList == ["v*", "release-*"] && jsondecode(aws_ecr_lifecycle_policy.this[0].policy).rules[0].selection.countNumber == 1
    error_message = "lifecycle_policy must set the counts and tag patterns."
  }
}

run "lifecycle_disabled" {
  command = plan

  variables {
    lifecycle_policy = { enabled = false }
  }

  assert {
    condition     = length(aws_ecr_lifecycle_policy.this) == 0
    error_message = "lifecycle_policy.enabled = false must remove the policy."
  }
}

run "mutability_exclusions" {
  command = plan

  variables {
    image_tag_mutability                   = "IMMUTABLE_WITH_EXCLUSION"
    image_tag_mutability_exclusion_filters = ["latest", "dev-*"]
    scan_on_push                           = false
  }

  assert {
    condition     = aws_ecr_repository.this.image_tag_mutability == "IMMUTABLE_WITH_EXCLUSION" && [for f in aws_ecr_repository.this.image_tag_mutability_exclusion_filter : f.filter] == ["latest", "dev-*"] && alltrue([for f in aws_ecr_repository.this.image_tag_mutability_exclusion_filter : f.filter_type == "WILDCARD"])
    error_message = "Exclusion filters must be wildcards."
  }

  assert {
    condition     = !aws_ecr_repository.this.image_scanning_configuration[0].scan_on_push
    error_message = "scan_on_push must be configurable."
  }
}

run "module_key_is_planned_safely" {
  command = plan

  variables {
    kms = { create = true }
  }

  assert {
    condition     = module.encryption.created && aws_ecr_repository.this.encryption_configuration[0].encryption_type == "KMS"
    error_message = "kms.create must plan without knowing the key ARN."
  }
}

run "module_key_encrypts_repository" {
  command = apply

  variables {
    kms = { create = true }
  }

  assert {
    condition     = aws_ecr_repository.this.encryption_configuration[0].kms_key == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && output.kms_key_arn == aws_ecr_repository.this.encryption_configuration[0].kms_key
    error_message = "The module key must encrypt the repository."
  }

  assert {
    condition     = output.arn == "arn:aws:ecr:eu-west-1:123456789012:repository/core-prod-orders" && output.repository_url == "123456789012.dkr.ecr.eu-west-1.amazonaws.com/core-prod-orders" && output.registry_id == "123456789012" && output.name == "core-prod-orders"
    error_message = "Outputs must expose the repository."
  }
}

run "caller_key_id" {
  command = plan

  variables {
    kms = { key_id = "11111111-2222-3333-4444-555555555555" }
  }

  assert {
    condition     = aws_ecr_repository.this.encryption_configuration[0].encryption_type == "KMS" && aws_ecr_repository.this.encryption_configuration[0].kms_key == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    error_message = "A key ID must be used as the key ARN."
  }
}

run "repository_policy" {
  command   = apply
  state_key = "policy"

  variables {
    pull_principal_arns = ["arn:aws:iam::210987654321:root"]
    policy_statements = [{
      sid        = "LambdaPull"
      actions    = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
      principals = { Service = ["lambda.amazonaws.com"] }
      conditions = [{ test = "StringLike", variable = "aws:sourceArn", values = ["arn:aws:lambda:eu-west-1:123456789012:function:*"] }]
    }]
  }

  assert {
    condition     = [for s in jsondecode(aws_ecr_repository_policy.this[0].policy).Statement : s.Sid] == ["CrossAccountPull", "LambdaPull"]
    error_message = "Pull principals come first, then caller statements."
  }

  assert {
    condition     = jsondecode(aws_ecr_repository_policy.this[0].policy).Statement[0].Principal.AWS == ["arn:aws:iam::210987654321:root"] && jsondecode(aws_ecr_repository_policy.this[0].policy).Statement[0].Action == ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
    error_message = "Cross-account principals get pull actions only."
  }

  assert {
    condition     = alltrue([for s in jsondecode(aws_ecr_repository_policy.this[0].policy).Statement : s.Resource == ["arn:aws:ecr:eu-west-1:123456789012:repository/core-prod-orders"]])
    error_message = "Statements without resources must apply to the repository."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Orders_Repo"
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

run "rejects_invalid_mutability" {
  command = plan

  variables {
    image_tag_mutability = "LOCKED"
  }

  expect_failures = [var.image_tag_mutability]
}

run "rejects_too_many_exclusions" {
  command = plan

  variables {
    image_tag_mutability_exclusion_filters = ["a*", "b*", "c*", "d*", "e*", "f*"]
  }

  expect_failures = [var.image_tag_mutability_exclusion_filters]
}

run "rejects_create_and_key_id" {
  command = plan

  variables {
    kms = { create = true, key_id = "11111111-2222-3333-4444-555555555555" }
  }

  expect_failures = [var.kms]
}

run "rejects_invalid_key_id" {
  command = plan

  variables {
    kms = { key_id = "alias/ecr" }
  }

  expect_failures = [var.kms]
}

run "rejects_zero_lifecycle_count" {
  command = plan

  variables {
    lifecycle_policy = { keep_tagged_images = 0 }
  }

  expect_failures = [var.lifecycle_policy]
}

run "rejects_empty_tag_patterns" {
  command = plan

  variables {
    lifecycle_policy = { tag_patterns = [] }
  }

  expect_failures = [var.lifecycle_policy]
}

run "rejects_public_pull" {
  command = plan

  variables {
    pull_principal_arns = ["*"]
  }

  expect_failures = [var.pull_principal_arns]
}

run "rejects_statement_without_principal" {
  command = plan

  variables {
    policy_statements = [{ actions = ["ecr:BatchGetImage"] }]
  }

  expect_failures = [var.policy_statements]
}
