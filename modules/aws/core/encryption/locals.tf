locals {
  given_key_arn = var.kms.key_id == null ? null : (
    startswith(var.kms.key_id, "arn:") ? var.kms.key_id : "arn:${module.naming.partition}:kms:${module.naming.region}:${module.naming.account_id}:key/${var.kms.key_id}"
  )

  key_arn = var.kms.create ? module.key[0].arn : local.given_key_arn
}
