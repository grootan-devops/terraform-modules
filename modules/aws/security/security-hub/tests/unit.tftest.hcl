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

  mock_resource "aws_securityhub_account" {
    defaults = {
      arn = "arn:aws:securityhub:eu-west-1:123456789012:hub/default"
    }
  }

  mock_resource "aws_securityhub_finding_aggregator" {
    defaults = {
      arn = "arn:aws:securityhub:eu-west-1:123456789012:finding-aggregator/abcd1234-abcd-1234-1234-abcdef123456"
    }
  }

  mock_resource "aws_securityhub_standards_subscription" {
    defaults = {
      arn = "arn:aws:securityhub:eu-west-1:123456789012:subscription/aws-foundational-security-best-practices/v/1.0.0"
    }
  }

  mock_resource "aws_securityhub_configuration_policy" {
    defaults = {
      id  = "00000000-1111-2222-3333-444444444444"
      arn = "arn:aws:securityhub:eu-west-1:123456789012:configuration-policy/00000000-1111-2222-3333-444444444444"
    }
  }
}

variables {
  environment = "prod"
  tags        = { Team = "security" }
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = keys(aws_securityhub_account.this) == ["eu-west-1"] && aws_securityhub_account.this["eu-west-1"].region == "eu-west-1" && aws_securityhub_account.this["eu-west-1"].enable_default_standards == false && aws_securityhub_account.this["eu-west-1"].control_finding_generator == "SECURITY_CONTROL" && aws_securityhub_account.this["eu-west-1"].auto_enable_controls == true
    error_message = "The hub uses consolidated findings, no default standards and auto-enabled controls."
  }

  assert {
    condition     = aws_securityhub_finding_aggregator.this[0].linking_mode == "ALL_REGIONS" && aws_securityhub_finding_aggregator.this[0].specified_regions == null
    error_message = "The aggregator links all Regions by default."
  }

  assert {
    condition     = aws_securityhub_organization_configuration.this[0].auto_enable == false && aws_securityhub_organization_configuration.this[0].auto_enable_standards == "NONE" && aws_securityhub_organization_configuration.this[0].organization_configuration[0].configuration_type == "CENTRAL"
    error_message = "The organization configuration is CENTRAL."
  }

  assert {
    condition     = length(aws_securityhub_configuration_policy.this) == 0 && length(aws_securityhub_configuration_policy_association.this) == 0 && output.configuration_policy_ids == {}
    error_message = "The baseline policy is created only with targets."
  }

  assert {
    condition     = length(aws_securityhub_standards_subscription.this) == 0
    error_message = "Central configuration enables standards through policies, not local subscriptions."
  }

  assert {
    condition     = length(aws_securityhub_organization_admin_account.this) == 0 && length(aws_securityhub_product_subscription.this) == 0
    error_message = "No administrator designation or product subscription by default."
  }
}

run "tags_reach_naming_with_governance_last" {
  command = plan

  variables {
    tags = { Team = "security", Application = "other" }
  }

  assert {
    condition     = module.naming.tags["Team"] == "security" && module.naming.tags["Application"] == "platform" && module.naming.tags["ManagedBy"] == "Terraform"
    error_message = "Caller tags are kept and governance tags win."
  }
}

