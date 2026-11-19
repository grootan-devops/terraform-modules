locals {
  account_id      = module.naming.account_id
  regions         = length(var.regions) > 0 ? distinct(var.regions) : [module.naming.region]
  unused_region   = coalesce(var.unused_access.region, module.naming.region)
  internal_region = coalesce(var.internal_access.region, module.naming.region)

  analyzer_created = {
    external = var.analyzers.enabled
    unused   = var.analyzers.enabled && var.unused_access.enabled
    internal = var.analyzers.enabled && var.internal_access.enabled
  }

  analyzer_regions = {
    external = local.regions
    unused   = [local.unused_region]
    internal = [local.internal_region]
  }

  archive_rule_instances = var.analyzers.enabled ? merge({}, [
    for key, rule in var.archive_rules : {
      for region in(rule.region != null ? [rule.region] : try(local.analyzer_regions[rule.analyzer], [])) : "${key}/${region}" => {
        rule_name = key
        analyzer  = rule.analyzer
        region    = region
        filters   = rule.filters
      }
    }
  ]...) : {}
}
