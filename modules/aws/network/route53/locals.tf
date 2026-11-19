locals {
  region         = "us-east-1"
  base           = module.naming.name
  private        = length(var.vpc_ids) > 0
  query_logging  = !local.private
  signing        = !local.private && var.dnssec.enabled
  zone_label     = replace(var.zone_name, ".", "-")
  log_group_name = "/aws/route53/${var.zone_name}"
  log_group_arn  = "arn:${module.naming.partition}:logs:${local.region}:${module.naming.account_id}:log-group:${local.log_group_name}"
  kms_key_arn    = module.encryption.key_arn

  kms_service_statements = [{
    sid        = "AllowCloudWatchLogs"
    actions    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    principals = { Service = ["logs.${local.region}.${module.naming.dns_suffix}"] }
    conditions = [{ test = "ArnLike", variable = "kms:EncryptionContext:aws:logs:arn", values = [local.log_group_arn] }]
  }]

  query_log_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "Route53QueryLogs"
      Effect    = "Allow"
      Principal = { Service = "route53.${module.naming.dns_suffix}" }
      Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource  = "${local.log_group_arn}:*"
      Condition = {
        ArnLike      = { "aws:SourceArn" = "arn:${module.naming.partition}:route53:::hostedzone/${aws_route53_zone.this.zone_id}" }
        StringEquals = { "aws:SourceAccount" = module.naming.account_id }
      }
    }]
  })

  dnssec_key_statements = [
    {
      sid        = "AllowRoute53DNSSECService"
      actions    = ["kms:DescribeKey", "kms:GetPublicKey", "kms:Sign", "kms:Verify"]
      principals = { Service = ["dnssec-route53.${module.naming.dns_suffix}"] }
      conditions = [
        { test = "StringEquals", variable = "aws:SourceAccount", values = [module.naming.account_id] },
        { test = "ArnLike", variable = "aws:SourceArn", values = ["arn:${module.naming.partition}:route53:::hostedzone/*"] }
      ]
    },
    {
      sid        = "AllowRoute53DNSSECServiceToCreateGrant"
      actions    = ["kms:CreateGrant"]
      principals = { Service = ["dnssec-route53.${module.naming.dns_suffix}"] }
      conditions = [{ test = "Bool", variable = "kms:GrantIsForAWSResource", values = ["true"] }]
    }
  ]
}
