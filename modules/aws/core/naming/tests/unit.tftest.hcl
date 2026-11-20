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

variables {
  application = "core"
  environment = "prod"
  name        = "orders"
  tags = {
    Team = "payments"
    Name = "caller-name"
  }
  names = {
    function = {}
    role     = { suffix = "exec", uniqueness = "account" }
    bucket   = { suffix = "assets", uniqueness = "global", max_length = 63 }
    lb       = { suffix = "public-load-balancer", max_length = 32 }
  }
}

run "derives_names_per_namespace" {
  command = plan

  assert {
    condition     = output.name == "core-prod-orders"
    error_message = "The base name must be <application>-<environment>-<name>."
  }

  assert {
    condition     = output.names.function == "core-prod-orders"
    error_message = "A region-scoped name without a suffix is the base name."
  }

  assert {
    condition     = output.names.role == "core-prod-orders-exec-eu-west-1"
    error_message = "Account-global names must end with the Region."
  }

  assert {
    condition     = output.names.bucket == "core-prod-orders-assets-123456789012-eu-west-1"
    error_message = "Global names must end with the account ID and Region."
  }
}

run "truncates_with_a_hash_of_the_full_name" {
  command = plan

  assert {
    condition     = length(output.names.lb) == 32
    error_message = "The load balancer name must be cut to its 32-character limit."
  }

  assert {
    condition     = output.names.lb == "core-prod-orders-public-l-${substr(md5("core-prod-orders-public-load-balancer"), 0, 6)}"
    error_message = "A truncated name must keep the prefix and end with 6 hex characters of the MD5 of the full name."
  }
}

run "different_long_names_stay_distinct" {
  command = plan

  variables {
    names = {
      a = { suffix = "reconciliation-worker-blue", max_length = 32 }
      b = { suffix = "reconciliation-worker-green", max_length = 32 }
    }
  }

  assert {
    condition     = output.names.a != output.names.b && length(output.names.a) <= 32 && length(output.names.b) <= 32
    error_message = "Two long names with a shared prefix must not collide after truncation."
  }
}

run "omits_an_empty_instance_name" {
  command = plan

  variables {
    name  = null
    names = { cluster = {} }
  }

  assert {
    condition     = output.name == "core-prod" && output.names.cluster == "core-prod"
    error_message = "Without a name the base is <application>-<environment>."
  }
}

run "uses_an_explicit_region" {
  command = plan

  variables {
    region = "us-east-1"
  }

  assert {
    condition     = output.region == "us-east-1" && output.names.role == "core-prod-orders-exec-us-east-1"
    error_message = "An explicit Region must be used in account-global names."
  }
}

run "governance_tags_win" {
  command = plan

  assert {
    condition     = output.tags["Name"] == "core-prod-orders" && output.tags["Team"] == "payments" && output.tags["ManagedBy"] == "Terraform" && output.tags["Application"] == "core" && output.tags["Environment"] == "prod"
    error_message = "Caller tags must be kept and governance tags must win."
  }
}

run "rejects_invalid_application" {
  command = plan

  variables {
    application = "Core_App"
  }

  expect_failures = [var.application]
}

run "rejects_invalid_environment" {
  command = plan

  variables {
    environment = "production-eu-west"
  }

  expect_failures = [var.environment]
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Orders"
  }

  expect_failures = [var.name]
}

run "rejects_unknown_uniqueness" {
  command = plan

  variables {
    names = { x = { uniqueness = "planet" } }
  }

  expect_failures = [var.names]
}

run "rejects_short_max_length" {
  command = plan

  variables {
    names = { x = { max_length = 8 } }
  }

  expect_failures = [var.names]
}

run "rejects_invalid_suffix" {
  command = plan

  variables {
    names = { x = { suffix = "Bad_Suffix" } }
  }

  expect_failures = [var.names]
}
