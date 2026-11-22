locals {
  account_id = module.naming.account_id
  regions    = length(var.regions) > 0 ? distinct(var.regions) : [module.naming.region]

  admin_regions        = var.organization_admin.enabled ? toset(local.regions) : toset([])
  graph_regions        = var.behavior_graph.enabled ? toset(local.regions) : toset([])
  organization_regions = var.organization_configuration.enabled ? local.graph_regions : toset([])

  members = {
    for pair in setproduct(keys(var.behavior_graph.member_accounts), local.regions) : "${pair[0]}/${pair[1]}" => {
      account_id    = pair[0]
      email_address = var.behavior_graph.member_accounts[pair[0]]
      region        = pair[1]
    } if var.behavior_graph.enabled
  }
}
