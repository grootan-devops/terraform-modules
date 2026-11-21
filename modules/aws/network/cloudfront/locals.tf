locals {
  region              = "us-east-1"
  base                = module.naming.name
  default_certificate = length(var.aliases) == 0
  log_group_name      = "/aws/cloudfront/${local.base}"
  log_group_arn       = "arn:${module.naming.partition}:logs:${local.region}:${module.naming.account_id}:log-group:${local.log_group_name}"
  logs_to_cloudwatch  = var.logging.destination == "cloudwatch"
  logs_to_s3          = var.logging.destination == "s3"
  s3_suffix_path      = "${module.naming.account_id}/CloudFront/{DistributionId}/{yyyy}/{MM}/{dd}/{HH}"
  kms_key_arn         = module.encryption.key_arn
  oac_types           = toset([for o in values(var.origins) : o.type if o.type != "custom"])

  managed_cache_policies            = toset([for n in compact(concat([var.default_cache_behavior.cache_policy], var.ordered_cache_behaviors[*].cache_policy)) : n if startswith(n, "Managed-")])
  managed_origin_request_policies   = toset([for n in compact(concat([var.default_cache_behavior.origin_request_policy], var.ordered_cache_behaviors[*].origin_request_policy)) : n if startswith(n, "Managed-")])
  managed_response_headers_policies = toset([for n in compact(concat([var.default_cache_behavior.response_headers_policy], var.ordered_cache_behaviors[*].response_headers_policy)) : n if startswith(n, "Managed-")])

  cache_policy_ids            = { for n in local.managed_cache_policies : n => data.aws_cloudfront_cache_policy.managed[n].id }
  origin_request_policy_ids   = { for n in local.managed_origin_request_policies : n => data.aws_cloudfront_origin_request_policy.managed[n].id }
  response_headers_policy_ids = { for n in local.managed_response_headers_policies : n => data.aws_cloudfront_response_headers_policy.managed[n].id }

  kms_service_statements = [{
    sid        = "AllowCloudWatchLogs"
    actions    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    principals = { Service = ["logs.${local.region}.${module.naming.dns_suffix}"] }
    conditions = [{ test = "ArnLike", variable = "kms:EncryptionContext:aws:logs:arn", values = [local.log_group_arn] }]
  }]

  record_fields = [
    "date", "time", "c-ip", "cs-method", "cs(Host)", "cs-uri-stem", "cs-uri-query", "x-host-header", "sc-status",
    "cs-protocol", "time-taken", "timestamp", "DistributionId", "cs(User-Agent)", "x-edge-result-type",
    "time-to-first-byte", "ssl-protocol", "ssl-cipher", "cs-protocol-version"
  ]
}