run "baseline_with_targets" {
  command = plan

  variables {
    configuration_policies = {
      baseline = { targets = ["r-ab12"] }
    }
  }

  assert {
    condition     = aws_securityhub_configuration_policy.this["baseline"].name == "platform-prod-baseline" && aws_securityhub_configuration_policy.this["baseline"].description == "platform-prod-baseline configuration policy"
    error_message = "Policies are named <application>-<environment>-<key>."
  }

  assert {
    condition = aws_securityhub_configuration_policy.this["baseline"].configuration_policy[0].enabled_standard_arns == toset([
      "arn:aws:securityhub:eu-west-1::standards/aws-foundational-security-best-practices/v/1.0.0",
      "arn:aws:securityhub:eu-west-1::standards/cis-aws-foundations-benchmark/v/5.0.0",
      "arn:aws:securityhub:eu-west-1::standards/nist-800-171/v/2.0.0",
      "arn:aws:securityhub:eu-west-1::standards/aws-resource-tagging-standard/v/1.0.0",
      "arn:aws:securityhub:eu-west-1::standards/pci-dss/v/4.0.1",
      "arn:aws:securityhub:eu-west-1::standards/ai-security-best-practices/v/1.0.0",
    ])
    error_message = "Default standards: FSBP, CIS 5.0.0, NIST 800-171, tagging, PCI DSS 4.0.1, AI security; no CRI without its ARN."
  }

  assert {
    condition     = aws_securityhub_configuration_policy.this["baseline"].configuration_policy[0].service_enabled && length(aws_securityhub_configuration_policy.this["baseline"].configuration_policy[0].security_controls_configuration[0].disabled_control_identifiers) == 0 && aws_securityhub_configuration_policy.this["baseline"].configuration_policy[0].security_controls_configuration[0].enabled_control_identifiers == null
    error_message = "Every control stays enabled, including new ones."
  }

  assert {
    condition     = keys(aws_securityhub_configuration_policy_association.this) == ["baseline/0"] && aws_securityhub_configuration_policy_association.this["baseline/0"].target_id == "r-ab12"
    error_message = "Associations are keyed by policy and index."
  }
}

run "cri_profile_with_arn" {
  command = plan

  variables {
    cri_profile = { enabled = true, standard_arn = "arn:aws:securityhub:eu-west-1::standards/test-only-cri-profile/v/0.0.0" }
    configuration_policies = {
      baseline = { targets = ["r-ab12"] }
      no-cri   = { targets = ["ou-ab12-cdef3456"], standards = { cri_profile_v2_2 = false } }
    }
  }

  assert {
    condition     = contains(aws_securityhub_configuration_policy.this["baseline"].configuration_policy[0].enabled_standard_arns, "arn:aws:securityhub:eu-west-1::standards/test-only-cri-profile/v/0.0.0") && length(aws_securityhub_configuration_policy.this["baseline"].configuration_policy[0].enabled_standard_arns) == 7
    error_message = "CRI joins the defaults when it is enabled with its ARN."
  }

  assert {
    condition     = length(aws_securityhub_configuration_policy.this["no-cri"].configuration_policy[0].enabled_standard_arns) == 6
    error_message = "A partial standards map merges over the defaults."
  }
}

run "standards_selection" {
  command = plan

  variables {
    configuration_policies = {
      baseline = {
        targets                  = ["r-ab12"]
        standards                = { fsbp_v1_0_0 = false, nist_800_53_r5 = true, cis_v1_2_0 = true }
        additional_standard_arns = ["arn:aws:securityhub:eu-west-1::standards/custom-standard/v/1.0.0"]
      }
    }
  }

  assert {
    condition     = !contains(aws_securityhub_configuration_policy.this["baseline"].configuration_policy[0].enabled_standard_arns, "arn:aws:securityhub:eu-west-1::standards/aws-foundational-security-best-practices/v/1.0.0")
    error_message = "A standard set to false is left out."
  }

  assert {
    condition = alltrue([for arn in [
      "arn:aws:securityhub:eu-west-1::standards/nist-800-53/v/5.0.0",
      "arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.2.0",
      "arn:aws:securityhub:eu-west-1::standards/custom-standard/v/1.0.0",
    ] : contains(aws_securityhub_configuration_policy.this["baseline"].configuration_policy[0].enabled_standard_arns, arn)])
    error_message = "Opt-in and additional standards are enabled."
  }
}

