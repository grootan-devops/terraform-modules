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
    condition     = output.role_names == ["shop-prod-orders-exec-eu-west-1", "shop-prod-orders-exec-us-east-1"]
    error_message = "Account-global IAM role names must differ by Region."
  }

  assert {
    condition     = output.bucket_names == ["shop-prod-assets-123456789012-eu-west-1", "shop-prod-assets-123456789012-us-east-1"]
    error_message = "Globally named buckets must differ by Region."
  }
}
