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

  mock_resource "aws_accessanalyzer_analyzer" {
    defaults = {
      arn = "arn:aws:access-analyzer:eu-west-1:123456789012:analyzer/platform-prod-external"
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
    condition     = keys(aws_accessanalyzer_analyzer.external) == ["eu-west-1"] && aws_accessanalyzer_analyzer.external["eu-west-1"].type == "ORGANIZATION" && aws_accessanalyzer_analyzer.external["eu-west-1"].analyzer_name == "platform-prod-external"
    error_message = "Defaults: one organization external analyzer in the provider Region, named <application>-<environment>-external."
  }

  assert {
    condition     = length(aws_accessanalyzer_analyzer.unused) == 1 && aws_accessanalyzer_analyzer.unused[0].type == "ORGANIZATION_UNUSED_ACCESS" && aws_accessanalyzer_analyzer.unused[0].region == "eu-west-1" && aws_accessanalyzer_analyzer.unused[0].configuration[0].unused_access[0].unused_access_age == 90
    error_message = "The unused access analyzer is on with a 90-day tracking period."
  }

  assert {
    condition     = length(aws_accessanalyzer_analyzer.unused[0].configuration[0].unused_access[0].analysis_rule) == 0
    error_message = "No exclusions by default."
  }

  assert {
    condition     = length(aws_accessanalyzer_analyzer.internal) + length(aws_accessanalyzer_archive_rule.this) + length(aws_organizations_aws_service_access.this) + length(aws_organizations_delegated_administrator.this) == 0
    error_message = "No internal analyzer, archive rules or organization resources by default."
  }

  assert {
    condition     = aws_accessanalyzer_analyzer.external["eu-west-1"].tags["Name"] == "platform-prod-external" && aws_accessanalyzer_analyzer.external["eu-west-1"].tags["Team"] == "security" && aws_accessanalyzer_analyzer.external["eu-west-1"].tags["Application"] == "platform" && aws_accessanalyzer_analyzer.external["eu-west-1"].tags["ManagedBy"] == "Terraform"
    error_message = "Analyzers carry caller and governance tags."
  }

  assert {
    condition     = output.analyzer_names == { external = "platform-prod-external", unused = "platform-prod-unused" } && output.internal_access_analyzer_arn == null
    error_message = "analyzer_names lists only the analyzers this call creates."
  }
}

run "regions_fan_out" {
  command = plan

  variables {
    regions       = ["us-east-1", "eu-west-1", "us-east-1"]
    unused_access = { region = "us-east-1" }
  }

  assert {
    condition     = keys(aws_accessanalyzer_analyzer.external) == ["eu-west-1", "us-east-1"] && aws_accessanalyzer_analyzer.external["us-east-1"].region == "us-east-1"
    error_message = "One external analyzer per distinct Region."
  }

  assert {
    condition     = aws_accessanalyzer_analyzer.unused[0].region == "us-east-1"
    error_message = "unused_access.region places the unused analyzer."
  }
}

