mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "eu-west-1"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      arn            = "arn:aws:cloudfront::123456789012:distribution/E2EXAMPLE12345"
      domain_name    = "d111111abcdef8.cloudfront.net"
      hosted_zone_id = "Z2FDTNDATAQYW2"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/cloudfront/core-prod"
    }
  }

  mock_resource "aws_cloudwatch_log_delivery_destination" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:delivery-destination:core-prod-cloudfront"
    }
  }
}

variables {
  application            = "core"
  environment            = "prod"
  tags                   = { Team = "edge" }
  origins                = { api = { domain_name = "api.example.com" } }
  default_cache_behavior = { target_origin_id = "api" }
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = aws_cloudfront_distribution.this.viewer_certificate[0].cloudfront_default_certificate && aws_cloudfront_distribution.this.viewer_certificate[0].acm_certificate_arn == null
    error_message = "No aliases means the default CloudFront certificate."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.default_cache_behavior[0].viewer_protocol_policy == "redirect-to-https" && aws_cloudfront_distribution.this.http_version == "http2and3" && aws_cloudfront_distribution.this.is_ipv6_enabled
    error_message = "Viewers are redirected to HTTPS (CloudFront.3)."
  }

  assert {
    condition     = [for o in aws_cloudfront_distribution.this.origin : o.custom_origin_config[0].origin_protocol_policy] == ["https-only"] && [for o in aws_cloudfront_distribution.this.origin : o.custom_origin_config[0].origin_ssl_protocols] == [toset(["TLSv1.2"])]
    error_message = "Custom origins use HTTPS with TLS 1.2 (CloudFront.9, CloudFront.10)."
  }

  assert {
    condition     = keys(data.aws_cloudfront_cache_policy.managed) == ["Managed-CachingOptimized"] && length(data.aws_cloudfront_origin_request_policy.managed) == 0 && keys(data.aws_cloudfront_response_headers_policy.managed) == ["Managed-SecurityHeadersPolicy"]
    error_message = "Only the managed policies in use are looked up."
  }

  assert {
    condition     = length(module.log_group) == 1 && module.log_group[0].name == "/aws/cloudfront/core-prod" && module.log_group[0].retention_in_days == 365 && module.log_group[0].kms_key_arn == null && output.kms_key_arn == null
    error_message = "Access logs go to a 365-day log group with service encryption by default."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_destination.this.output_format == "json"
    error_message = "The log group gets JSON records."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.this.region == "us-east-1" && aws_cloudwatch_log_delivery_source.this.log_type == "ACCESS_LOGS" && aws_cloudwatch_log_delivery_source.this.name == "core-prod-cloudfront" && aws_cloudwatch_log_delivery_destination.this.region == "us-east-1" && aws_cloudwatch_log_delivery.this.region == "us-east-1"
    error_message = "Log delivery runs in us-east-1."
  }

  assert {
    condition     = length(aws_cloudfront_origin_access_control.this) == 0 && aws_cloudfront_distribution.this.web_acl_id == null && aws_cloudfront_distribution.this.price_class == "PriceClass_All"
    error_message = "No origin access control without S3 or Lambda origins; no web ACL by default."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.tags["Name"] == "core-prod" && aws_cloudfront_distribution.this.tags["Team"] == "edge" && aws_cloudfront_distribution.this.tags["ManagedBy"] == "Terraform"
    error_message = "Caller and governance tags must be applied (CloudFront.14)."
  }
}