run "module_standards_reach_policies" {
  command = plan

  variables {
    standards = { nist_800_53_r5 = true, pci_v4_0_1 = false }
    configuration_policies = {
      baseline  = { targets = ["r-ab12"] }
      regulated = { targets = ["ou-ab12-cdef3456"], standards = { pci_v4_0_1 = true } }
    }
  }

  assert {
    condition     = contains(aws_securityhub_configuration_policy.this["baseline"].configuration_policy[0].enabled_standard_arns, "arn:aws:securityhub:eu-west-1::standards/nist-800-53/v/5.0.0") && !contains(aws_securityhub_configuration_policy.this["baseline"].configuration_policy[0].enabled_standard_arns, "arn:aws:securityhub:eu-west-1::standards/pci-dss/v/4.0.1")
    error_message = "standards changes the defaults of every policy."
  }

  assert {
    condition     = contains(aws_securityhub_configuration_policy.this["regulated"].configuration_policy[0].enabled_standard_arns, "arn:aws:securityhub:eu-west-1::standards/pci-dss/v/4.0.1")
    error_message = "A policy's standards override the module standards."
  }
}

run "controls_and_custom_parameters" {
  command = plan

  variables {
    configuration_policies = {
      strict = {
        targets                     = ["123456789013"]
        description                 = "Strict accounts."
        enabled_control_identifiers = ["IAM.7", "S3.1"]
        custom_parameters = [{
          security_control_id = "IAM.7"
          parameters = [
            { name = "MaxPasswordAge", int = 90 },
            { name = "RequireLowercaseCharacters", bool = true },
          ]
        }]
      }
    }
  }

  assert {
    condition     = aws_securityhub_configuration_policy.this["strict"].description == "Strict accounts." && aws_securityhub_configuration_policy.this["strict"].configuration_policy[0].security_controls_configuration[0].enabled_control_identifiers == toset(["IAM.7", "S3.1"]) && aws_securityhub_configuration_policy.this["strict"].configuration_policy[0].security_controls_configuration[0].disabled_control_identifiers == null
    error_message = "enabled_control_identifiers replaces the disabled list."
  }

  assert {
    condition     = aws_securityhub_configuration_policy.this["strict"].configuration_policy[0].security_controls_configuration[0].security_control_custom_parameter[0].security_control_id == "IAM.7" && length(aws_securityhub_configuration_policy.this["strict"].configuration_policy[0].security_controls_configuration[0].security_control_custom_parameter[0].parameter) == 2
    error_message = "Custom parameters flow through."
  }
}

run "disabled_service_policy" {
  command = plan

  variables {
    configuration_policies = {
      off = { targets = ["ou-ab12-cdef3456"], service_enabled = false }
    }
  }

  assert {
    condition     = aws_securityhub_configuration_policy.this["off"].configuration_policy[0].service_enabled == false && aws_securityhub_configuration_policy.this["off"].configuration_policy[0].enabled_standard_arns == null && length(aws_securityhub_configuration_policy.this["off"].configuration_policy[0].security_controls_configuration) == 0
    error_message = "A policy that disables the service has no standards or controls."
  }
}

run "associations_and_subscriptions" {
  command = apply

  variables {
    configuration_policies = {
      baseline = { targets = ["r-ab12", "ou-ab12-cdef3456"] }
    }
    self_managed_targets  = ["123456789013"]
    product_subscriptions = ["arn:aws:securityhub:eu-west-1:956882708938:product/crowdstrike/crowdstrike-falcon"]
  }

  assert {
    condition     = sort(keys(aws_securityhub_configuration_policy_association.this)) == tolist(["SELF_MANAGED_SECURITY_HUB/0", "baseline/0", "baseline/1"])
    error_message = "One association per target."
  }

  assert {
    condition     = aws_securityhub_configuration_policy_association.this["baseline/1"].target_id == "ou-ab12-cdef3456" && aws_securityhub_configuration_policy_association.this["baseline/1"].policy_id == "00000000-1111-2222-3333-444444444444"
    error_message = "Policy targets use the policy ID."
  }

  assert {
    condition     = aws_securityhub_configuration_policy_association.this["SELF_MANAGED_SECURITY_HUB/0"].target_id == "123456789013" && aws_securityhub_configuration_policy_association.this["SELF_MANAGED_SECURITY_HUB/0"].policy_id == "SELF_MANAGED_SECURITY_HUB"
    error_message = "Self-managed targets use SELF_MANAGED_SECURITY_HUB."
  }

  assert {
    condition     = keys(aws_securityhub_product_subscription.this) == ["arn:aws:securityhub:eu-west-1:956882708938:product/crowdstrike/crowdstrike-falcon"]
    error_message = "Listed products are subscribed."
  }

  assert {
    condition     = output.arn == "arn:aws:securityhub:eu-west-1:123456789012:hub/default" && output.finding_aggregator_arn == "arn:aws:securityhub:eu-west-1:123456789012:finding-aggregator/abcd1234-abcd-1234-1234-abcdef123456" && output.configuration_policy_ids == { baseline = "00000000-1111-2222-3333-444444444444" }
    error_message = "Outputs carry the hub, aggregator and policy IDs."
  }
}

