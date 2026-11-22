locals {
  account_id  = module.naming.account_id
  regions     = length(var.regions) > 0 ? distinct(var.regions) : [module.naming.region]
  org_enabled = var.organization_configuration.enabled
  scanning    = !var.organization_admin.enabled

  account_enabled = local.org_enabled ? var.organization_configuration.activate_admin_account : local.scanning

  resource_types = [
    for type, enabled in {
      EC2             = var.scan_types.ec2
      ECR             = var.scan_types.ecr
      LAMBDA          = var.scan_types.lambda
      LAMBDA_CODE     = var.scan_types.lambda_code
      CODE_REPOSITORY = var.scan_types.code_repository
    } : type if enabled
  ]

  member_account_ids = distinct(var.organization_configuration.member_account_ids)

  member_associations = local.org_enabled ? {
    for pair in setproduct(local.member_account_ids, local.regions) : "${pair[0]}/${pair[1]}" => {
      account_id = pair[0]
      region     = pair[1]
    }
  } : {}

  filter_instances = local.scanning ? {
    for pair in setproduct(keys(var.filters), local.regions) : "${pair[0]}/${pair[1]}" => {
      key    = pair[0]
      region = pair[1]
    }
  } : {}
}
