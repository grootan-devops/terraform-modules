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

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }
}

run "plans_with_unknown_ids" {
  command = plan

  assert {
    condition     = output.cluster_name == "shop-dev" && output.repository_name == "shop-dev-web" && output.assets_bucket == "shop-dev-assets-123456789012-eu-west-1"
    error_message = "Names must follow the standard per namespace."
  }

  assert {
    condition     = sort(keys(module.cluster.alarm_names)) == tolist(["asg-general-cpu", "asg-general-status-check-failed"])
    error_message = "Node groups get their alarms by default; cluster alarms wait for Container Insights."
  }

  assert {
    condition     = length(module.vpc.alarm_names) == 6 && length(module.assets.alarm_names) == 0
    error_message = "One NAT gateway per AZ gets two alarms each; the bucket size alarm needs a threshold."
  }
}