run "account_only_mode" {
  command = plan

  variables {
    regions                    = ["us-east-1", "eu-west-1"]
    organization_configuration = { enabled = false }
    unused_access              = { unused_access_age = 45, exclusion_resource_tags = [{ break-glass = "true" }] }
    internal_access            = { enabled = true, inclusions = [{ resource_types = ["AWS::S3::Bucket"] }] }
    archive_rules = {
      TrustedAudit = { analyzer = "external", filters = [{ criteria = "isPublic", eq = ["false"] }] }
      ServiceRoles = { analyzer = "unused", filters = [{ criteria = "resource", contains = ["aws-service-role"] }] }
    }
  }

  assert {
    condition     = keys(aws_accessanalyzer_analyzer.external) == ["eu-west-1", "us-east-1"] && alltrue([for a in values(aws_accessanalyzer_analyzer.external) : a.type == "ACCOUNT"])
    error_message = "Account-only mode creates an ACCOUNT external analyzer in each Region."
  }

  assert {
    condition     = aws_accessanalyzer_analyzer.unused[0].type == "ACCOUNT_UNUSED_ACCESS" && aws_accessanalyzer_analyzer.unused[0].configuration[0].unused_access[0].unused_access_age == 45 && length(aws_accessanalyzer_analyzer.unused[0].configuration[0].unused_access[0].analysis_rule[0].exclusion) == 1
    error_message = "The ACCOUNT_UNUSED_ACCESS analyzer keeps the tracking period and tag exclusions."
  }

  assert {
    condition     = aws_accessanalyzer_analyzer.internal[0].type == "ACCOUNT_INTERNAL_ACCESS" && aws_accessanalyzer_analyzer.internal[0].configuration[0].internal_access[0].analysis_rule[0].inclusion[0].resource_types == tolist(["AWS::S3::Bucket"])
    error_message = "The ACCOUNT_INTERNAL_ACCESS analyzer keeps its inclusions."
  }

  assert {
    condition     = keys(aws_accessanalyzer_archive_rule.this) == ["ServiceRoles/eu-west-1", "TrustedAudit/eu-west-1", "TrustedAudit/us-east-1"] && length(aws_organizations_aws_service_access.this) + length(aws_organizations_delegated_administrator.this) == 0
    error_message = "Archive rules work in account-only mode, with no organization resources."
  }
}

run "account_only_mode_outputs" {
  command   = apply
  state_key = "account_only"

  variables {
    organization_configuration = { enabled = false }
    archive_rules = {
      TrustedAudit = { analyzer = "external", filters = [{ criteria = "isPublic", eq = ["false"] }] }
    }
  }

  assert {
    condition     = output.external_analyzer_arns == { "eu-west-1" = "arn:aws:access-analyzer:eu-west-1:123456789012:analyzer/platform-prod-external" } && output.unused_access_analyzer_arn != null
    error_message = "Account analyzer ARNs are exported."
  }

  assert {
    condition     = aws_accessanalyzer_archive_rule.this["TrustedAudit/eu-west-1"].analyzer_name == "platform-prod-external" && output.analyzer_names == { external = "platform-prod-external", unused = "platform-prod-unused" }
    error_message = "Archive rules target the account analyzer."
  }
}

run "management_account_call" {
  command = plan

  variables {
    organization_admin = { enabled = true, account_id = "210987654321" }
    analyzers          = { enabled = false }
  }

  assert {
    condition     = aws_organizations_aws_service_access.this[0].service_principal == "access-analyzer.amazonaws.com" && aws_organizations_delegated_administrator.this[0].account_id == "210987654321" && aws_organizations_delegated_administrator.this[0].service_principal == "access-analyzer.amazonaws.com"
    error_message = "The management call enables trusted access and registers the administrator."
  }

  assert {
    condition     = length(aws_accessanalyzer_analyzer.external) + length(aws_accessanalyzer_analyzer.unused) + length(aws_accessanalyzer_analyzer.internal) == 0 && output.analyzer_names == {}
    error_message = "The management call creates no analyzers."
  }
}

run "management_account_call_without_trusted_access" {
  command = plan

  variables {
    organization_admin = { enabled = true, account_id = "210987654321", manage_trusted_access = false }
    analyzers          = { enabled = false }
  }

  assert {
    condition     = length(aws_organizations_aws_service_access.this) == 0 && length(aws_organizations_delegated_administrator.this) == 1
    error_message = "manage_trusted_access = false leaves trusted access alone."
  }
}