run "aggregator_specified_regions" {
  command = plan

  variables {
    finding_aggregator = { linking_mode = "SPECIFIED_REGIONS", specified_regions = ["us-east-1", "eu-central-1"] }
  }

  assert {
    condition     = aws_securityhub_finding_aggregator.this[0].specified_regions == toset(["us-east-1", "eu-central-1"])
    error_message = "specified_regions flow through."
  }
}

run "account_only_mode" {
  command = plan

  variables {
    regions                    = ["us-east-1", "eu-west-1"]
    organization_configuration = { enabled = false }
    product_subscriptions      = ["arn:aws:securityhub:eu-west-1:956882708938:product/crowdstrike/crowdstrike-falcon"]
  }

  assert {
    condition     = keys(aws_securityhub_account.this) == ["eu-west-1", "us-east-1"] && aws_securityhub_account.this["us-east-1"].region == "us-east-1" && aws_securityhub_account.this["us-east-1"].enable_default_standards == false
    error_message = "Account-only mode enables the hub in the provider Region and every listed Region."
  }

  assert {
    condition = keys(aws_securityhub_standards_subscription.this) == [
      "eu-west-1/ai_security_v1_0_0", "eu-west-1/cis_v5_0_0", "eu-west-1/fsbp_v1_0_0", "eu-west-1/nist_800_171_r2", "eu-west-1/pci_v4_0_1", "eu-west-1/tagging_v1_0_0",
      "us-east-1/ai_security_v1_0_0", "us-east-1/cis_v5_0_0", "us-east-1/fsbp_v1_0_0", "us-east-1/nist_800_171_r2", "us-east-1/pci_v4_0_1", "us-east-1/tagging_v1_0_0",
    ]
    error_message = "The default standards are subscribed in each Region; no CRI without it."
  }

  assert {
    condition     = aws_securityhub_standards_subscription.this["us-east-1/fsbp_v1_0_0"].standards_arn == "arn:aws:securityhub:us-east-1::standards/aws-foundational-security-best-practices/v/1.0.0" && aws_securityhub_standards_subscription.this["us-east-1/fsbp_v1_0_0"].region == "us-east-1"
    error_message = "Each subscription uses its Region's standards ARN."
  }

  assert {
    condition     = length(aws_securityhub_organization_configuration.this) + length(aws_securityhub_configuration_policy.this) + length(aws_securityhub_configuration_policy_association.this) + length(aws_securityhub_organization_admin_account.this) == 0
    error_message = "Account-only mode creates no central configuration."
  }

  assert {
    condition     = aws_securityhub_finding_aggregator.this[0].linking_mode == "ALL_REGIONS" && length(aws_securityhub_product_subscription.this) == 1
    error_message = "Finding aggregation and product subscriptions keep working."
  }
}

