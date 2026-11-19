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

  mock_data "aws_organizations_organization" {
    defaults = {
      id                            = "o-abc123def4"
      arn                           = "arn:aws:organizations::111111111111:organization/o-abc123def4"
      master_account_id             = "111111111111"
      aws_service_access_principals = ["cloudtrail.amazonaws.com"]
      roots = [{
        id   = "r-ab12"
        arn  = "arn:aws:organizations::111111111111:root/o-abc123def4/r-ab12"
        name = "Root"
        policy_types = [
          { type = "SERVICE_CONTROL_POLICY", status = "ENABLED" },
          { type = "RESOURCE_CONTROL_POLICY", status = "ENABLED" },
        ]
      }]
    }
  }

  mock_resource "aws_organizations_policy" {
    defaults = {
      id  = "p-examplepolicy"
      arn = "arn:aws:organizations::111111111111:policy/o-abc123def4/service_control_policy/p-examplepolicy"
    }
  }
}

variables {
  environment = "prod"
  tags        = { Team = "security" }
}

run "nothing_is_created_without_targets" {
  command = plan

  assert {
    condition     = length(aws_organizations_policy.this) == 0 && length(aws_organizations_policy_attachment.this) == 0
    error_message = "No policy may exist without targets."
  }

  assert {
    condition     = length(aws_organizations_organization.this) == 0 && length(aws_organizations_resource_policy.this) == 0 && length(aws_organizations_delegated_administrator.this) == 0
    error_message = "The organization, delegation policy and delegated administrators are opt-in."
  }

  assert {
    condition     = aws_iam_organizations_features.this[0].enabled_features == toset(["RootCredentialsManagement", "RootSessions"]) && keys(aws_organizations_aws_service_access.this) == ["iam.amazonaws.com"]
    error_message = "Centralized root access and IAM trusted access are on by default."
  }

  assert {
    condition     = output.enabled_policy_types == tolist(["RESOURCE_CONTROL_POLICY", "SERVICE_CONTROL_POLICY"]) && output.root_id == "r-ab12" && output.organization_id == "o-abc123def4"
    error_message = "Unmanaged organization: outputs read the current root."
  }
}

run "names_and_tags" {
  command = plan

  variables {
    service_control_policies = {
      deny_leave_organization = { targets = ["root"] }
    }
  }

  assert {
    condition     = aws_organizations_policy.this["deny_leave_organization"].name == "platform-prod-deny-leave-organization"
    error_message = "Policies are named <application>-<environment>-<key>."
  }

  assert {
    condition     = aws_organizations_policy.this["deny_leave_organization"].tags["Name"] == "platform-prod-deny-leave-organization" && aws_organizations_policy.this["deny_leave_organization"].tags["Application"] == "platform" && aws_organizations_policy.this["deny_leave_organization"].tags["ManagedBy"] == "Terraform" && aws_organizations_policy.this["deny_leave_organization"].tags["Team"] == "security"
    error_message = "Caller and governance tags must be applied."
  }

  assert {
    condition     = aws_organizations_policy_attachment.this["deny_leave_organization/root"].target_id == "r-ab12"
    error_message = "The root target resolves to the root ID."
  }
}

