locals {
  secret_name      = module.naming.names.secret
  multi_region_key = var.kms.create && length(var.replica_regions) > 0
  kms_key_arn      = local.multi_region_key ? module.key[0].arn : module.encryption.key_arn
  replica_key_arns = local.multi_region_key ? module.key[0].replica_arns : {}
}
