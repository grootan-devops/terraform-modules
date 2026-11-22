locals {
  arn        = "arn:${module.naming.partition}:s3:::${module.bucket.name}"
  accounts   = length(var.source_account_ids) > 0 ? var.source_account_ids : [module.naming.account_id]
  elb_prefix = var.elb_logs.prefix == null ? "" : "${var.elb_logs.prefix}/"

  lifecycle_rules               = [{ id = "expire-logs", expiration_days = var.expiration_days, transitions = var.transitions }]
  noncurrent_version_expiration = { enabled = true, days = var.noncurrent_version_expiration_days }

  elb_legacy_accounts = {
    us-east-1      = "127311923021"
    us-east-2      = "033677994240"
    us-west-1      = "027434742980"
    us-west-2      = "797873946194"
    af-south-1     = "098369216593"
    ap-east-1      = "754344448648"
    ap-southeast-3 = "589379963580"
    ap-south-1     = "718504428378"
    ap-northeast-3 = "383597477331"
    ap-northeast-2 = "600734575887"
    ap-southeast-1 = "114774131450"
    ap-southeast-2 = "783225319266"
    ap-northeast-1 = "582318560864"
    ca-central-1   = "985666609251"
    eu-central-1   = "054676820928"
    eu-west-1      = "156460612806"
    eu-west-2      = "652711504416"
    eu-south-1     = "635631232127"
    eu-west-3      = "009996457667"
    eu-north-1     = "897822967062"
    me-south-1     = "076674570225"
    sa-east-1      = "507241528517"
    us-gov-east-1  = "190560391635"
    us-gov-west-1  = "048591011584"
  }

  elb_legacy_account = try(local.elb_legacy_accounts[module.naming.region], null)
  elb_resources      = [for a in local.accounts : "${local.arn}/${local.elb_prefix}AWSLogs/${a}/*"]

  s3_source_arns     = length(var.s3_access_logs.source_bucket_arns) > 0 ? var.s3_access_logs.source_bucket_arns : ["arn:${module.naming.partition}:s3:::*"]
  vended_source_arns = length(var.vended_logs.source_arns) > 0 ? var.vended_logs.source_arns : [for a in local.accounts : "arn:${module.naming.partition}:logs:*:${a}:*"]

  statement_candidates = [
    {
      when = var.s3_access_logs.enabled
      statement = {
        sid        = "S3ServerAccessLogs"
        actions    = ["s3:PutObject"]
        resources  = ["${local.arn}/*"]
        principals = { Service = ["logging.s3.${module.naming.dns_suffix}"] }
        conditions = [
          { test = "StringEquals", variable = "aws:SourceAccount", values = local.accounts },
          { test = "ArnLike", variable = "aws:SourceArn", values = local.s3_source_arns }
        ]
      }
    },
    {
      when = var.elb_logs.enabled
      statement = {
        sid        = "ElbLogDelivery"
        actions    = ["s3:PutObject"]
        resources  = local.elb_resources
        principals = { Service = ["logdelivery.elasticloadbalancing.${module.naming.dns_suffix}"] }
        conditions = []
      }
    },
    {
      when = var.elb_logs.enabled && local.elb_legacy_account != null
      statement = {
        sid        = "ElbLegacyLogDelivery"
        actions    = ["s3:PutObject"]
        resources  = local.elb_resources
        principals = { AWS = ["arn:${module.naming.partition}:iam::${coalesce(local.elb_legacy_account, "000000000000")}:root"] }
        conditions = []
      }
    },
    {
      when = var.vended_logs.enabled
      statement = {
        sid        = "VendedLogDeliveryWrite"
        actions    = ["s3:PutObject"]
        resources  = ["${local.arn}/*"]
        principals = { Service = ["delivery.logs.${module.naming.dns_suffix}"] }
        conditions = [
          { test = "StringEquals", variable = "s3:x-amz-acl", values = ["bucket-owner-full-control"] },
          { test = "StringEquals", variable = "aws:SourceAccount", values = local.accounts },
          { test = "ArnLike", variable = "aws:SourceArn", values = local.vended_source_arns }
        ]
      }
    },
    {
      when = var.vended_logs.enabled
      statement = {
        sid        = "VendedLogDeliveryCheck"
        actions    = ["s3:GetBucketAcl", "s3:ListBucket"]
        resources  = [local.arn]
        principals = { Service = ["delivery.logs.${module.naming.dns_suffix}"] }
        conditions = [
          { test = "StringEquals", variable = "aws:SourceAccount", values = local.accounts },
          { test = "ArnLike", variable = "aws:SourceArn", values = local.vended_source_arns }
        ]
      }
    }
  ]

  policy_statements = [for c in local.statement_candidates : c.statement if c.when]
}