run "scp_library_content" {
  command = plan

  variables {
    application              = "core"
    exempt_principal_arns    = ["arn:aws:iam::*:role/break-glass"]
    security_admin_role_arns = ["arn:aws:iam::*:role/security-admin"]
    network_admin_role_arns  = ["arn:aws:iam::*:role/network-admin"]
    service_control_policies = {
      deny_leave_organization       = { targets = ["root"] }
      region_restriction            = { targets = ["ou-ab12-sandbox1"], allowed_regions = ["eu-west-1"], additional_global_actions = ["bedrock:*"] }
      root_user_restriction         = { targets = ["ou-ab12-sandbox1"] }
      protect_security_services     = { targets = ["ou-ab12-sandbox1"], services = ["guardduty"] }
      protect_security_kms_keys     = { targets = ["ou-ab12-sandbox1"] }
      protect_audit_buckets         = { targets = ["222222222222"], bucket_arns = ["arn:aws:s3:::core-prod-audit"] }
      ec2_guardrails                = { targets = ["ou-ab12-sandbox1"], deny_public_ip = true, allowed_instance_types = ["t3.*"] }
      network_guardrails            = { targets = ["ou-ab12-sandbox1"] }
      restrict_iam_user_credentials = { targets = ["ou-ab12-sandbox1"], allowed_principal_arns = ["arn:aws:iam::*:role/identity-automation"] }
    }
  }

  assert {
    condition     = length(aws_organizations_policy.this) == 9 && alltrue([for p in values(aws_organizations_policy.this) : p.type == "SERVICE_CONTROL_POLICY"])
    error_message = "Every SCP with targets must be created."
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.this["deny_leave_organization"].content).Statement[0].Condition.ArnNotLike["aws:PrincipalArn"] == ["arn:aws:iam::*:role/break-glass"]
    error_message = "exempt_principal_arns must be excluded from every SCP."
  }

  assert {
    condition     = contains(jsondecode(aws_organizations_policy.this["region_restriction"].content).Statement[0].NotAction, "bedrock:*") && jsondecode(aws_organizations_policy.this["region_restriction"].content).Statement[0].Condition.StringNotEquals["aws:RequestedRegion"] == ["eu-west-1"]
    error_message = "region_restriction denies other Regions except global actions."
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.this["root_user_restriction"].content).Statement[0].Condition.Null["aws:AssumedRoot"] == "true"
    error_message = "root_user_restriction must keep sts:AssumeRoot sessions usable."
  }

  assert {
    condition     = alltrue([for a in jsondecode(aws_organizations_policy.this["protect_security_services"].content).Statement[0].Action : startswith(a, "guardduty:")]) && contains(jsondecode(aws_organizations_policy.this["protect_security_services"].content).Statement[0].Condition.ArnNotLike["aws:PrincipalArn"], "arn:aws:iam::*:role/security-admin")
    error_message = "protect_security_services covers the selected services and exempts security admins."
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.this["protect_security_kms_keys"].content).Statement[0].Condition.StringEquals["aws:ResourceTag/SecurityProtection"] == "true"
    error_message = "protect_security_kms_keys keys on the protection tag."
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.this["protect_audit_buckets"].content).Statement[0].Resource == ["arn:aws:s3:::core-prod-audit"]
    error_message = "protect_audit_buckets targets the listed buckets."
  }

  assert {
    condition     = [for s in jsondecode(aws_organizations_policy.this["ec2_guardrails"].content).Statement : s.Sid] == ["DenyRunInstancesWithoutImdsV2", "DenyImdsV1Reenablement", "DenyUnencryptedVolumes", "DenyDisablingEbsEncryptionByDefault", "DenyPublicIpOnLaunch", "DenyUnapprovedInstanceTypes"]
    error_message = "ec2_guardrails must render every enabled statement."
  }

  assert {
    condition     = contains(jsondecode(aws_organizations_policy.this["network_guardrails"].content).Statement[0].Condition.ArnNotLike["aws:PrincipalArn"], "arn:aws:iam::*:role/network-admin")
    error_message = "network_guardrails exempts network admins."
  }

  assert {
    condition     = contains(jsondecode(aws_organizations_policy.this["restrict_iam_user_credentials"].content).Statement[0].Condition.ArnNotLike["aws:PrincipalArn"], "arn:aws:iam::*:role/identity-automation")
    error_message = "restrict_iam_user_credentials exempts approved automation."
  }

  assert {
    condition     = length([for s in flatten([for p in values(aws_organizations_policy.this) : jsondecode(p.content).Statement]) : s if contains(flatten([try(s.Action, [])]), "s3:PutAccountPublicAccessBlock")]) == 0
    error_message = "No SCP protects the account S3 public access block; the S3 declarative policy does."
  }

  assert {
    condition     = aws_organizations_policy_attachment.this["protect_audit_buckets/222222222222"].target_id == "222222222222" && aws_organizations_policy_attachment.this["region_restriction/ou-ab12-sandbox1"].target_id == "ou-ab12-sandbox1"
    error_message = "Account and OU targets are attached as given."
  }
}

run "scp_without_condition_omits_it" {
  command = plan

  variables {
    service_control_policies = {
      deny_leave_organization = { targets = ["root"] }
    }
  }

  assert {
    condition     = !can(jsondecode(aws_organizations_policy.this["deny_leave_organization"].content).Statement[0].Condition)
    error_message = "An SCP without exemptions carries no empty Condition."
  }
}

