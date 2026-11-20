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
    condition     = output.alb_name == "shop-dev" && output.log_bucket == "shop-dev-logs-123456789012-eu-west-1"
    error_message = "One-per-environment modules use the base name; buckets carry the account and Region."
  }

  assert {
    condition     = output.nlb_name == "shop-dev-partners-nlb" && output.nlb_name != output.alb_name
    error_message = "The NLB never shares a name with the ALB."
  }

  assert {
    condition     = contains(keys(module.alb.alarm_names), "alb-lb-web-unhealthy-hosts") && contains(keys(module.private_link.alarm_names), "nlb-lb-alb-no-healthy-hosts") && contains(keys(module.db.alarm_names), "rds-instance-free-storage") && contains(keys(module.app.alarm_names), "ecs-web-running-tasks")
    error_message = "Load balancers, database and service get their built-in alarms, routed without hand wiring."
  }

  assert {
    condition     = length([for k in keys(module.vpc.alarm_names) : k if startswith(k, "nat-")]) == 2
    error_message = "The single NAT gateway gets its port allocation and packet drop alarms."
  }
}
