locals {
  account_id = module.naming.account_id
  arn_prefix = "arn:${module.naming.partition}"
  regions    = length(var.regions) > 0 ? distinct(var.regions) : [module.naming.region]

  per_region = {
    ebs_encryption       = var.ebs_default_encryption.enabled ? toset(local.regions) : toset([])
    metadata_defaults    = var.instance_metadata_defaults.enabled ? toset(local.regions) : toset([])
    snapshot_block       = var.ebs_snapshot_block_public_access.enabled ? toset(local.regions) : toset([])
    ami_block            = var.ami_block_public_access.enabled ? toset(local.regions) : toset([])
    serial_console_block = var.serial_console_access_block.enabled ? toset(local.regions) : toset([])
    vpc_block            = var.vpc_block_public_access.enabled ? toset(local.regions) : toset([])
    api_gateway          = var.api_gateway_logging.enabled ? toset(local.regions) : toset([])
    ecr_scanning         = var.ecr_registry_scanning.enabled ? toset(local.regions) : toset([])
  }

  ebs_default_keys = { for r, arn in var.ebs_default_encryption.kms_key_arns : r => arn if contains(local.per_region.ebs_encryption, r) }

  alternate_contacts = var.alternate_contacts.enabled ? {
    for type, contact in {
      SECURITY   = var.alternate_contacts.security
      BILLING    = var.alternate_contacts.billing
      OPERATIONS = var.alternate_contacts.operations
    } : type => contact if contact != null
  } : {}

  ecr_replication_rules = {
    for region in local.regions : region => [
      for rule in var.ecr_replication.rules : {
        destinations = [
          for d in rule.destinations : { region = d.region, registry_id = coalesce(d.registry_id, local.account_id) }
          if !(d.region == region && coalesce(d.registry_id, local.account_id) == local.account_id)
        ]
        repository_prefixes = rule.repository_prefixes
      }
    ]
  }

  ecr_replication = var.ecr_replication.enabled ? {
    for region, rules in local.ecr_replication_rules : region => [for r in rules : r if length(r.destinations) > 0]
    if length([for r in rules : r if length(r.destinations) > 0]) > 0
  } : {}

  ecr_pull_through_cache_rules = { for item in flatten([
    for prefix, rule in var.ecr_pull_through_cache_rules : [
      for region in(rule.region == null ? local.regions : [rule.region]) : {
        key    = "${region}/${prefix}"
        region = region
        prefix = prefix
        rule   = rule
      }
    ]
  ]) : item.key => item }

  support_trust_conditions = var.support_role.require_mfa ? [{ test = "Bool", variable = "aws:MultiFactorAuthPresent", values = ["true"] }] : []
}
