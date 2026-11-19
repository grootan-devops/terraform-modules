mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111111111111"
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

  mock_data "aws_ssoadmin_instances" {
    defaults = {
      arns               = ["arn:aws:sso:::instance/ssoins-1111111111111111"]
      identity_store_ids = ["d-1111111111"]
    }
  }

  mock_resource "aws_ssoadmin_permission_set" {
    defaults = {
      arn = "arn:aws:sso:::permissionSet/ssoins-1111111111111111/ps-1111111111111111"
    }
  }

  mock_resource "aws_identitystore_group" {
    defaults = {
      group_id = "11111111-2222-3333-4444-555555555555"
    }
  }
}

variables {
  environment = "prod"
  tags        = { Team = "identity" }
  permission_sets = {
    admin = {
      managed_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"]
      session_duration    = "PT4H"
    }
    readonly = {
      description               = "Read-only access."
      managed_policy_arns       = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
      customer_managed_policies = [{ name = "deny-secrets", path = "/platform/" }]
      policy_statements         = [{ sid = "DenyBilling", effect = "Deny", actions = ["aws-portal:*"], resources = ["*"] }]
      permissions_boundary      = { enabled = true, managed_policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess" }
    }
  }
}

run "permission_sets" {
  command = plan

  assert {
    condition     = aws_ssoadmin_permission_set.this["admin"].name == "platform-prod-admin" && aws_ssoadmin_permission_set.this["admin"].session_duration == "PT4H" && aws_ssoadmin_permission_set.this["readonly"].session_duration == "PT1H"
    error_message = "Permission sets are named <application>-<environment>-<key>; sessions default to one hour."
  }

  assert {
    condition     = aws_ssoadmin_permission_set.this["admin"].instance_arn == "arn:aws:sso:::instance/ssoins-1111111111111111" && output.instance_arn == "arn:aws:sso:::instance/ssoins-1111111111111111" && output.identity_store_id == "d-1111111111"
    error_message = "The instance is discovered."
  }

  assert {
    condition     = aws_ssoadmin_permission_set.this["admin"].description == "platform-prod-admin permission set" && aws_ssoadmin_permission_set.this["readonly"].description == "Read-only access."
    error_message = "Descriptions default to the name."
  }

  assert {
    condition     = aws_ssoadmin_permission_set.this["admin"].tags["Name"] == "platform-prod-admin" && aws_ssoadmin_permission_set.this["admin"].tags["Team"] == "identity" && aws_ssoadmin_permission_set.this["admin"].tags["ManagedBy"] == "Terraform"
    error_message = "Caller and governance tags must be applied."
  }

  assert {
    condition     = keys(aws_ssoadmin_managed_policy_attachment.this) == ["admin/arn:aws:iam::aws:policy/AdministratorAccess", "readonly/arn:aws:iam::aws:policy/ReadOnlyAccess"]
    error_message = "Managed policies attach per permission set."
  }

  assert {
    condition     = aws_ssoadmin_customer_managed_policy_attachment.this["readonly//platform/deny-secrets"].customer_managed_policy_reference[0].path == "/platform/"
    error_message = "Customer managed policies attach by name and path."
  }

  assert {
    condition     = keys(aws_ssoadmin_permission_set_inline_policy.this) == ["readonly"] && jsondecode(aws_ssoadmin_permission_set_inline_policy.this["readonly"].inline_policy).Statement[0].Effect == "Deny" && jsondecode(aws_ssoadmin_permission_set_inline_policy.this["readonly"].inline_policy).Statement[0].Sid == "DenyBilling"
    error_message = "Inline statements render through core/policy-document."
  }

  assert {
    condition     = keys(aws_ssoadmin_permissions_boundary_attachment.this) == ["readonly"] && aws_ssoadmin_permissions_boundary_attachment.this["readonly"].permissions_boundary[0].managed_policy_arn == "arn:aws:iam::aws:policy/PowerUserAccess"
    error_message = "A permissions boundary attaches only when enabled."
  }

  assert {
    condition     = length(aws_identitystore_group.this) == 0 && length(aws_ssoadmin_account_assignment.this) == 0
    error_message = "Groups and assignments are opt-in."
  }

  assert {
    condition     = aws_ssoadmin_managed_policy_attachments_exclusive.this["admin"].managed_policy_arns == toset(["arn:aws:iam::aws:policy/AdministratorAccess"]) && aws_ssoadmin_managed_policy_attachments_exclusive.this["readonly"].managed_policy_arns == toset(["arn:aws:iam::aws:policy/ReadOnlyAccess"])
    error_message = "Managed policy attachments are exclusive per permission set."
  }

  assert {
    condition     = length(aws_ssoadmin_customer_managed_policy_attachments_exclusive.this["admin"].customer_managed_policy_reference) == 0 && length(aws_ssoadmin_customer_managed_policy_attachments_exclusive.this["readonly"].customer_managed_policy_reference) == 1
    error_message = "Customer managed policy attachments are exclusive per permission set."
  }
}

run "customer_managed_boundary" {
  command = plan

  variables {
    permission_sets = {
      dev = { permissions_boundary = { enabled = true, customer_managed_policy = { name = "boundary" } } }
    }
  }

  assert {
    condition     = aws_ssoadmin_permissions_boundary_attachment.this["dev"].permissions_boundary[0].customer_managed_policy_reference[0].name == "boundary" && aws_ssoadmin_permissions_boundary_attachment.this["dev"].permissions_boundary[0].customer_managed_policy_reference[0].path == "/"
    error_message = "A customer managed boundary is referenced by name."
  }
}

run "long_names_are_truncated" {
  command = plan

  variables {
    application     = "customer-identity-portal"
    permission_sets = { break-glass-admins = {} }
  }

  assert {
    condition     = length(aws_ssoadmin_permission_set.this["break-glass-admins"].name) <= 32 && startswith(aws_ssoadmin_permission_set.this["break-glass-admins"].name, "customer-identity-portal-")
    error_message = "Permission set names are cut to 32 characters with a hash."
  }
}

run "groups_and_assignments" {
  command   = apply
  state_key = "assignments"

  variables {
    groups = {
      admins = { description = "Platform administrators.", member_ids = ["aaaaaaaa-1111-2222-3333-444444444444"] }
    }
    account_assignments = {
      admins  = { permission_set = "admin", group = "admins", account_ids = ["222222222222", "333333333333"] }
      auditor = { permission_set = "readonly", principal_type = "USER", principal_id = "bbbbbbbb-1111-2222-3333-444444444444", account_ids = ["222222222222"] }
    }
  }

  assert {
    condition     = aws_identitystore_group.this["admins"].display_name == "platform-prod-admins" && aws_identitystore_group.this["admins"].identity_store_id == "d-1111111111" && output.group_ids["admins"] == "11111111-2222-3333-4444-555555555555"
    error_message = "Groups are named and created in the discovered identity store."
  }

  assert {
    condition     = aws_identitystore_group_membership.this["admins/aaaaaaaa-1111-2222-3333-444444444444"].group_id == "11111111-2222-3333-4444-555555555555"
    error_message = "Members join the group."
  }

  assert {
    condition     = keys(aws_ssoadmin_account_assignment.this) == ["admins/222222222222", "admins/333333333333", "auditor/222222222222"]
    error_message = "One assignment per account."
  }

  assert {
    condition     = aws_ssoadmin_account_assignment.this["admins/222222222222"].principal_id == "11111111-2222-3333-4444-555555555555" && aws_ssoadmin_account_assignment.this["admins/222222222222"].principal_type == "GROUP" && aws_ssoadmin_account_assignment.this["admins/222222222222"].target_type == "AWS_ACCOUNT"
    error_message = "Group keys resolve to the created group."
  }

  assert {
    condition     = aws_ssoadmin_account_assignment.this["auditor/222222222222"].principal_id == "bbbbbbbb-1111-2222-3333-444444444444" && aws_ssoadmin_account_assignment.this["auditor/222222222222"].permission_set_arn == output.permission_set_arns["readonly"]
    error_message = "User assignments use the given principal ID."
  }
}

run "rejects_invalid_application" {
  command = plan

  variables {
    application = "Platform"
  }

  expect_failures = [var.application]
}

run "rejects_invalid_environment" {
  command = plan

  variables {
    environment = "prod_1"
  }

  expect_failures = [var.environment]
}

run "rejects_invalid_permission_set_key" {
  command = plan

  variables {
    permission_sets = { AdministratorAccess = {} }
  }

  expect_failures = [var.permission_sets]
}

run "rejects_long_session" {
  command = plan

  variables {
    permission_sets = { admin = { session_duration = "PT24H" } }
  }

  expect_failures = [var.permission_sets]
}

run "rejects_customer_policy_as_managed_arn" {
  command = plan

  variables {
    permission_sets = { admin = { managed_policy_arns = ["arn:aws:iam::111111111111:policy/admin"] } }
  }

  expect_failures = [var.permission_sets]
}

run "rejects_statement_without_resources" {
  command = plan

  variables {
    permission_sets = { admin = { policy_statements = [{ actions = ["s3:ListAllMyBuckets"] }] } }
  }

  expect_failures = [var.permission_sets]
}

run "rejects_boundary_without_policy" {
  command = plan

  variables {
    permission_sets = { admin = { permissions_boundary = { enabled = true } } }
  }

  expect_failures = [var.permission_sets]
}

run "rejects_invalid_group_key" {
  command = plan

  variables {
    groups = { Admins = {} }
  }

  expect_failures = [var.groups]
}

run "rejects_unknown_permission_set" {
  command = plan

  variables {
    account_assignments = { ops = { permission_set = "ops", principal_id = "bbbbbbbb-1111-2222-3333-444444444444", account_ids = ["222222222222"] } }
  }

  expect_failures = [var.account_assignments]
}

run "rejects_invalid_principal_type" {
  command = plan

  variables {
    account_assignments = { ops = { permission_set = "admin", principal_type = "ROLE", principal_id = "bbbbbbbb-1111-2222-3333-444444444444", account_ids = ["222222222222"] } }
  }

  expect_failures = [var.account_assignments]
}

run "rejects_assignment_without_principal" {
  command = plan

  variables {
    account_assignments = { ops = { permission_set = "admin", account_ids = ["222222222222"] } }
  }

  expect_failures = [var.account_assignments]
}

run "rejects_invalid_account_id" {
  command = plan

  variables {
    account_assignments = { ops = { permission_set = "admin", principal_id = "bbbbbbbb-1111-2222-3333-444444444444", account_ids = ["2222"] } }
  }

  expect_failures = [var.account_assignments]
}