run "unused_access_exclusions_and_internal_access" {
  command = plan

  variables {
    unused_access = {
      unused_access_age       = 45
      exclusion_account_ids   = ["210987654321"]
      exclusion_resource_tags = [{ break-glass = "true" }]
    }
    internal_access = {
      enabled    = true
      region     = "us-east-1"
      inclusions = [{ resource_types = ["AWS::S3::Bucket"] }]
    }
  }

  assert {
    condition     = aws_accessanalyzer_analyzer.unused[0].configuration[0].unused_access[0].unused_access_age == 45 && length(aws_accessanalyzer_analyzer.unused[0].configuration[0].unused_access[0].analysis_rule[0].exclusion) == 2
    error_message = "Tracking period and both exclusion kinds reach the analyzer."
  }

  assert {
    condition     = aws_accessanalyzer_analyzer.internal[0].type == "ORGANIZATION_INTERNAL_ACCESS" && aws_accessanalyzer_analyzer.internal[0].region == "us-east-1" && aws_accessanalyzer_analyzer.internal[0].analyzer_name == "platform-prod-internal"
    error_message = "The internal analyzer is created in internal_access.region."
  }

  assert {
    condition     = aws_accessanalyzer_analyzer.internal[0].configuration[0].internal_access[0].analysis_rule[0].inclusion[0].resource_types == tolist(["AWS::S3::Bucket"])
    error_message = "Inclusions scope the internal analyzer."
  }
}

run "unused_access_off" {
  command = plan

  variables {
    unused_access = { enabled = false }
  }

  assert {
    condition     = length(aws_accessanalyzer_analyzer.unused) == 0 && length(aws_accessanalyzer_analyzer.external) == 1 && output.unused_access_analyzer_arn == null
    error_message = "unused_access.enabled = false drops only the unused analyzer."
  }
}

run "archive_rules" {
  command = apply

  variables {
    regions         = ["eu-west-1", "us-east-1"]
    internal_access = { enabled = true }
    archive_rules = {
      TrustedAudit = {
        analyzer = "external"
        filters = [
          { criteria = "principal.AWS", eq = ["333333333333"] },
          { criteria = "isPublic", eq = ["false"] },
        ]
      }
      UsEastOnly = {
        analyzer = "external"
        region   = "us-east-1"
        filters  = [{ criteria = "resourceType", eq = ["AWS::S3::Bucket"] }]
      }
      ServiceRoles = {
        analyzer = "unused"
        filters  = [{ criteria = "resource", contains = ["aws-service-role"] }]
      }
      Internal = {
        analyzer = "internal"
        filters  = [{ criteria = "resourceOwnerAccount", exists = true }]
      }
    }
  }

  assert {
    condition     = keys(aws_accessanalyzer_archive_rule.this) == ["Internal/eu-west-1", "ServiceRoles/eu-west-1", "TrustedAudit/eu-west-1", "TrustedAudit/us-east-1", "UsEastOnly/us-east-1"]
    error_message = "External rules land on every external analyzer unless a Region is set."
  }

  assert {
    condition     = aws_accessanalyzer_archive_rule.this["TrustedAudit/us-east-1"].analyzer_name == "platform-prod-external" && aws_accessanalyzer_archive_rule.this["TrustedAudit/us-east-1"].region == "us-east-1" && aws_accessanalyzer_archive_rule.this["ServiceRoles/eu-west-1"].analyzer_name == "platform-prod-unused"
    error_message = "Rules target the analyzer of their kind."
  }

  assert {
    condition     = one([for f in aws_accessanalyzer_archive_rule.this["Internal/eu-west-1"].filter : f.exists]) == "true"
    error_message = "exists is passed as a string."
  }

  assert {
    condition     = keys(output.external_analyzer_arns) == ["eu-west-1", "us-east-1"] && output.unused_access_analyzer_arn == "arn:aws:access-analyzer:eu-west-1:123456789012:analyzer/platform-prod-external" && output.internal_access_analyzer_arn != null
    error_message = "Analyzer ARNs are exported."
  }
}

run "names_and_governance_tags_win" {
  command   = plan
  state_key = "naming"

  variables {
    application = "observability-platform"
    environment = "production"
    tags        = { Application = "spoofed", Owner = "secops" }
  }

  assert {
    condition     = aws_accessanalyzer_analyzer.external["eu-west-1"].analyzer_name == "observability-platform-production-external"
    error_message = "Analyzer names come from core/naming."
  }

  assert {
    condition     = aws_accessanalyzer_analyzer.external["eu-west-1"].tags["Application"] == "observability-platform" && aws_accessanalyzer_analyzer.external["eu-west-1"].tags["Owner"] == "secops"
    error_message = "Governance tags win over caller tags."
  }
}

