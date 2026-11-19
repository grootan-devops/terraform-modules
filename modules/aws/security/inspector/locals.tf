locals {
  account_id  = module.naming.account_id
  regions     = length(var.regions) > 0 ? distinct(var.regions) : [module.naming.region]
  org_enabled = var.organization_configuration.enabled
  auto_enable = var.organization_configuration.auto_enable

  resource_types = [
    for type, enabled in {
      EC2             = local.auto_enable.ec2
      ECR             = local.auto_enable.ecr
      LAMBDA          = local.auto_enable.lambda
      LAMBDA_CODE     = local.auto_enable.lambda_code
      CODE_REPOSITORY = local.auto_enable.code_repository
    } : type if enabled
  ]

  member_account_ids = distinct(var.member_account_ids)

  member_associations = local.org_enabled ? {
    for pair in setproduct(local.member_account_ids, local.regions) : "${pair[0]}/${pair[1]}" => {
      account_id = pair[0]
      region     = pair[1]
    }
  } : {}

  filter_instances = local.org_enabled ? {
    for pair in setproduct(keys(var.filters), local.regions) : "${pair[0]}/${pair[1]}" => {
      key    = pair[0]
      region = pair[1]
    }
  } : {}
}