run "account_only_standard_selection" {
  command = plan

  variables {
    regions                    = ["us-east-1"]
    organization_configuration = { enabled = false }
    standards                  = { fsbp_v1_0_0 = false, cis_v1_2_0 = true, nist_800_53_r5 = true }
    cri_profile                = { enabled = true, standard_arn = "arn:aws:securityhub:eu-west-1::standards/test-only-cri-profile/v/0.0.0" }
  }

  assert {
    condition     = !contains(keys(aws_securityhub_standards_subscription.this), "eu-west-1/fsbp_v1_0_0") && aws_securityhub_standards_subscription.this["eu-west-1/nist_800_53_r5"].standards_arn == "arn:aws:securityhub:eu-west-1::standards/nist-800-53/v/5.0.0"
    error_message = "standards turns defaults off and opt-in standards on."
  }

  assert {
    condition     = aws_securityhub_standards_subscription.this["us-east-1/cis_v1_2_0"].standards_arn == "arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.2.0"
    error_message = "CIS v1.2.0 uses its global ruleset ARN."
  }

  assert {
    condition     = aws_securityhub_standards_subscription.this["us-east-1/cri_profile_v2_2"].standards_arn == "arn:aws:securityhub:us-east-1::standards/test-only-cri-profile/v/0.0.0" && aws_securityhub_standards_subscription.this["eu-west-1/cri_profile_v2_2"].standards_arn == "arn:aws:securityhub:eu-west-1::standards/test-only-cri-profile/v/0.0.0"
    error_message = "The CRI ARN takes each subscription's Region."
  }
}

run "account_only_mode_outputs" {
  command   = apply
  state_key = "account_only"

  variables {
    organization_configuration = { enabled = false }
    organization_admin         = { enabled = true, account_id = "222222222222" }
  }

  assert {
    condition     = output.arn == "arn:aws:securityhub:eu-west-1:123456789012:hub/default" && output.finding_aggregator_arn == "arn:aws:securityhub:eu-west-1:123456789012:finding-aggregator/abcd1234-abcd-1234-1234-abcdef123456" && output.configuration_policy_ids == {}
    error_message = "Hub and aggregator outputs work without central configuration."
  }

  assert {
    condition     = length(aws_securityhub_standards_subscription.this) == 6 && aws_securityhub_standards_subscription.this["eu-west-1/fsbp_v1_0_0"].arn == "arn:aws:securityhub:eu-west-1:123456789012:subscription/aws-foundational-security-best-practices/v/1.0.0"
    error_message = "Standards are subscribed in the provider Region."
  }

  assert {
    condition     = aws_securityhub_organization_admin_account.this[0].admin_account_id == "222222222222"
    error_message = "A hub without central configuration may designate the administrator."
  }
}

run "management_account_call" {
  command = plan

  variables {
    hub                = { enabled = false }
    organization_admin = { enabled = true, account_id = "222222222222" }
    configuration_policies = {
      baseline = { targets = ["r-ab12"] }
    }
    product_subscriptions = ["arn:aws:securityhub:eu-west-1:956882708938:product/crowdstrike/crowdstrike-falcon"]
  }

  assert {
    condition     = length(aws_securityhub_organization_admin_account.this) == 1 && aws_securityhub_organization_admin_account.this[0].admin_account_id == "222222222222"
    error_message = "The management account call designates the administrator."
  }

  assert {
    condition     = length(aws_securityhub_account.this) + length(aws_securityhub_finding_aggregator.this) + length(aws_securityhub_organization_configuration.this) + length(aws_securityhub_configuration_policy.this) + length(aws_securityhub_configuration_policy_association.this) + length(aws_securityhub_product_subscription.this) == 0
    error_message = "hub.enabled = false creates nothing else."
  }

  assert {
    condition     = output.arn == null && output.finding_aggregator_arn == null
    error_message = "Hub outputs are null without a hub."
  }
}