run "rejects_invalid_application" {
  command = plan

  variables {
    application = "Platform"
  }

  expect_failures = [var.application]
}

run "rejects_invalid_environment" {
  command = plan

  variables {
    environment = "p"
  }

  expect_failures = [var.environment]
}

run "rejects_invalid_region" {
  command = plan

  variables {
    regions = ["EU-WEST-1"]
  }

  expect_failures = [var.regions]
}

run "rejects_malformed_admin_account" {
  command = plan

  variables {
    organization_admin = { enabled = true, account_id = "abc" }
    analyzers          = { enabled = false }
  }

  expect_failures = [var.organization_admin]
}

run "rejects_admin_with_analyzers" {
  command = plan

  variables {
    organization_admin = { enabled = true, account_id = "210987654321" }
  }

  expect_failures = [var.organization_admin]
}

run "rejects_management_account_as_admin" {
  command = plan

  variables {
    organization_admin = { enabled = true, account_id = "123456789012" }
    analyzers          = { enabled = false }
  }

  expect_failures = [aws_organizations_delegated_administrator.this]
}

run "rejects_invalid_unused_access_age" {
  command = plan

  variables {
    unused_access = { unused_access_age = 400 }
  }

  expect_failures = [var.unused_access]
}

run "rejects_owner_in_exclusions" {
  command = plan

  variables {
    unused_access = { exclusion_account_ids = ["123456789012"] }
  }

  expect_failures = [aws_accessanalyzer_analyzer.unused]
}

run "rejects_exclusion_account_ids_in_account_mode" {
  command = plan

  variables {
    organization_configuration = { enabled = false }
    unused_access              = { exclusion_account_ids = ["210987654321"] }
  }

  expect_failures = [var.unused_access]
}

run "rejects_inclusion_account_ids_in_account_mode" {
  command = plan

  variables {
    organization_configuration = { enabled = false }
    internal_access            = { enabled = true, inclusions = [{ account_ids = ["210987654321"] }] }
  }

  expect_failures = [var.internal_access]
}

run "rejects_invalid_archive_rule_name" {
  command = plan

  variables {
    archive_rules = {
      "1rule" = { analyzer = "external", filters = [{ criteria = "isPublic", eq = ["false"] }] }
    }
  }

  expect_failures = [var.archive_rules]
}

run "rejects_unknown_analyzer_kind" {
  command = plan

  variables {
    archive_rules = {
      Rule = { analyzer = "public", filters = [{ criteria = "isPublic", eq = ["false"] }] }
    }
  }

  expect_failures = [var.archive_rules]
}

run "rejects_filter_without_comparator" {
  command = plan

  variables {
    archive_rules = {
      Rule = { analyzer = "external", filters = [{ criteria = "isPublic" }] }
    }
  }

  expect_failures = [var.archive_rules]
}

run "rejects_too_many_values" {
  command = plan

  variables {
    archive_rules = {
      Rule = { analyzer = "external", filters = [{ criteria = "principal.AWS", eq = [for i in range(21) : format("1111111111%02d", i)] }] }
    }
  }

  expect_failures = [var.archive_rules]
}

run "rejects_rule_for_missing_analyzer" {
  command = plan

  variables {
    archive_rules = {
      Rule = { analyzer = "internal", filters = [{ criteria = "isPublic", eq = ["false"] }] }
    }
  }

  expect_failures = [var.archive_rules]
}

run "rejects_rule_region_without_analyzer" {
  command = plan

  variables {
    archive_rules = {
      Rule = { analyzer = "external", region = "us-west-2", filters = [{ criteria = "isPublic", eq = ["false"] }] }
    }
  }

  expect_failures = [aws_accessanalyzer_archive_rule.this]
}