run "rcp_library_content" {
  command = plan

  variables {
    resource_control_policies = {
      transport_security = { targets = ["ou-ab12-sandbox1"] }
      identity_perimeter = { targets = ["ou-ab12-sandbox1"], services = ["s3", "sts"], trusted_account_ids = ["333333333333"] }
    }
  }

  assert {
    condition     = [for s in jsondecode(aws_organizations_policy.this["transport_security"].content).Statement : s.Sid] == ["DenyInsecureTransport", "DenyS3TlsBelow12"] && aws_organizations_policy.this["transport_security"].type == "RESOURCE_CONTROL_POLICY"
    error_message = "transport_security denies non-TLS and old TLS."
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.this["identity_perimeter"].content).Statement[0].Condition.StringNotEqualsIfExists["aws:PrincipalOrgID"] == "o-abc123def4" && jsondecode(aws_organizations_policy.this["identity_perimeter"].content).Statement[0].Condition.StringNotEqualsIfExists["aws:PrincipalAccount"] == ["333333333333"]
    error_message = "identity_perimeter allows the organization and trusted accounts only."
  }
}

run "declarative_library_content" {
  command = plan

  variables {
    organization = { manage = true, additional_policy_types = ["SERVICE_CONTROL_POLICY", "RESOURCE_CONTROL_POLICY"] }
    declarative_policies = {
      ec2 = {
        targets                 = ["ou-ab12-sandbox1"]
        vpc_block_public_access = { enabled = true }
        allowed_images_settings = { enabled = true }
      }
      s3                  = { targets = ["root"] }
      tag_policy          = { targets = ["root"], enforced_for = ["ec2:instance"] }
      ai_services_opt_out = { targets = ["root"], service_overrides = { rekognition = "optIn" } }
    }
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.this["ec2"].content).ec2_attributes.instance_metadata_defaults.http_tokens["@@assign"] == "required" && jsondecode(aws_organizations_policy.this["ec2"].content).ec2_attributes.instance_metadata_defaults.http_put_response_hop_limit["@@assign"] == "2"
    error_message = "The EC2 policy requires IMDSv2 with hop limit 2."
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.this["ec2"].content).ec2_attributes.snapshot_block_public_access.state["@@assign"] == "block_all_sharing" && jsondecode(aws_organizations_policy.this["ec2"].content).ec2_attributes.serial_console_access.status["@@assign"] == "disabled"
    error_message = "The EC2 policy blocks snapshot sharing and the serial console."
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.this["ec2"].content).ec2_attributes.vpc_block_public_access.internet_gateway_block.mode["@@assign"] == "block_ingress" && jsondecode(aws_organizations_policy.this["ec2"].content).ec2_attributes.allowed_images_settings.image_criteria.criteria_1.allowed_image_providers["@@assign"] == ["amazon"]
    error_message = "Optional VPC block public access and allowed images render when enabled."
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.this["s3"].content).s3_attributes.public_access_block_configuration["@@assign"] == "all" && aws_organizations_policy.this["s3"].type == "S3_POLICY"
    error_message = "The S3 policy enforces all four block public access settings."
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.this["tag_policy"].content).tags.ManagedBy.tag_value["@@assign"] == ["Terraform"] && jsondecode(aws_organizations_policy.this["tag_policy"].content).tags.Application.enforced_for["@@assign"] == ["ec2:instance"]
    error_message = "The tag policy locks governance keys."
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.this["ai_services_opt_out"].content).services.default.opt_out_policy["@@assign"] == "optOut" && jsondecode(aws_organizations_policy.this["ai_services_opt_out"].content).services.rekognition.opt_out_policy["@@assign"] == "optIn"
    error_message = "The AI opt-out policy opts out by default."
  }
}

run "ec2_policy_omits_optional_blocks" {
  command = plan

  variables {
    declarative_policies = {
      ec2 = { targets = ["root"] }
    }
    organization = { manage = true, additional_policy_types = ["SERVICE_CONTROL_POLICY", "RESOURCE_CONTROL_POLICY"] }
  }

  assert {
    condition     = !can(jsondecode(aws_organizations_policy.this["ec2"].content).ec2_attributes.vpc_block_public_access) && !can(jsondecode(aws_organizations_policy.this["ec2"].content).ec2_attributes.allowed_images_settings)
    error_message = "VPC block public access and allowed images are off by default."
  }
}

