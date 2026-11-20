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

  mock_resource "aws_inspector2_filter" {
    defaults = {
      arn = "arn:aws:inspector2:eu-west-1:123456789012:owner/123456789012/filter/a1b2c3d4"
    }
  }

  mock_resource "aws_inspector2_member_association" {
    defaults = {
      relationship_status = "ENABLED"
    }
  }
}

variables {
  environment = "prod"
  tags        = { Team = "security" }
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = keys(aws_inspector2_organization_configuration.this) == ["eu-west-1"] && keys(aws_inspector2_enabler.admin) == ["eu-west-1"]
    error_message = "Defaults: organization configuration and administrator activation in the provider Region."
  }

  assert {
    condition = (
      aws_inspector2_organization_configuration.this["eu-west-1"].auto_enable[0].ec2 &&
      aws_inspector2_organization_configuration.this["eu-west-1"].auto_enable[0].ecr &&
      aws_inspector2_organization_configuration.this["eu-west-1"].auto_enable[0].lambda &&
      aws_inspector2_organization_configuration.this["eu-west-1"].auto_enable[0].lambda_code &&
      !aws_inspector2_organization_configuration.this["eu-west-1"].auto_enable[0].code_repository
    )
    error_message = "EC2, ECR, Lambda and Lambda code scanning are auto-enabled; code repositories are opt-in."
  }

  assert {
    condition     = aws_inspector2_enabler.admin["eu-west-1"].account_ids == toset(["123456789012"]) && aws_inspector2_enabler.admin["eu-west-1"].resource_types == toset(["EC2", "ECR", "LAMBDA", "LAMBDA_CODE"])
    error_message = "The administrator scans its own resources with the auto-enabled types."
  }

  assert {
    condition     = length(aws_inspector2_delegated_admin_account.this) + length(aws_inspector2_member_association.this) + length(aws_inspector2_enabler.members) + length(aws_inspector2_filter.this) == 0
    error_message = "No designation, members or filters by default."
  }

  assert {
    condition     = output.member_associations == {} && output.filter_arns == {}
    error_message = "Empty outputs by default."
  }
}

run "regions_fan_out" {
  command = plan

  variables {
    regions            = ["us-east-1", "eu-west-1", "us-east-1"]
    member_account_ids = ["210987654321"]
    filters = {
      low = { severity = [{ value = "LOW" }] }
    }
  }

  assert {
    condition     = keys(aws_inspector2_organization_configuration.this) == ["eu-west-1", "us-east-1"] && keys(aws_inspector2_enabler.admin) == ["eu-west-1", "us-east-1"] && keys(aws_inspector2_enabler.members) == ["eu-west-1", "us-east-1"]
    error_message = "Every Regional resource fans out over distinct regions."
  }

  assert {
    condition     = aws_inspector2_organization_configuration.this["us-east-1"].region == "us-east-1" && aws_inspector2_enabler.members["us-east-1"].region == "us-east-1"
    error_message = "The resource-level region argument carries the Region."
  }

  assert {
    condition     = keys(aws_inspector2_member_association.this) == ["210987654321/eu-west-1", "210987654321/us-east-1"] && keys(aws_inspector2_filter.this) == ["low/eu-west-1", "low/us-east-1"]
    error_message = "Members and filters exist per Region."
  }
}

run "management_account_call" {
  command = plan

  variables {
    regions                    = ["us-east-1", "eu-west-1"]
    organization_admin         = { enabled = true, account_id = "210987654321" }
    organization_configuration = { enabled = false }
  }

  assert {
    condition     = keys(aws_inspector2_delegated_admin_account.this) == ["eu-west-1", "us-east-1"] && aws_inspector2_delegated_admin_account.this["us-east-1"].account_id == "210987654321" && aws_inspector2_delegated_admin_account.this["us-east-1"].region == "us-east-1"
    error_message = "The management call designates the administrator in every Region."
  }

  assert {
    condition     = length(aws_inspector2_organization_configuration.this) + length(aws_inspector2_enabler.admin) + length(aws_inspector2_enabler.members) + length(aws_inspector2_filter.this) == 0
    error_message = "The management call creates no administrator resources."
  }
}

