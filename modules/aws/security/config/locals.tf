locals {
  partition              = module.naming.partition
  account_id             = module.naming.account_id
  regions                = length(var.regions) > 0 ? distinct(var.regions) : [module.naming.region]
  recorder_regions       = var.recorder.enabled ? toset(local.regions) : toset([])
  global_resource_region = coalesce(var.recorder.global_resource_region, module.naming.region)
  kms_key_arn            = module.encryption.key_arn

  service_linked_role_arn = "arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig"

  delivery_source_accounts = distinct(concat([local.account_id], var.bucket.allowed_account_ids))

  kms_service_statement_candidates = [
    {
      when = true
      statement = {
        sid        = "AWSConfigKMSPolicy"
        actions    = ["kms:Decrypt", "kms:GenerateDataKey"]
        principals = { Service = ["config.amazonaws.com"] }
        conditions = [{ test = "StringEquals", variable = "aws:SourceAccount", values = local.delivery_source_accounts }]
      }
    },
    {
      when = var.bucket.organization_id != null
      statement = {
        sid        = "AWSConfigKMSPolicyOrganization"
        actions    = ["kms:Decrypt", "kms:GenerateDataKey"]
        principals = { Service = ["config.amazonaws.com"] }
        conditions = [{ test = "StringEquals", variable = "aws:SourceOrgID", values = [coalesce(var.bucket.organization_id, "none")] }]
      }
    },
  ]

  kms_service_statements = [for c in local.kms_service_statement_candidates : c.statement if c.when]

  config_principals = toset(["config.amazonaws.com", "config-multiaccountsetup.amazonaws.com"])

  managed_rule_references = toset(concat(keys(local.managed_rules), [for rule in values(local.managed_rules) : rule.identifier]))

  required_tag_keys_csv = join(",", var.organization_rules.required_tag_keys)

  required_tags_parameters = merge(
    { for index, key in var.organization_rules.required_tag_keys : "tag${index + 1}Key" => key },
    { for index, key in var.organization_rules.required_tag_keys : "tag${index + 1}Value" => var.organization_rules.required_tag_values[key] if contains(keys(var.organization_rules.required_tag_values), key) },
  )

  rule_set = merge(
    {
      for key, rule in local.managed_rules : key => {
        rule_identifier = rule.identifier
        description     = rule.description
        global          = rule.global
        only_regions    = rule.only_regions
        except_regions  = rule.except_regions
        input_parameters = merge(
          key == "required-tags" ? local.required_tags_parameters : rule.input_parameters,
          contains(keys(rule.input_parameters), "requiredKeyTags") ? { requiredKeyTags = local.required_tag_keys_csv } : {},
          try(var.organization_rules.rule_parameter_overrides[rule.identifier], {}),
          try(var.organization_rules.rule_parameter_overrides[key], {}),
        )
        maximum_execution_frequency = rule.maximum_execution_frequency
        resource_types_scope        = length(rule.resource_types_scope) > 0 ? rule.resource_types_scope : null
        resource_id_scope           = null
        tag_key_scope               = null
        tag_value_scope             = null
        excluded_accounts           = var.organization_rules.excluded_accounts
        regions                     = null
      } if !contains(var.organization_rules.disabled_rules, key) && !contains(var.organization_rules.disabled_rules, rule.identifier)
    },
    {
      for key, rule in var.organization_rules.additional_rules : key => {
        rule_identifier             = rule.rule_identifier
        description                 = rule.description
        global                      = false
        only_regions                = []
        except_regions              = []
        input_parameters            = rule.input_parameters
        maximum_execution_frequency = rule.maximum_execution_frequency
        resource_types_scope        = rule.resource_types_scope
        resource_id_scope           = rule.resource_id_scope
        tag_key_scope               = rule.tag_key_scope
        tag_value_scope             = rule.tag_value_scope
        excluded_accounts           = rule.excluded_accounts != null ? rule.excluded_accounts : var.organization_rules.excluded_accounts
        regions                     = rule.regions
      }
    },
  )

  organization_rule_regions = var.organization_rules.regions != null ? distinct(var.organization_rules.regions) : local.regions
  account_rule_regions      = var.account_rules.regions != null ? distinct(var.account_rules.regions) : local.regions

  rule_deployments = {
    organization = {
      enabled        = var.organization_rules.enabled
      regions        = local.organization_rule_regions
      global_regions = length(local.organization_rule_regions) == 0 ? [] : [contains(local.organization_rule_regions, local.global_resource_region) ? local.global_resource_region : local.organization_rule_regions[0]]
    }
    account = {
      enabled        = var.account_rules.enabled
      regions        = local.account_rule_regions
      global_regions = length(local.account_rule_regions) == 0 ? [] : [contains(local.account_rule_regions, local.global_resource_region) ? local.global_resource_region : local.account_rule_regions[0]]
    }
  }

  rule_instances = {
    for item in flatten([
      for mode, deployment in local.rule_deployments : [
        for key, rule in local.rule_set : [
          for region in(rule.regions != null ? rule.regions : (rule.global ? deployment.global_regions : deployment.regions)) : merge(rule, {
            mode   = mode
            key    = key
            region = region
          }) if(length(rule.only_regions) == 0 || contains(rule.only_regions, region)) && !contains(rule.except_regions, region)
        ]
      ] if deployment.enabled
    ]) : "${item.mode}/${item.region}/${item.key}" => item
  }

  organization_rule_instances = { for item in values(local.rule_instances) : "${item.region}/${item.key}" => item if item.mode == "organization" }
  account_rule_instances      = { for item in values(local.rule_instances) : "${item.region}/${item.key}" => item if item.mode == "account" }

  conformance_pack_instances = {
    for item in flatten([
      for key, pack in var.conformance_packs : [
        for region in(pack.regions != null ? pack.regions : local.regions) : merge(pack, {
          key    = key
          region = region
        })
      ]
    ]) : "${item.region}/${item.key}" => item
  }

  rule_names = merge(
    { for key in keys(local.rule_set) : "rule-${key}" => { suffix = key, max_length = 64 } },
    { for key in keys(var.conformance_packs) : "pack-${key}" => { suffix = key, max_length = 128 } },
  )
}