run "managed_organization_enables_only_used_types" {
  command = plan

  variables {
    organization = { manage = true, additional_policy_types = ["SERVICE_CONTROL_POLICY", "RESOURCE_CONTROL_POLICY"] }
    declarative_policies = {
      s3         = { targets = ["root"] }
      tag_policy = { targets = ["root"] }
    }
  }

  assert {
    condition     = aws_organizations_organization.this[0].enabled_policy_types == toset(["SERVICE_CONTROL_POLICY", "RESOURCE_CONTROL_POLICY", "S3_POLICY", "TAG_POLICY"]) && aws_organizations_organization.this[0].feature_set == "ALL"
    error_message = "Only the types of attached policies and additional_policy_types are enabled."
  }

  assert {
    condition     = output.enabled_policy_types == tolist(["RESOURCE_CONTROL_POLICY", "S3_POLICY", "SERVICE_CONTROL_POLICY", "TAG_POLICY"])
    error_message = "enabled_policy_types follows the managed set."
  }
}

run "managed_organization_refuses_type_disable" {
  command = plan

  variables {
    organization = { manage = true }
  }

  expect_failures = [aws_organizations_organization.this]
}

run "managed_organization_may_disable_types" {
  command = plan

  variables {
    organization = { manage = true, allow_policy_type_disable = true }
  }

  assert {
    condition     = length(aws_organizations_organization.this[0].enabled_policy_types) == 0
    error_message = "allow_policy_type_disable lets the module disable unused types."
  }
}

run "attaching_a_type_that_is_not_enabled_fails" {
  command = plan

  variables {
    declarative_policies = {
      ec2 = { targets = ["root"] }
    }
  }

  expect_failures = [aws_organizations_policy_attachment.this]
}

run "attachment_count_per_target_is_limited" {
  command = plan

  variables {
    service_control_policies = {
      deny_leave_organization   = { targets = ["root"] }
      region_restriction        = { targets = ["root"], allowed_regions = ["eu-west-1"] }
      root_user_restriction     = { targets = ["root"] }
      protect_security_services = { targets = ["root"] }
      protect_security_kms_keys = { targets = ["root"] }
      protect_audit_buckets     = { targets = ["root"], bucket_arns = ["arn:aws:s3:::core-prod-audit"] }
      ec2_guardrails            = { targets = ["root"] }
      network_guardrails        = { targets = ["root"] }
    }
    custom_policies = {
      extra-one = { type = "SERVICE_CONTROL_POLICY", content = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Deny\",\"Action\":\"ec2:CreateKeyPair\",\"Resource\":\"*\"}]}", targets = ["root"] }
      extra-two = { type = "SERVICE_CONTROL_POLICY", content = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Deny\",\"Action\":\"ec2:DeleteKeyPair\",\"Resource\":\"*\"}]}", targets = ["root"] }
    }
  }

  expect_failures = [aws_organizations_policy_attachment.this]
}

run "custom_policies" {
  command = plan

  variables {
    custom_policies = {
      deny-key-pairs = {
        type    = "SERVICE_CONTROL_POLICY"
        content = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Deny\",\"Action\":\"ec2:CreateKeyPair\",\"Resource\":\"*\"}]}"
        targets = ["ou-ab12-sandbox1"]
      }
    }
  }

  assert {
    condition     = aws_organizations_policy.this["deny-key-pairs"].name == "platform-prod-deny-key-pairs" && aws_organizations_policy.this["deny-key-pairs"].description == "Custom SERVICE_CONTROL_POLICY."
    error_message = "Custom policies are named and described."
  }
}

run "custom_rcp_shape_is_checked" {
  command = plan

  variables {
    custom_policies = {
      bad-rcp = {
        type    = "RESOURCE_CONTROL_POLICY"
        content = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"s3:GetObject\",\"Resource\":\"*\"}]}"
        targets = ["ou-ab12-sandbox1"]
      }
    }
  }

  expect_failures = [aws_organizations_policy.this]
}

run "empty_ec2_guardrails_is_rejected" {
  command = plan

  variables {
    service_control_policies = {
      ec2_guardrails = { targets = ["root"], require_imdsv2 = false, require_encrypted_volumes = false, deny_disable_ebs_default_encryption = false }
    }
  }

  expect_failures = [aws_organizations_policy.this]
}

