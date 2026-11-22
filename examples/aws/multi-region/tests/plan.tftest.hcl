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
}

mock_provider "aws" {
  alias = "us_east_1"

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
}

mock_provider "archive" {
  mock_data "archive_file" {
    defaults = {
      output_path = "placeholder.zip"
    }
  }
}

run "same_names_in_two_regions_do_not_collide" {
  command = plan

  assert {
    condition     = output.function_names == ["shop-prod-orders", "shop-prod-orders"]
    error_message = "Regional resources keep the same name in each Region."
  }

  assert {
    condition     = output.role_names == ["shop-prod-orders-lambda-eu-west-1", "shop-prod-orders-lambda-us-east-1"]
    error_message = "Account-global IAM role names must differ by Region."
  }

  assert {
    condition     = output.bucket_names == ["shop-prod-assets-123456789012-eu-west-1", "shop-prod-assets-123456789012-us-east-1"]
    error_message = "Globally named buckets must differ by Region."
  }
}

run "alarms_route_to_their_own_region" {
  command = plan

  assert {
    condition     = module.fn_eu.alarm_names == module.fn_us.alarm_names && length(module.fn_eu.alarm_names) == 3
    error_message = "Alarm names repeat across Regions; alarms are regional, so they do not collide."
  }

  assert {
    condition     = sort(keys(module.alarm_routing.topic_arns)) == tolist(["eu-west-1", "us-east-1"])
    error_message = "alarm-routing creates topics in both Regions, one map per Region for the modules there."
  }
}

