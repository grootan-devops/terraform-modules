locals {
  rotates     = var.key_usage == "ENCRYPT_DECRYPT" && var.key_spec == "SYMMETRIC_DEFAULT"
  alias       = "alias/${module.naming.names.alias}"
  description = coalesce(var.description, "${module.naming.names.alias} key")

  root_statement = {
    sid        = "EnableIAMPolicies"
    effect     = "Allow"
    actions    = ["kms:*"]
    resources  = ["*"]
    principals = { AWS = ["arn:${module.naming.partition}:iam::${module.naming.account_id}:root"] }
    conditions = []
  }
}