run "trusted_access_and_delegated_administrators" {
  command = plan

  variables {
    trusted_access_service_principals = ["account.amazonaws.com", "auditmanager.amazonaws.com"]
    delegated_administrators = {
      iam = { account_id = "222222222222", service_principal = "iam.amazonaws.com" }
    }
  }

  assert {
    condition     = keys(aws_organizations_aws_service_access.this) == ["account.amazonaws.com", "auditmanager.amazonaws.com", "iam.amazonaws.com"]
    error_message = "Non-owned principals get trusted access here; IAM is added for root access."
  }

  assert {
    condition     = aws_organizations_delegated_administrator.this["iam"].account_id == "222222222222"
    error_message = "Delegated administrators are registered."
  }
}

run "root_access_management_off" {
  command = plan

  variables {
    root_access_management = { enabled = false }
  }

  assert {
    condition     = length(aws_iam_organizations_features.this) == 0 && length(aws_organizations_aws_service_access.this) == 0
    error_message = "Disabling root access removes the feature and IAM trusted access."
  }
}

run "policy_management_delegation" {
  command = plan

  variables {
    policy_management_delegation = { enabled = true, account_id = "222222222222", policy_types = ["SERVICE_CONTROL_POLICY"] }
  }

  assert {
    condition     = jsondecode(aws_organizations_resource_policy.this[0].content).Statement[2].Principal.AWS == "arn:aws:iam::222222222222:root" && jsondecode(aws_organizations_resource_policy.this[0].content).Statement[2].Condition.StringLikeIfExists["organizations:PolicyType"] == ["SERVICE_CONTROL_POLICY"]
    error_message = "Delegation is scoped to the listed policy types."
  }

  assert {
    condition     = !contains(flatten([for s in jsondecode(aws_organizations_resource_policy.this[0].content).Statement : s.Action]), "organizations:EnablePolicyType")
    error_message = "Policy types are never delegated."
  }

  assert {
    condition     = aws_organizations_resource_policy.this[0].tags["Name"] == "platform-prod-policy-delegation"
    error_message = "The delegation policy is named and tagged."
  }
}

run "outputs_after_apply" {
  command   = apply
  state_key = "outputs"

  variables {
    service_control_policies = {
      deny_leave_organization = { targets = ["root"] }
    }
  }

  assert {
    condition     = output.policies["deny_leave_organization"].id == "p-examplepolicy" && output.policies["deny_leave_organization"].name == "platform-prod-deny-leave-organization"
    error_message = "The policies output exposes id and name."
  }

  assert {
    condition     = output.attachments["deny_leave_organization/root"].target_id == "r-ab12" && output.attachments["deny_leave_organization/root"].policy_id == "p-examplepolicy"
    error_message = "The attachments output exposes policy and target IDs."
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
    environment = "PROD"
  }

  expect_failures = [var.environment]
}

run "rejects_unknown_additional_policy_type" {
  command = plan

  variables {
    organization = { manage = true, additional_policy_types = ["SECURITYHUB_CSPM_POLICY"] }
  }

  expect_failures = [var.organization]
}

run "rejects_invalid_trusted_principal" {
  command = plan

  variables {
    trusted_access_service_principals = ["account"]
  }

  expect_failures = [var.trusted_access_service_principals]
}

run "rejects_service_owned_trusted_principal" {
  command = plan

  variables {
    trusted_access_service_principals = ["guardduty.amazonaws.com"]
  }

  expect_failures = [var.trusted_access_service_principals]
}

run "rejects_invalid_delegated_administrator" {
  command = plan

  variables {
    delegated_administrators = { iam = { account_id = "2222", service_principal = "iam.amazonaws.com" } }
  }

  expect_failures = [var.delegated_administrators]
}

run "rejects_service_owned_delegated_administrator" {
  command = plan

  variables {
    delegated_administrators = { ssm = { account_id = "222222222222", service_principal = "ssm.amazonaws.com" } }
  }

  expect_failures = [var.delegated_administrators]
}

run "rejects_delegation_of_service_owned_type" {
  command = plan

  variables {
    policy_management_delegation = { enabled = true, account_id = "222222222222", policy_types = ["GUARDDUTY_POLICY"] }
  }

  expect_failures = [var.policy_management_delegation]
}

