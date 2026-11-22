mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:sts::123456789012:assumed-role/terraform-deployer/plan"
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

  mock_data "aws_iam_session_context" {
    defaults = {
      issuer_arn  = "arn:aws:iam::123456789012:role/terraform-deployer"
      issuer_name = "terraform-deployer"
    }
  }

  mock_data "aws_ssoadmin_instances" {
    defaults = {
      arns               = ["arn:aws:sso:::instance/ssoins-1111111111111111"]
      identity_store_ids = ["d-1111111111"]
    }
  }

  mock_data "aws_ssm_patch_baselines" {
    defaults = {
      baseline_identities = [
        {
          baseline_id          = "arn:aws:ssm:eu-west-1:080255945899:patchbaseline/pb-0b8d4f5a6e3c2a1d7"
          baseline_name        = "AWS-AmazonLinux2023DefaultPatchBaseline"
          baseline_description = "Default Patch Baseline for Amazon Linux 2023 Provided by AWS."
          default_baseline     = true
          operating_system     = "AMAZON_LINUX_2023"
        }
      ]
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

  assert {
    condition     = toset(keys(module.detective.graph_arns)) == toset(var.regions) && keys(module.access_analyzer.analyzer_names) == ["external", "unused"]
    error_message = "Detective graphs and access analyzers cover every Region of the account."
  }

  assert {
    condition     = output.backup_vault_name == "platform-prod" && output.backup_role_name == "platform-prod-backup-eu-west-1"
    error_message = "The backup vault and its role follow the naming standard."
  }

  assert {
    condition     = toset(keys(module.systems_manager.session_log_group_names)) == toset(var.regions) && length(distinct(values(module.systems_manager.session_log_group_names))) == 1
    error_message = "Session logs land in one log group name in every Region."
  }

  assert {
    condition     = jsondecode(module.backup_guardrail.json).Statement[0].Condition.ArnNotLike["aws:PrincipalArn"] == ["arn:aws:iam::*:role/terraform-deployer"]
    error_message = "The backup guardrail exempts the deployer role, the vault admin, in every member account."
  }

  assert {
    condition     = output.scp_names["protect-backups"] == "platform-prod-protect-backups" && keys(module.identity_center.permission_set_arns) == ["admin", "audit"]
    error_message = "The backup guardrail is a named custom SCP; Identity Center has two permission sets."
  }
}
