mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_resource "aws_detective_graph" {
    defaults = {
      graph_arn = "arn:aws:detective:us-east-1:123456789012:graph:027c7c4610ea4aacaf0b883093cab899"
    }
  }

  mock_resource "aws_detective_member" {
    defaults = {
      id     = "arn:aws:detective:us-east-1:123456789012:graph:027c7c4610ea4aacaf0b883093cab899/210987654321"
      status = "ENABLED"
    }
  }
}

variables {
  environment = "prod"
  tags        = { Team = "security" }
}

run "nothing_by_default" {
  command = plan

  assert {
    condition     = length(aws_detective_organization_admin_account.this) + length(aws_detective_graph.this) + length(aws_detective_organization_configuration.this) + length(aws_detective_member.this) == 0
    error_message = "Without a switch the module creates nothing."
  }

  assert {
    condition     = output.graph_arns == {} && output.member_ids == {}
    error_message = "Outputs are empty without a graph."
  }
}

run "behavior_graph_defaults" {
  command = plan

  variables {
    behavior_graph = { enabled = true }
  }

  assert {
    condition     = keys(aws_detective_graph.this) == ["us-east-1"] && aws_detective_graph.this["us-east-1"].region == "us-east-1"
    error_message = "One behavior graph in the provider Region."
  }

  assert {
    condition     = aws_detective_organization_configuration.this["us-east-1"].auto_enable && aws_detective_organization_configuration.this["us-east-1"].region == "us-east-1"
    error_message = "New organization accounts are enabled automatically."
  }

  assert {
    condition     = aws_detective_graph.this["us-east-1"].tags["Name"] == "platform-prod" && aws_detective_graph.this["us-east-1"].tags["Application"] == "platform" && aws_detective_graph.this["us-east-1"].tags["Team"] == "security" && aws_detective_graph.this["us-east-1"].tags["ManagedBy"] == "Terraform"
    error_message = "Graphs carry caller and governance tags; application defaults to platform."
  }

  assert {
    condition     = length(aws_detective_organization_admin_account.this) + length(aws_detective_member.this) == 0
    error_message = "No designation and no members by default."
  }
}

run "governance_tags_win" {
  command = plan

  variables {
    behavior_graph = { enabled = true }
    tags           = { Environment = "sandbox", Owner = "secops" }
  }

  assert {
    condition     = aws_detective_graph.this["us-east-1"].tags["Environment"] == "prod" && aws_detective_graph.this["us-east-1"].tags["Owner"] == "secops"
    error_message = "Governance tags override caller tags."
  }
}

run "members_in_every_region" {
  command = apply

  variables {
    regions = ["us-east-1", "eu-west-1", "eu-west-1"]
    behavior_graph = {
      enabled         = true
      member_accounts = { "210987654321" = "security@example.com", "111122223333" = "logs@example.com" }
    }
    organization_configuration = { auto_enable = false }
  }

  assert {
    condition     = toset(keys(aws_detective_graph.this)) == toset(["us-east-1", "eu-west-1"]) && !aws_detective_organization_configuration.this["eu-west-1"].auto_enable
    error_message = "One graph and configuration per distinct Region."
  }

  assert {
    condition     = length(aws_detective_member.this) == 4 && aws_detective_member.this["210987654321/eu-west-1"].region == "eu-west-1" && aws_detective_member.this["210987654321/eu-west-1"].email_address == "security@example.com"
    error_message = "Every member is enabled in every Region."
  }

  assert {
    condition     = aws_detective_member.this["111122223333/us-east-1"].graph_arn == "arn:aws:detective:us-east-1:123456789012:graph:027c7c4610ea4aacaf0b883093cab899" && output.graph_arns["us-east-1"] == aws_detective_member.this["111122223333/us-east-1"].graph_arn
    error_message = "Members join the graph of their Region."
  }

  assert {
    condition     = output.member_statuses["210987654321/us-east-1"] == "ENABLED" && length(output.member_ids) == 4
    error_message = "Member IDs and statuses are output by account and Region."
  }
}

