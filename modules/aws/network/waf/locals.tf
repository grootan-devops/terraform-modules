locals {
  base           = module.naming.name
  region         = var.scope == "CLOUDFRONT" ? "us-east-1" : null
  log_region     = coalesce(local.region, module.naming.region)
  log_group_name = "aws-waf-logs-${local.base}"
  log_group_arn  = "arn:${module.naming.partition}:logs:${local.log_region}:${module.naming.account_id}:log-group:${local.log_group_name}"
  logs_to_s3     = var.logging.destination == "s3"
  kms_key_arn    = module.encryption.key_arn

  kms_service_statements = [{
    sid        = "AllowCloudWatchLogs"
    actions    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    principals = { Service = ["logs.${local.log_region}.${module.naming.dns_suffix}"] }
    conditions = [{ test = "ArnLike", variable = "kms:EncryptionContext:aws:logs:arn", values = [local.log_group_arn] }]
  }]

  rule_names = concat(
    [for k in keys(var.managed_rules) : "managed-${k}"],
    [for k in keys(var.rate_limit_rules) : "rate-${k}"],
    [for k in keys(var.ip_block_rules) : "ip-${k}"],
    [for k in keys(var.geo_block_rules) : "geo-${k}"],
    [for k in keys(var.regex_match_rules) : "regex-${k}"]
  )

  metric_name       = local.base
  rule_metric_names = { for n in local.rule_names : n => "${local.base}-${n}" }
}