run "custom_domain" {
  command = plan

  variables {
    name                = "web"
    aliases             = ["www.example.com"]
    acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-2222-3333-4444-555555555555"
    waf                 = { enabled = true, web_acl_arn = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/core-prod/a1b2c3d4-5678-90ab-cdef-EXAMPLE11111" }
  }

  assert {
    condition     = !aws_cloudfront_distribution.this.viewer_certificate[0].cloudfront_default_certificate && aws_cloudfront_distribution.this.viewer_certificate[0].ssl_support_method == "sni-only" && aws_cloudfront_distribution.this.viewer_certificate[0].minimum_protocol_version == "TLSv1.2_2025"
    error_message = "Aliases use the ACM certificate with SNI and TLSv1.2_2025 (CloudFront.7, CloudFront.8, CloudFront.15)."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.web_acl_id == "arn:aws:wafv2:us-east-1:123456789012:global/webacl/core-prod/a1b2c3d4-5678-90ab-cdef-EXAMPLE11111"
    error_message = "waf.enabled attaches the web ACL (CloudFront.6)."
  }

  assert {
    condition     = module.log_group[0].name == "/aws/cloudfront/core-prod-web" && aws_cloudwatch_log_delivery_source.this.name == "core-prod-web-cloudfront"
    error_message = "Names follow <application>-<environment>-<name>."
  }
}

run "s3_lambda_origins_and_behaviors" {
  command = plan

  variables {
    origins = {
      site    = { domain_name = "core-prod-site-123456789012-eu-west-1.s3.eu-west-1.amazonaws.com", type = "s3" }
      backup  = { domain_name = "core-prod-site-123456789012-eu-central-1.s3.eu-central-1.amazonaws.com", type = "s3" }
      fn      = { domain_name = "abcdefghij.lambda-url.eu-west-1.on.aws", type = "lambda" }
      partner = { domain_name = "partner.example.com" }
    }
    origin_groups          = { site-failover = { primary = "site", secondary = "backup" } }
    default_cache_behavior = { target_origin_id = "site-failover" }
    default_root_object    = "index.html"
    ordered_cache_behaviors = [
      { path_pattern = "/api/*", target_origin_id = "fn", allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"], cache_policy = "Managed-CachingDisabled", origin_request_policy = "Managed-AllViewerExceptHostHeader" },
      { path_pattern = "/partner/*", target_origin_id = "partner", cache_policy = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad", response_headers_policy = "67f7725c-6f97-4210-82d7-5512b31e9d03" }
    ]
  }

  assert {
    condition     = keys(aws_cloudfront_origin_access_control.this) == ["lambda", "s3"] && aws_cloudfront_origin_access_control.this["s3"].signing_behavior == "always" && aws_cloudfront_origin_access_control.this["s3"].name == "core-prod-s3" && aws_cloudfront_origin_access_control.this["lambda"].origin_access_control_origin_type == "lambda"
    error_message = "S3 and Lambda origins get a SigV4 origin access control (CloudFront.13, CloudFront.16)."
  }

  assert {
    condition     = length([for o in aws_cloudfront_distribution.this.origin : o if o.origin_id == "site" && length(o.custom_origin_config) == 0]) == 1 && length([for o in aws_cloudfront_distribution.this.origin : o if o.origin_id == "fn" && length(o.custom_origin_config) == 1]) == 1
    error_message = "S3 origins have no custom origin config; Lambda URLs do."
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this.origin_group) == 1 && aws_cloudfront_distribution.this.default_root_object == "index.html"
    error_message = "Origin groups provide failover (CloudFront.4); default root object (CloudFront.1)."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.ordered_cache_behavior[1].cache_policy_id == "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" && aws_cloudfront_distribution.this.ordered_cache_behavior[1].response_headers_policy_id == "67f7725c-6f97-4210-82d7-5512b31e9d03" && aws_cloudfront_distribution.this.ordered_cache_behavior[1].viewer_protocol_policy == "redirect-to-https"
    error_message = "Policy IDs pass through unchanged."
  }

  assert {
    condition     = keys(data.aws_cloudfront_cache_policy.managed) == ["Managed-CachingDisabled", "Managed-CachingOptimized"] && keys(data.aws_cloudfront_origin_request_policy.managed) == ["Managed-AllViewerExceptHostHeader"] && keys(data.aws_cloudfront_response_headers_policy.managed) == ["Managed-SecurityHeadersPolicy"]
    error_message = "Managed names are looked up once each."
  }
}

run "module_key_is_planned_safely" {
  command = plan

  variables {
    kms = { create = true }
  }

  assert {
    condition     = module.encryption.created && module.log_group[0].name == "/aws/cloudfront/core-prod"
    error_message = "kms.create must plan without knowing the key ARN."
  }
}

run "module_key_encrypts_logs" {
  command = apply

  variables {
    kms = { create = true }
  }

  assert {
    condition     = module.log_group[0].kms_key_arn == "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555" && output.kms_key_arn == module.log_group[0].kms_key_arn
    error_message = "The us-east-1 module key must encrypt the log group."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.this.resource_arn == "arn:aws:cloudfront::123456789012:distribution/E2EXAMPLE12345" && aws_cloudwatch_log_delivery_destination.this.delivery_destination_configuration[0].destination_resource_arn == module.log_group[0].arn
    error_message = "The distribution's access logs are delivered to the log group."
  }

  assert {
    condition     = output.domain_name == "d111111abcdef8.cloudfront.net" && output.hosted_zone_id == "Z2FDTNDATAQYW2" && output.arn == "arn:aws:cloudfront::123456789012:distribution/E2EXAMPLE12345" && output.log_group_name == "/aws/cloudfront/core-prod"
    error_message = "Outputs expose the distribution for DNS and logs."
  }
}

run "caller_key_id" {
  command   = plan
  state_key = "key_id"

  variables {
    kms = { key_id = "11111111-2222-3333-4444-555555555555" }
  }

  assert {
    condition     = module.log_group[0].kms_key_arn == "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    error_message = "A key ID becomes a us-east-1 key ARN."
  }
}

run "logs_to_s3" {
  command   = apply
  state_key = "s3"

  variables {
    logging = { destination = "s3", s3_bucket_arn = "arn:aws:s3:::core-prod-logs-123456789012-eu-west-1" }
  }

  assert {
    condition     = length(module.log_group) == 0 && output.log_group_name == null && output.log_group_arn == null
    error_message = "The s3 destination creates no log group."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_destination.this.delivery_destination_configuration[0].destination_resource_arn == "arn:aws:s3:::core-prod-logs-123456789012-eu-west-1/AWSLogs" && aws_cloudwatch_log_delivery_destination.this.output_format == "json" && aws_cloudwatch_log_delivery_destination.this.region == "us-east-1"
    error_message = "The us-east-1 destination writes JSON under <bucket>/AWSLogs."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery.this.s3_delivery_configuration[0].suffix_path == "123456789012/CloudFront/{DistributionId}/{yyyy}/{MM}/{dd}/{HH}" && !aws_cloudwatch_log_delivery.this.s3_delivery_configuration[0].enable_hive_compatible_path && length(aws_cloudwatch_log_delivery.this.s3_delivery_configuration) == 1
    error_message = "Objects land under <account>/CloudFront/<distribution>/<hour>, no Hive paths."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.this.resource_arn == "arn:aws:cloudfront::123456789012:distribution/E2EXAMPLE12345" && aws_cloudwatch_log_delivery.this.delivery_destination_arn == "arn:aws:logs:us-east-1:123456789012:delivery-destination:core-prod-cloudfront" && contains(aws_cloudwatch_log_delivery.this.record_fields, "c-ip")
    error_message = "The distribution's access logs are delivered to the bucket destination."
  }
}

run "logs_to_s3_plan_safely" {
  command   = plan
  state_key = "s3_plan"

  variables {
    logging = { destination = "s3", s3_bucket_arn = "arn:aws:s3:::core-prod-logs-123456789012-eu-west-1", prefix = "cdn" }
  }

  assert {
    condition     = length(module.log_group) == 0 && !module.encryption.created && aws_cloudwatch_log_delivery_destination.this.delivery_destination_configuration[0].destination_resource_arn == "arn:aws:s3:::core-prod-logs-123456789012-eu-west-1/cdn"
    error_message = "The s3 destination plans from the literal destination and puts prefix in the bucket path."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Web_CDN"
  }

  expect_failures = [var.name]
}

run "rejects_invalid_application" {
  command = plan

  variables {
    application = "Core"
  }

  expect_failures = [var.application]
}

run "rejects_invalid_environment" {
  command = plan

  variables {
    environment = "PROD"
  }

  expect_failures = [var.environment]
}

run "rejects_aliases_without_certificate" {
  command = plan

  variables {
    aliases = ["www.example.com"]
  }

  expect_failures = [var.acm_certificate_arn]
}

run "rejects_waf_without_web_acl" {
  command = plan

  variables {
    waf = { enabled = true }
  }

  expect_failures = [var.waf]
}

run "rejects_old_tls_policy" {
  command = plan

  variables {
    minimum_protocol_version = "TLSv1.2_2021"
  }

  expect_failures = [var.minimum_protocol_version]
}

run "rejects_invalid_origin_type" {
  command = plan

  variables {
    origins                = { api = { domain_name = "api.example.com", type = "mediastore" } }
    default_cache_behavior = { target_origin_id = "api" }
  }

  expect_failures = [var.origins]
}

run "rejects_unknown_origin_group_member" {
  command = plan

  variables {
    origin_groups = { g = { primary = "api", secondary = "missing" } }
  }

  expect_failures = [var.origin_groups]
}

run "rejects_unknown_default_origin" {
  command = plan

  variables {
    default_cache_behavior = { target_origin_id = "missing" }
  }

  expect_failures = [var.default_cache_behavior]
}

run "rejects_unknown_ordered_origin" {
  command = plan

  variables {
    ordered_cache_behaviors = [{ path_pattern = "/x/*", target_origin_id = "missing" }]
  }

  expect_failures = [var.ordered_cache_behaviors]
}

run "rejects_invalid_geo_restriction" {
  command = plan

  variables {
    geo_restriction = { restriction_type = "allow" }
  }

  expect_failures = [var.geo_restriction]
}

run "rejects_invalid_price_class" {
  command = plan

  variables {
    price_class = "PriceClass_50"
  }

  expect_failures = [var.price_class]
}

run "rejects_log_key_outside_us_east_1" {
  command = plan

  variables {
    cloudwatch_logs = { kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" }
  }

  expect_failures = [var.cloudwatch_logs]
}

run "rejects_create_and_key_id" {
  command = plan

  variables {
    kms = { create = true, key_id = "11111111-2222-3333-4444-555555555555" }
  }

  expect_failures = [var.kms]
}

run "rejects_key_outside_us_east_1" {
  command = plan

  variables {
    kms = { key_id = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" }
  }

  expect_failures = [var.kms]
}

run "rejects_invalid_log_destination" {
  command = plan

  variables {
    logging = { destination = "firehose" }
  }

  expect_failures = [var.logging]
}

run "rejects_s3_logging_without_bucket" {
  command = plan

  variables {
    logging = { destination = "s3" }
  }

  expect_failures = [var.logging]
}

run "rejects_log_bucket_with_dots" {
  command = plan

  variables {
    logging = { destination = "s3", s3_bucket_arn = "arn:aws:s3:::logs.example.com" }
  }

  expect_failures = [var.logging]
}

run "rejects_nested_log_prefix" {
  command = plan

  variables {
    logging = { destination = "s3", s3_bucket_arn = "arn:aws:s3:::core-prod-logs-123456789012-eu-west-1", prefix = "cdn/edge" }
  }

  expect_failures = [var.logging]
}

run "rejects_kms_with_s3_logging" {
  command = plan

  variables {
    kms     = { create = true }
    logging = { destination = "s3", s3_bucket_arn = "arn:aws:s3:::core-prod-logs-123456789012-eu-west-1" }
  }

  expect_failures = [var.logging]
}
