locals {
  partition       = module.naming.partition
  home_region     = module.naming.region
  regions         = distinct(concat([local.home_region], var.regions))
  central_enabled = var.hub.enabled && var.organization_configuration.enabled
  account_mode    = var.hub.enabled && !var.organization_configuration.enabled
  hub_regions     = var.hub.enabled ? toset(local.regions) : toset([])

  standard_defaults = {
    fsbp_v1_0_0        = true
    cis_v5_0_0         = true
    nist_800_171_r2    = true
    tagging_v1_0_0     = true
    pci_v4_0_1         = true
    ai_security_v1_0_0 = true
    cri_profile_v2_2   = true
    nist_800_53_r5     = false
    cis_v3_0_0         = false
    cis_v1_4_0         = false
    cis_v1_2_0         = false
    pci_v3_2_1         = false
  }

  regional_standard_paths = {
    fsbp_v1_0_0        = "standards/aws-foundational-security-best-practices/v/1.0.0"
    cis_v5_0_0         = "standards/cis-aws-foundations-benchmark/v/5.0.0"
    cis_v3_0_0         = "standards/cis-aws-foundations-benchmark/v/3.0.0"
    cis_v1_4_0         = "standards/cis-aws-foundations-benchmark/v/1.4.0"
    nist_800_53_r5     = "standards/nist-800-53/v/5.0.0"
    nist_800_171_r2    = "standards/nist-800-171/v/2.0.0"
    pci_v4_0_1         = "standards/pci-dss/v/4.0.1"
    pci_v3_2_1         = "standards/pci-dss/v/3.2.1"
    tagging_v1_0_0     = "standards/aws-resource-tagging-standard/v/1.0.0"
    ai_security_v1_0_0 = "standards/ai-security-best-practices/v/1.0.0"
  }

  regional_standard_arns = {
    for region in local.regions : region => merge(
      { for key, path in local.regional_standard_paths : key => "arn:${local.partition}:securityhub:${region}::${path}" },
      { cis_v1_2_0 = "arn:${local.partition}:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.2.0" },
      var.cri_profile.enabled ? { cri_profile_v2_2 = replace(var.cri_profile.standard_arn, "/^(arn:[^:]+:securityhub:)[a-z0-9-]+::/", "$${1}${region}::") } : {},
    )
  }

  standard_arns      = local.regional_standard_arns[local.home_region]
  selected_standards = merge(local.standard_defaults, var.standards)

  policies = local.central_enabled ? { for key, policy in var.configuration_policies : key => policy if length(policy.targets) > 0 } : {}

  policy_standard_arns = {
    for key, policy in local.policies : key => policy.service_enabled ? sort(distinct(concat(
      [for standard, enabled in merge(local.selected_standards, policy.standards) : local.standard_arns[standard] if enabled && contains(keys(local.standard_arns), standard)],
      policy.additional_standard_arns,
    ))) : []
  }

  standards_subscriptions = local.account_mode ? merge({}, [
    for region in local.regions : {
      for standard, enabled in local.selected_standards : "${region}/${standard}" => {
        region        = region
        standards_arn = local.regional_standard_arns[region][standard]
      } if enabled && contains(keys(local.regional_standard_arns[region]), standard)
    }
  ]...) : {}

  self_managed = "SELF_MANAGED_SECURITY_HUB"

  associations = local.central_enabled ? merge(
    { for index, target in var.self_managed_targets : "${local.self_managed}/${index}" => { target_id = target, policy = local.self_managed } },
    merge([for key, policy in local.policies : { for index, target in policy.targets : "${key}/${index}" => { target_id = target, policy = key } }]...),
  ) : {}
}
