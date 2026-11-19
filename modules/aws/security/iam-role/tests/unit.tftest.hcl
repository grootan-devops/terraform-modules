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
  purpose     = "exec"
  trust = {
    services   = ["lambda.amazonaws.com"]
    conditions = [{ test = "StringEquals", variable = "aws:SourceAccount", values = ["123456789012"] }]
  }
  tags = { Team = "payments" }
}

run "names_the_role_per_region" {
  command = plan

  assert {
    condition     = aws_iam_role.this.name == "core-prod-orders-exec-eu-west-1" && aws_iam_role.this.path == "/"
    error_message = "The role name must be <application>-<environment>-<name>-<purpose>-<region>."
  }

  assert {
    condition     = aws_iam_role.this.tags["Name"] == "core-prod-orders-exec-eu-west-1" && aws_iam_role.this.tags["Team"] == "payments" && aws_iam_role.this.tags["ManagedBy"] == "Terraform"
    error_message = "The role must carry caller and governance tags with Name set to the role name."
  }

  assert {
    condition     = aws_iam_role.this.max_session_duration == 3600 && aws_iam_role.this.permissions_boundary == null
    error_message = "Defaults: one-hour sessions, no permissions boundary."
  }
}

run "renders_the_trust_policy" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Principal == { Service = ["lambda.amazonaws.com"] } && jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Action == ["sts:AssumeRole"]
    error_message = "The trust policy must name the service and sts:AssumeRole."
  }

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == ["123456789012"] && !can(jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Resource)
    error_message = "Trust conditions must be rendered and the trust policy must have no Resource."
  }

  assert {
    condition     = length(aws_iam_role_policy.this) == 0 && length(aws_iam_role_policy_attachment.this) == 0 && length(aws_iam_instance_profile.this) == 0
    error_message = "No inline policy, attachment or instance profile without input."
  }
}

run "extends_the_role" {
  command = plan

  variables {
    managed_policy_arns      = ["arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"]
    permissions_boundary_arn = "arn:aws:iam::123456789012:policy/boundary"
    policy_statements = [{
      sid       = "ReadQueue"
      actions   = ["sqs:ReceiveMessage"]
      resources = ["arn:aws:sqs:eu-west-1:123456789012:core-prod-orders"]
    }]
    policy_documents = [jsonencode({ Version = "2012-10-17", Statement = [{ Sid = "Logs", Effect = "Allow", Action = ["logs:PutLogEvents"], Resource = ["*"] }] })]
    instance_profile = { enabled = true }
  }

  assert {
    condition     = aws_iam_role_policy.this[0].name == "inline" && length(jsondecode(aws_iam_role_policy.this[0].policy).Statement) == 2 && jsondecode(aws_iam_role_policy.this[0].policy).Statement[0].Sid == "Logs"
    error_message = "Policy documents and statements must merge into one inline policy, documents first."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.this["0"].policy_arn == "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess" && aws_iam_role.this.permissions_boundary == "arn:aws:iam::123456789012:policy/boundary"
    error_message = "Managed policies and the permissions boundary must be applied."
  }

  assert {
    condition     = aws_iam_instance_profile.this[0].name == "core-prod-orders-exec-eu-west-1"
    error_message = "The instance profile must share the role name."
  }

  assert {
    condition     = aws_iam_role_policies_exclusive.this.policy_names == toset(["inline"]) && aws_iam_role_policy_attachments_exclusive.this.policy_arns == toset(["arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"])
    error_message = "Inline policies and attachments are exclusive."
  }
}

run "exclusive_without_policies" {
  command = plan

  assert {
    condition     = length(aws_iam_role_policies_exclusive.this.policy_names) == 0 && length(aws_iam_role_policy_attachments_exclusive.this.policy_arns) == 0
    error_message = "A role without policies keeps none."
  }
}

run "exact_name_and_global_role" {
  command = plan

  variables {
    role_name = "github-deploy"
  }

  assert {
    condition     = aws_iam_role.this.name == "github-deploy"
    error_message = "role_name must override the derived name."
  }
}

run "role_without_region_suffix" {
  command = plan

  variables {
    include_region_in_name = false
  }

  assert {
    condition     = aws_iam_role.this.name == "core-prod-orders-exec"
    error_message = "include_region_in_name = false must drop the Region."
  }
}

run "pod_identity_trust" {
  command = plan

  variables {
    trust = {
      services = ["pods.eks.amazonaws.com"]
      actions  = ["sts:AssumeRole", "sts:TagSession"]
    }
  }

  assert {
    condition     = jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Action == ["sts:AssumeRole", "sts:TagSession"] && !can(jsondecode(aws_iam_role.this.assume_role_policy).Statement[0].Condition)
    error_message = "Custom trust actions must be rendered; no Condition without conditions."
  }
}

run "rejects_empty_trust" {
  command = plan

  variables {
    trust = {}
  }

  expect_failures = [var.trust]
}

run "rejects_wildcard_trust" {
  command = plan

  variables {
    trust = { aws_principals = ["*"] }
  }

  expect_failures = [var.trust]
}

run "rejects_statement_with_principals" {
  command = plan

  variables {
    policy_statements = [{ actions = ["s3:GetObject"], resources = ["*"], principals = { AWS = ["arn:aws:iam::123456789012:root"] } }]
  }

  expect_failures = [var.policy_statements]
}

run "rejects_full_admin_statement" {
  command = plan

  variables {
    policy_statements = [{ actions = ["*"], resources = ["*"] }]
  }

  expect_failures = [var.policy_statements]
}

run "rejects_no_name_parts" {
  command = plan

  variables {
    name    = null
    purpose = null
  }

  expect_failures = [var.purpose]
}

run "rejects_invalid_role_name" {
  command = plan

  variables {
    role_name = "role with spaces"
  }

  expect_failures = [var.role_name]
}

run "rejects_invalid_path" {
  command = plan

  variables {
    path = "service-role"
  }

  expect_failures = [var.path]
}

run "rejects_long_session" {
  command = plan

  variables {
    max_session_duration = 86400
  }

  expect_failures = [var.max_session_duration]
}

run "rejects_invalid_purpose" {
  command = plan

  variables {
    purpose = "Exec Role"
  }

  expect_failures = [var.purpose]
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

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Orders"
  }

  expect_failures = [var.name]
}