run "account_only_mode" {
  command   = plan
  state_key = "account_only"

  variables {
    regions                    = ["us-east-1", "eu-west-1"]
    behavior_graph             = { enabled = true, member_accounts = { "210987654321" = "security@example.com" } }
    organization_configuration = { enabled = false }
  }

  assert {
    condition     = toset(keys(aws_detective_graph.this)) == toset(["us-east-1", "eu-west-1"]) && aws_detective_graph.this["eu-west-1"].region == "eu-west-1"
    error_message = "Account-only mode keeps a graph in each Region."
  }

  assert {
    condition     = length(aws_detective_organization_configuration.this) + length(aws_detective_organization_admin_account.this) == 0
    error_message = "Account-only mode creates no organization configuration."
  }

  assert {
    condition     = keys(aws_detective_member.this) == ["210987654321/eu-west-1", "210987654321/us-east-1"]
    error_message = "Members plan while the graph ARN is unknown."
  }
}

run "account_only_mode_graph_arns" {
  command   = apply
  state_key = "account_only"

  variables {
    behavior_graph             = { enabled = true }
    organization_configuration = { enabled = false }
  }

  assert {
    condition     = output.graph_arns == { "us-east-1" = "arn:aws:detective:us-east-1:123456789012:graph:027c7c4610ea4aacaf0b883093cab899" } && length(aws_detective_organization_configuration.this) == 0
    error_message = "The account's own graph ARN is output."
  }
}

run "management_account_call" {
  command   = plan
  state_key = "management"

  variables {
    regions            = ["us-east-1", "eu-west-1"]
    organization_admin = { enabled = true, account_id = "210987654321" }
  }

  assert {
    condition     = toset(keys(aws_detective_organization_admin_account.this)) == toset(["us-east-1", "eu-west-1"]) && alltrue([for a in values(aws_detective_organization_admin_account.this) : a.account_id == "210987654321"])
    error_message = "The same administrator is designated in every Region."
  }

  assert {
    condition     = length(aws_detective_graph.this) + length(aws_detective_member.this) == 0
    error_message = "The management account call creates no graph."
  }
}

run "rejects_application" {
  command = plan

  variables {
    application = "1platform"
  }

  expect_failures = [var.application]
}

run "rejects_environment" {
  command = plan

  variables {
    environment = "Prod"
  }

  expect_failures = [var.environment]
}

run "rejects_region" {
  command = plan

  variables {
    regions = ["US-EAST-1"]
  }

  expect_failures = [var.regions]
}

run "rejects_member_account_id" {
  command = plan

  variables {
    behavior_graph = { enabled = true, member_accounts = { "21098765432" = "security@example.com" } }
  }

  expect_failures = [var.behavior_graph]
}

run "rejects_member_email" {
  command = plan

  variables {
    behavior_graph = { enabled = true, member_accounts = { "210987654321" = "not-an-email" } }
  }

  expect_failures = [var.behavior_graph]
}

run "rejects_members_without_graph" {
  command = plan

  variables {
    behavior_graph = { member_accounts = { "210987654321" = "security@example.com" } }
  }

  expect_failures = [var.behavior_graph]
}

run "rejects_organization_admin_account_id" {
  command = plan

  variables {
    organization_admin = { enabled = true, account_id = "abc" }
  }

  expect_failures = [var.organization_admin]
}

run "rejects_organization_admin_with_graph" {
  command = plan

  variables {
    behavior_graph     = { enabled = true }
    organization_admin = { enabled = true, account_id = "210987654321" }
  }

  expect_failures = [var.organization_admin]
}

run "rejects_management_account_as_administrator" {
  command = plan

  variables {
    organization_admin = { enabled = true, account_id = "123456789012" }
  }

  expect_failures = [aws_detective_organization_admin_account.this]
}

run "rejects_administrator_as_member" {
  command = plan

  variables {
    behavior_graph = { enabled = true, member_accounts = { "123456789012" = "admin@example.com" } }
  }

  expect_failures = [aws_detective_member.this]
}
