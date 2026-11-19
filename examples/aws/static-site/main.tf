locals {
  edge_log_groups = "arn:${module.naming.partition}:logs:${module.naming.region}:${module.naming.account_id}:log-group:"
  admin_dns_value = module.admin.domain_dns_records[var.domain_name].sub_domains["admin"].value
}

module "naming" {
  source = "../../../modules/aws/core/naming"

  application = var.application
  environment = var.environment
  region      = "us-east-1"
}

module "edge_key" {
  source = "../../../modules/aws/core/encryption"

  application = var.application
  environment = var.environment
  purpose     = "edge-logs"
  region      = module.naming.region
  kms         = var.log_kms
  service_statements = [{
    sid        = "AllowCloudWatchLogs"
    actions    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    principals = { Service = ["logs.${module.naming.region}.${module.naming.dns_suffix}"] }
    conditions = [{
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["${local.edge_log_groups}/aws/cloudfront/${module.naming.name}-*", "${local.edge_log_groups}aws-waf-logs-${module.naming.name}-*"]
    }]
  }]
}

module "zone" {
  source = "../../../modules/aws/network/route53"

  application = var.application
  environment = var.environment
  zone_name   = var.domain_name
  records = {
    apex      = { type = "A", alias = { name = module.cdn.domain_name, zone_id = module.cdn.hosted_zone_id } }
    apex-ipv6 = { type = "AAAA", alias = { name = module.cdn.domain_name, zone_id = module.cdn.hosted_zone_id } }
    www       = { name = "www", type = "A", alias = { name = module.cdn.domain_name, zone_id = module.cdn.hosted_zone_id } }
    www-ipv6  = { name = "www", type = "AAAA", alias = { name = module.cdn.domain_name, zone_id = module.cdn.hosted_zone_id } }
    admin     = { name = "admin", type = "CNAME", records = [local.admin_dns_value] }
  }
}

module "cert" {
  source = "../../../modules/aws/security/acm"

  application               = var.application
  environment               = var.environment
  domain_name               = var.domain_name
  subject_alternative_names = ["www.${var.domain_name}", "admin.${var.domain_name}"]
  region                    = "us-east-1"
  validation                = { zone_id = module.zone.zone_id }
}

module "logs" {
  source = "../../../modules/aws/storage/log-bucket"

  application = var.application
  environment = var.environment
  name        = "logs"
}

module "site" {
  source = "../../../modules/aws/storage/s3"

  application = var.application
  environment = var.environment
  name        = "site"
  access_logs = { enabled = true, bucket = module.logs.name, prefix = "site/" }
  policy_statements = [{
    sid        = "AllowCloudFrontRead"
    actions    = ["s3:GetObject"]
    principals = { Service = ["cloudfront.amazonaws.com"] }
    conditions = [{ test = "StringEquals", variable = "AWS:SourceArn", values = [module.cdn.arn] }]
  }]
}

module "edge_waf" {
  source = "../../../modules/aws/network/waf"

  application      = var.application
  environment      = var.environment
  name             = "edge"
  scope            = "CLOUDFRONT"
  kms              = { key_id = module.edge_key.key_arn }
  rate_limit_rules = { per_ip = { limit = 2000 } }
}

module "cdn" {
  source = "../../../modules/aws/network/cloudfront"

  application            = var.application
  environment            = var.environment
  name                   = "site"
  aliases                = [var.domain_name, "www.${var.domain_name}"]
  acm_certificate_arn    = module.cert.arn
  waf                    = { enabled = true, web_acl_arn = module.edge_waf.arn }
  kms                    = { key_id = module.edge_key.key_arn }
  default_root_object    = "index.html"
  origins                = { site = { domain_name = module.site.regional_domain_name, type = "s3" } }
  default_cache_behavior = { target_origin_id = "site" }
  custom_error_responses = [
    { error_code = 403, response_code = 404, response_page_path = "/404.html" },
    { error_code = 404, response_code = 404, response_page_path = "/404.html" }
  ]

  alarms = { topic_arns = local.edge_alarm_topics }
}

module "admin" {
  source = "../../../modules/aws/storage/amplify"

  application = var.application
  environment = var.environment
  name        = "admin"
  description = "Admin console"
  branches    = { main = { framework = "React" } }
  domain_associations = {
    (var.domain_name) = {
      certificate_arn       = module.cert.arn
      wait_for_verification = false
      sub_domains           = { admin = { branch_name = "main", prefix = "admin" } }
    }
  }
  custom_rules = [{ source = "/<*>", target = "/index.html", status = "404-200" }]
}