run "scan_type_overrides" {
  command = plan

  variables {
    organization_configuration = {
      auto_enable = { ec2 = false, lambda = false, lambda_code = false, code_repository = true }
    }
  }

  assert {
    condition     = !aws_inspector2_organization_configuration.this["eu-west-1"].auto_enable[0].ec2 && aws_inspector2_organization_configuration.this["eu-west-1"].auto_enable[0].code_repository
    error_message = "auto_enable overrides reach the organization configuration."
  }

  assert {
    condition     = aws_inspector2_enabler.admin["eu-west-1"].resource_types == toset(["CODE_REPOSITORY", "ECR"])
    error_message = "The enabler activates only the selected types."
  }
}

run "administrator_activation_off" {
  command = plan

  variables {
    organization_configuration = { activate_admin_account = false }
  }

  assert {
    condition     = length(aws_inspector2_enabler.admin) == 0 && length(aws_inspector2_organization_configuration.this) == 1
    error_message = "activate_admin_account = false keeps the configuration and skips the administrator enabler."
  }
}

run "members_associated_and_activated" {
  command = apply

  variables {
    member_account_ids = ["210987654321", "345678901234", "210987654321"]
  }

  assert {
    condition     = aws_inspector2_member_association.this["210987654321/eu-west-1"].account_id == "210987654321" && length(aws_inspector2_member_association.this) == 2
    error_message = "Each distinct member is associated once per Region."
  }

  assert {
    condition     = aws_inspector2_enabler.members["eu-west-1"].account_ids == toset(["210987654321", "345678901234"]) && aws_inspector2_enabler.members["eu-west-1"].resource_types == toset(["EC2", "ECR", "LAMBDA", "LAMBDA_CODE"])
    error_message = "Members get the same scan types."
  }

  assert {
    condition     = output.member_associations["345678901234/eu-west-1"] == "ENABLED"
    error_message = "member_associations reports the relationship status."
  }
}

run "suppression_rules" {
  command = apply

  variables {
    regions = ["eu-west-1", "us-east-1"]
    filters = {
      accepted-cve = {
        description      = "Accepted risk"
        reason           = "Compensating control"
        vulnerability_id = [{ value = "CVE-2024-0001" }]
        resource_tags    = [{ key = "Environment", value = "dev" }]
      }
      info = {
        action   = "NONE"
        severity = [{ value = "INFORMATIONAL" }, { comparison = "NOT_EQUALS", value = "CRITICAL" }]
      }
    }
  }

  assert {
    condition     = aws_inspector2_filter.this["accepted-cve/us-east-1"].name == "platform-prod-accepted-cve" && aws_inspector2_filter.this["accepted-cve/us-east-1"].region == "us-east-1" && aws_inspector2_filter.this["accepted-cve/us-east-1"].action == "SUPPRESS"
    error_message = "Filters are named <application>-<environment>-<key> and suppress by default."
  }

  assert {
    condition     = aws_inspector2_filter.this["accepted-cve/eu-west-1"].reason == "Compensating control" && one(aws_inspector2_filter.this["accepted-cve/eu-west-1"].filter_criteria[0].resource_tags).comparison == "EQUALS"
    error_message = "Reason and tag criteria (EQUALS) reach the rule."
  }

  assert {
    condition     = aws_inspector2_filter.this["info/eu-west-1"].action == "NONE" && length(aws_inspector2_filter.this["info/eu-west-1"].filter_criteria[0].severity) == 2
    error_message = "Action and severity criteria reach the rule."
  }

  assert {
    condition     = aws_inspector2_filter.this["info/eu-west-1"].tags["Name"] == "platform-prod-info" && aws_inspector2_filter.this["info/eu-west-1"].tags["Team"] == "security" && aws_inspector2_filter.this["info/eu-west-1"].tags["Application"] == "platform" && aws_inspector2_filter.this["info/eu-west-1"].tags["ManagedBy"] == "Terraform"
    error_message = "Filters carry caller and governance tags."
  }

  assert {
    condition     = keys(output.filter_arns) == ["accepted-cve", "info"] && keys(output.filter_arns["info"]) == ["eu-west-1", "us-east-1"] && output.filter_arns["info"]["us-east-1"] == "arn:aws:inspector2:eu-west-1:123456789012:owner/123456789012/filter/a1b2c3d4"
    error_message = "filter_arns maps key, then Region, to the ARN."
  }
}