run "rejects_unknown_root_feature" {
  command = plan

  variables {
    root_access_management = { features = ["RootPasswords"] }
  }

  expect_failures = [var.root_access_management]
}

run "rejects_invalid_exempt_principal" {
  command = plan

  variables {
    exempt_principal_arns = ["break-glass"]
  }

  expect_failures = [var.exempt_principal_arns]
}

run "rejects_invalid_security_admin_role" {
  command = plan

  variables {
    security_admin_role_arns = ["arn:aws:iam::*:user/security"]
  }

  expect_failures = [var.security_admin_role_arns]
}

run "rejects_invalid_network_admin_role" {
  command = plan

  variables {
    network_admin_role_arns = ["network-admin"]
  }

  expect_failures = [var.network_admin_role_arns]
}

run "rejects_invalid_scp_target" {
  command = plan

  variables {
    service_control_policies = { deny_leave_organization = { targets = ["sandbox"] } }
  }

  expect_failures = [var.service_control_policies]
}

run "rejects_region_restriction_without_regions" {
  command = plan

  variables {
    service_control_policies = { region_restriction = { targets = ["root"] } }
  }

  expect_failures = [var.service_control_policies]
}

run "rejects_unknown_security_service" {
  command = plan

  variables {
    service_control_policies = { protect_security_services = { services = ["shield"] } }
  }

  expect_failures = [var.service_control_policies]
}

run "rejects_audit_buckets_without_arns" {
  command = plan

  variables {
    service_control_policies = { protect_audit_buckets = { targets = ["root"] } }
  }

  expect_failures = [var.service_control_policies]
}

run "rejects_invalid_iam_user_automation_arn" {
  command = plan

  variables {
    service_control_policies = { restrict_iam_user_credentials = { allowed_principal_arns = ["automation"] } }
  }

  expect_failures = [var.service_control_policies]
}

run "rejects_invalid_rcp_target" {
  command = plan

  variables {
    resource_control_policies = { transport_security = { targets = ["ou-x"] } }
  }

  expect_failures = [var.resource_control_policies]
}

run "rejects_unsupported_rcp_service" {
  command = plan

  variables {
    resource_control_policies = { transport_security = { services = ["ec2"] } }
  }

  expect_failures = [var.resource_control_policies]
}

run "rejects_invalid_trusted_account" {
  command = plan

  variables {
    resource_control_policies = { identity_perimeter = { trusted_account_ids = ["3333"] } }
  }

  expect_failures = [var.resource_control_policies]
}

run "rejects_invalid_declarative_target" {
  command = plan

  variables {
    declarative_policies = { s3 = { targets = ["everything"] } }
  }

  expect_failures = [var.declarative_policies]
}

run "rejects_invalid_ec2_setting" {
  command = plan

  variables {
    declarative_policies = { ec2 = { http_put_response_hop_limit = 0 } }
  }

  expect_failures = [var.declarative_policies]
}

run "rejects_invalid_tag_policy" {
  command = plan

  variables {
    declarative_policies = { tag_policy = { enforced_for = ["ec2"] } }
  }

  expect_failures = [var.declarative_policies]
}

run "rejects_invalid_ai_opt_out" {
  command = plan

  variables {
    declarative_policies = { ai_services_opt_out = { default_policy = "optout" } }
  }

  expect_failures = [var.declarative_policies]
}

run "rejects_service_owned_custom_type" {
  command = plan

  variables {
    custom_policies = { backup = { type = "BACKUP_POLICY", content = "{}", targets = ["root"] } }
  }

  expect_failures = [var.custom_policies]
}

run "rejects_custom_key_reusing_library_key" {
  command = plan

  variables {
    custom_policies = { deny-leave-organization = { type = "SERVICE_CONTROL_POLICY", content = "{}", targets = ["root"] } }
  }

  expect_failures = [var.custom_policies]
}

run "rejects_custom_invalid_json" {
  command = plan

  variables {
    custom_policies = { broken = { type = "SERVICE_CONTROL_POLICY", content = "{", targets = ["root"] } }
  }

  expect_failures = [var.custom_policies]
}

run "rejects_custom_without_targets" {
  command = plan

  variables {
    custom_policies = { idle = { type = "SERVICE_CONTROL_POLICY", content = "{}", targets = [] } }
  }

  expect_failures = [var.custom_policies]
}