run "rejects_management_account_as_admin" {
  command = plan

  variables {
    hub                = { enabled = false }
    organization_admin = { enabled = true, account_id = "123456789012" }
  }

  expect_failures = [aws_securityhub_organization_admin_account.this]
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

run "rejects_malformed_admin_account_id" {
  command = plan

  variables {
    hub                = { enabled = false }
    organization_admin = { enabled = true, account_id = "2222" }
  }

  expect_failures = [var.organization_admin]
}

run "rejects_admin_with_central_configuration" {
  command = plan

  variables {
    organization_admin = { enabled = true, account_id = "222222222222" }
  }

  expect_failures = [var.organization_admin]
}

run "rejects_unknown_linking_mode" {
  command = plan

  variables {
    finding_aggregator = { linking_mode = "SOME_REGIONS" }
  }

  expect_failures = [var.finding_aggregator]
}

run "rejects_specified_regions_with_all_regions" {
  command = plan

  variables {
    finding_aggregator = { linking_mode = "ALL_REGIONS", specified_regions = ["us-east-1"] }
  }

  expect_failures = [var.finding_aggregator]
}

run "rejects_invalid_policy_key" {
  command = plan

  variables {
    configuration_policies = {
      Baseline = {}
    }
  }

  expect_failures = [var.configuration_policies]
}

run "rejects_unknown_standard_key" {
  command = plan

  variables {
    configuration_policies = {
      baseline = { standards = { fsbp = true } }
    }
  }

  expect_failures = [var.configuration_policies]
}

run "rejects_service_managed_additional_standard" {
  command = plan

  variables {
    configuration_policies = {
      baseline = { additional_standard_arns = ["arn:aws:securityhub:eu-west-1::standards/service-managed-aws-control-tower/v/1.0.0"] }
    }
  }

  expect_failures = [var.configuration_policies]
}

run "rejects_conflicting_control_lists" {
  command = plan

  variables {
    configuration_policies = {
      baseline = { enabled_control_identifiers = ["IAM.7"], disabled_control_identifiers = ["S3.1"] }
    }
  }

  expect_failures = [var.configuration_policies]
}

run "rejects_malformed_target" {
  command = plan

  variables {
    configuration_policies = {
      baseline = { targets = ["root"] }
    }
  }

  expect_failures = [var.configuration_policies]
}

run "rejects_duplicate_target" {
  command = plan

  variables {
    configuration_policies = {
      baseline = { targets = ["r-ab12"] }
    }
    self_managed_targets = ["r-ab12"]
  }

  expect_failures = [var.configuration_policies]
}

run "rejects_malformed_self_managed_target" {
  command = plan

  variables {
    self_managed_targets = ["12345"]
  }

  expect_failures = [var.self_managed_targets]
}

run "rejects_malformed_cri_arn" {
  command = plan

  variables {
    cri_profile = { enabled = true, standard_arn = "cri-profile" }
  }

  expect_failures = [var.cri_profile]
}

run "rejects_cri_without_arn" {
  command = plan

  variables {
    cri_profile = { enabled = true }
  }

  expect_failures = [var.cri_profile]
}

run "rejects_malformed_region" {
  command = plan

  variables {
    organization_configuration = { enabled = false }
    regions                    = ["useast1"]
  }

  expect_failures = [var.regions]
}

run "rejects_regions_with_central_configuration" {
  command = plan

  variables {
    regions = ["us-east-1"]
  }

  expect_failures = [var.regions]
}

run "rejects_unknown_module_standard_key" {
  command = plan

  variables {
    standards = { fsbp = true }
  }

  expect_failures = [var.standards]
}

run "rejects_policy_targets_without_central_configuration" {
  command = plan

  variables {
    organization_configuration = { enabled = false }
    configuration_policies = {
      baseline = { targets = ["r-ab12"] }
    }
  }

  expect_failures = [var.configuration_policies]
}

run "rejects_self_managed_targets_without_central_configuration" {
  command = plan

  variables {
    organization_configuration = { enabled = false }
    self_managed_targets       = ["123456789013"]
  }

  expect_failures = [var.self_managed_targets]
}

run "rejects_malformed_product_arn" {
  command = plan

  variables {
    product_subscriptions = ["arn:aws:securityhub:eu-west-1::hub/default"]
  }

  expect_failures = [var.product_subscriptions]
}
