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
  purpose     = "db"
  vpc_id      = "vpc-0a1b2c3d4e5f67890"
  ingress_rules = {
    app = { description = "PostgreSQL from the app", from_port = 5432, to_port = 5432, referenced_security_group_id = "sg-0123456789abcdef0" }
    vpc = { description = "PostgreSQL from the VPC", from_port = 5432, to_port = 5432, cidr_ipv4 = "10.0.0.0/16" }
  }
}

run "creates_group_and_rules" {
  command = plan

  assert {
    condition     = aws_security_group.this.name_prefix == "core-prod-orders-db-" && aws_security_group.this.tags["Name"] == "core-prod-orders-db" && aws_security_group.this.description == "core-prod-orders-db security group"
    error_message = "The group must be named <application>-<environment>-<name>-<purpose>."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["app"].referenced_security_group_id == "sg-0123456789abcdef0" && aws_vpc_security_group_ingress_rule.this["vpc"].cidr_ipv4 == "10.0.0.0/16" && aws_vpc_security_group_ingress_rule.this["vpc"].from_port == 5432
    error_message = "Each ingress rule must be a separate rule resource with its source."
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.this) == 0
    error_message = "No egress rule by default."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["app"].tags["Name"] == "core-prod-orders-db-app" && aws_vpc_security_group_ingress_rule.this["app"].tags["ManagedBy"] == "Terraform"
    error_message = "Rules must be tagged."
  }
}

run "exclusive_rules" {
  command = apply

  variables {
    ingress_rules = {
      app  = { description = "PostgreSQL from the app", from_port = 5432, to_port = 5432, referenced_security_group_id = "sg-0123456789abcdef0" }
      peer = { description = "PostgreSQL between members", from_port = 5432, to_port = 5432, self = true }
    }
    egress_rules = {
      vpc = { description = "Outbound to the VPC", ip_protocol = "-1", cidr_ipv4 = "10.0.0.0/16" }
    }
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["peer"].referenced_security_group_id == aws_security_group.this.id
    error_message = "self references the group itself."
  }

  assert {
    condition     = aws_vpc_security_group_rules_exclusive.this.security_group_id == aws_security_group.this.id && aws_vpc_security_group_rules_exclusive.this.ingress_rule_ids == toset(values(output.ingress_rule_ids)) && aws_vpc_security_group_rules_exclusive.this.egress_rule_ids == toset(values(output.egress_rule_ids))
    error_message = "The module's rules are the group's only rules."
  }
}

run "rejects_self_with_source" {
  command = plan

  variables {
    ingress_rules = {
      bad = { description = "Two sources", from_port = 5432, to_port = 5432, cidr_ipv4 = "10.0.0.0/16", self = true }
    }
  }

  expect_failures = [var.ingress_rules]
}

run "all_traffic_egress" {
  command = plan

  variables {
    egress_rules = {
      all = { description = "All traffic to the VPC", ip_protocol = "-1", cidr_ipv4 = "10.0.0.0/16" }
    }
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.this["all"].ip_protocol == "-1" && aws_vpc_security_group_egress_rule.this["all"].from_port == null
    error_message = "Protocol -1 rules must not set ports."
  }
}

run "public_ingress_when_allowed" {
  command = plan

  variables {
    allow_public_ingress = true
    ingress_rules = {
      https = { description = "HTTPS from the internet", from_port = 443, to_port = 443, cidr_ipv4 = "0.0.0.0/0" }
    }
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.this["https"].cidr_ipv4 == "0.0.0.0/0"
    error_message = "allow_public_ingress must allow 0.0.0.0/0."
  }
}

run "rejects_public_ingress" {
  command = plan

  variables {
    ingress_rules = {
      ssh = { description = "SSH", from_port = 22, to_port = 22, cidr_ipv4 = "0.0.0.0/0" }
    }
  }

  expect_failures = [var.ingress_rules]
}

run "rejects_two_sources" {
  command = plan

  variables {
    ingress_rules = {
      x = { description = "x", from_port = 1, to_port = 1, cidr_ipv4 = "10.0.0.0/8", prefix_list_id = "pl-12345678" }
    }
  }

  expect_failures = [var.ingress_rules]
}

run "rejects_bad_protocol" {
  command = plan

  variables {
    egress_rules = {
      x = { description = "x", ip_protocol = "http", from_port = 80, to_port = 80, cidr_ipv4 = "10.0.0.0/8" }
    }
  }

  expect_failures = [var.egress_rules]
}

run "rejects_missing_ports" {
  command = plan

  variables {
    egress_rules = {
      x = { description = "x", cidr_ipv4 = "10.0.0.0/8" }
    }
  }

  expect_failures = [var.egress_rules]
}

run "rejects_egress_without_destination" {
  command = plan

  variables {
    egress_rules = {
      x = { description = "x", ip_protocol = "-1" }
    }
  }

  expect_failures = [var.egress_rules]
}

run "rejects_bad_ingress_protocol" {
  command = plan

  variables {
    ingress_rules = {
      x = { description = "x", ip_protocol = "sctp", from_port = 1, to_port = 1, cidr_ipv4 = "10.0.0.0/8" }
    }
  }

  expect_failures = [var.ingress_rules]
}

run "rejects_ingress_without_ports" {
  command = plan

  variables {
    ingress_rules = {
      x = { description = "x", cidr_ipv4 = "10.0.0.0/8" }
    }
  }

  expect_failures = [var.ingress_rules]
}

run "rejects_no_name_parts" {
  command = plan

  variables {
    name    = null
    purpose = null
  }

  expect_failures = [var.purpose]
}

run "rejects_invalid_purpose" {
  command = plan

  variables {
    purpose = "DB"
  }

  expect_failures = [var.purpose]
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Orders"
  }

  expect_failures = [var.name]
}

run "rejects_invalid_application" {
  command = plan

  variables {
    application = "Core"
  }

  expect_failures = [var.application]
}

run "rejects_invalid_environment" {
  command = plan

  variables {
    environment = "PROD"
  }

  expect_failures = [var.environment]
}
