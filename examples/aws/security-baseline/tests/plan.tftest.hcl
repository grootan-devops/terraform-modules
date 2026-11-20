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

  mock_data "aws_availability_zones" {
    defaults = {
      names    = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
      zone_ids = ["euw1-az1", "euw1-az2", "euw1-az3"]
    }
  }

  mock_data "aws_organizations_organization" {
    defaults = {
      id                            = "o-abcdef1234"
      master_account_id             = "123456789012"
      feature_set                   = "ALL"
      aws_service_access_principals = []
      enabled_policy_types          = ["SERVICE_CONTROL_POLICY"]
      roots = [{
        arn          = "arn:aws:organizations::123456789012:root/o-abcdef1234/r-abcd"
        id           = "r-abcd"
        name         = "Root"
        policy_types = [{ status = "ENABLED", type = "SERVICE_CONTROL_POLICY" }]
      }]
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }
}

run "plans_the_baseline" {
  command = plan

  assert {
    condition     = output.trail_bucket == "platform-prod-cloudtrail-123456789012-eu-west-1" && output.config_bucket == "platform-prod-config-123456789012-eu-west-1"
    error_message = "Account module buckets carry the account and Region."
  }

  assert {
    condition     = output.budget_names["account"] == "platform-prod-account"
    error_message = "Account budgets alert through the alarm-routing topic."
  }
}