run "names_truncate_and_governance_tags_win" {
  command   = plan
  state_key = "naming"

  variables {
    application = "observability-platform"
    environment = "production"
    tags        = { Application = "spoofed", Owner = "secops" }
    filters = {
      accepted-risk-for-legacy-images = { finding_type = [{ value = "PACKAGE_VULNERABILITY" }] }
    }
  }

  assert {
    condition     = length(aws_inspector2_filter.this["accepted-risk-for-legacy-images/eu-west-1"].name) == 64 && startswith(aws_inspector2_filter.this["accepted-risk-for-legacy-images/eu-west-1"].name, "observability-platform-production-accepted-risk-for-legac")
    error_message = "Long filter names are cut to 64 characters with a hash suffix."
  }

  assert {
    condition     = aws_inspector2_filter.this["accepted-risk-for-legacy-images/eu-west-1"].tags["Application"] == "observability-platform" && aws_inspector2_filter.this["accepted-risk-for-legacy-images/eu-west-1"].tags["Owner"] == "secops"
    error_message = "Governance tags win over caller tags."
  }
}

run "rejects_invalid_application" {
  command = plan

  variables {
    application = "1platform"
  }

  expect_failures = [var.application]
}

run "rejects_invalid_environment" {
  command = plan

  variables {
    environment = "Prod"
  }

  expect_failures = [var.environment]
}

run "rejects_invalid_region" {
  command = plan

  variables {
    regions = ["eu-west"]
  }

  expect_failures = [var.regions]
}

run "rejects_malformed_admin_account" {
  command = plan

  variables {
    organization_admin         = { enabled = true, account_id = "12345" }
    organization_configuration = { enabled = false }
  }

  expect_failures = [var.organization_admin]
}

run "rejects_admin_with_organization_configuration" {
  command = plan

  variables {
    organization_admin = { enabled = true, account_id = "210987654321" }
  }

  expect_failures = [var.organization_admin]
}

run "rejects_management_account_as_admin" {
  command = plan

  variables {
    organization_admin         = { enabled = true, account_id = "123456789012" }
    organization_configuration = { enabled = false }
  }

  expect_failures = [aws_inspector2_delegated_admin_account.this]
}

run "rejects_lambda_code_without_lambda" {
  command = plan

  variables {
    organization_configuration = { auto_enable = { lambda = false } }
  }

  expect_failures = [var.organization_configuration]
}

run "rejects_no_scan_type" {
  command = plan

  variables {
    organization_configuration = { auto_enable = { ec2 = false, ecr = false, lambda = false, lambda_code = false } }
  }

  expect_failures = [var.organization_configuration]
}

run "rejects_malformed_member_account" {
  command = plan

  variables {
    member_account_ids = ["2109876543"]
  }

  expect_failures = [var.member_account_ids]
}

run "rejects_members_without_organization_configuration" {
  command = plan

  variables {
    organization_configuration = { enabled = false }
    member_account_ids         = ["210987654321"]
  }

  expect_failures = [var.member_account_ids]
}

run "rejects_administrator_as_member" {
  command = plan

  variables {
    member_account_ids = ["123456789012"]
  }

  expect_failures = [aws_inspector2_member_association.this]
}

run "rejects_invalid_filter_key" {
  command = plan

  variables {
    filters = {
      "Accepted_CVE" = { severity = [{ value = "LOW" }] }
    }
  }

  expect_failures = [var.filters]
}

run "rejects_invalid_filter_action" {
  command = plan

  variables {
    filters = {
      low = { action = "ARCHIVE", severity = [{ value = "LOW" }] }
    }
  }

  expect_failures = [var.filters]
}

run "rejects_filter_without_criteria" {
  command = plan

  variables {
    filters = {
      everything = {}
    }
  }

  expect_failures = [var.filters]
}

run "rejects_invalid_comparison" {
  command = plan

  variables {
    filters = {
      low = { severity = [{ comparison = "CONTAINS", value = "LOW" }] }
    }
  }

  expect_failures = [var.filters]
}

run "rejects_invalid_severity" {
  command = plan

  variables {
    filters = {
      low = { severity = [{ value = "SEVERE" }] }
    }
  }

  expect_failures = [var.filters]
}

run "rejects_invalid_finding_type" {
  command = plan

  variables {
    filters = {
      net = { finding_type = [{ value = "NETWORK" }] }
    }
  }

  expect_failures = [var.filters]
}

run "rejects_too_many_entries" {
  command = plan

  variables {
    filters = {
      cves = { vulnerability_id = [for i in range(11) : { value = "CVE-2024-000${i}" }] }
    }
  }

  expect_failures = [var.filters]
}

run "rejects_filters_without_organization_configuration" {
  command = plan

  variables {
    organization_configuration = { enabled = false }
    filters = {
      low = { severity = [{ value = "LOW" }] }
    }
  }

  expect_failures = [var.filters]
}
