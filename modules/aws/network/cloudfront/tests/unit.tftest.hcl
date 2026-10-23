# The log delivery resources validate their ARN arguments even under the mock
# provider, so the distribution, log group and delivery destination get
# well-formed ARNs instead of random strings.
mock_provider "aws" {
  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      arn = "arn:aws:cloudfront::123456789012:distribution/E1A2B3C4D5E6F7"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/cloudfront/core-prod-web"
    }
  }

  mock_resource "aws_cloudwatch_log_delivery_destination" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:delivery-destination:core-prod-web-cloudfront"
    }
  }
}

variables {
  application         = "core"
  environment         = "prod"
  name                = "web"
  aliases             = ["app.example.com"]
  acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  kms_key_arn         = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"

  default_cache_behavior_origin_id = "api"
  origins = [
    {
      domain_name              = "api.example.com"
      origin_id                = "api"
      origin_access_control_id = null
      is_s3                    = false
    }
  ]

  cloudwatch_logs = {
    retention_in_days = 90
  }
}

run "verify_rendered_names" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/aws/cloudfront/core-prod-web"
    error_message = "Log group name did not match /aws/cloudfront/<application>-<environment>-<name>."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.this.name == "core-prod-web-cloudfront"
    error_message = "Log delivery source name did not match <rendered_name>-cloudfront."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_destination.this.name == "core-prod-web-cloudfront"
    error_message = "Log delivery destination name did not match <rendered_name>-cloudfront."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.tags["Name"] == "core-prod-web"
    error_message = "Distribution Name tag did not match the rendered name."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.comment == "CDN for core-prod"
    error_message = "Distribution comment did not match CDN for <application>-<environment>."
  }
}

run "verify_name_fallback_when_null" {
  command = plan

  variables {
    name = null
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/aws/cloudfront/core-prod"
    error_message = "Log group name did not fall back to <application>-<environment> when name is null."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.this.name == "core-prod-cloudfront" && aws_cloudwatch_log_delivery_destination.this.name == "core-prod-cloudfront"
    error_message = "Log delivery names did not fall back to <application>-<environment> when name is null."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.tags["Name"] == "core-prod"
    error_message = "Distribution Name tag did not fall back to <application>-<environment> when name is null."
  }
}

run "verify_name_fallback_when_empty" {
  command = plan

  variables {
    name = ""
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/aws/cloudfront/core-prod" && aws_cloudfront_distribution.this.tags["Name"] == "core-prod"
    error_message = "Names did not fall back to <application>-<environment> when name is empty."
  }
}

run "verify_tags" {
  command = plan

  variables {
    tags = {
      CostCenter = "1234"
      Team       = "platform"
    }
  }

  assert {
    condition     = aws_cloudfront_distribution.this.tags["Application"] == "core" && aws_cloudfront_distribution.this.tags["Environment"] == "prod" && aws_cloudfront_distribution.this.tags["Name"] == "core-prod-web"
    error_message = "Distribution is missing the Application, Environment or Name governance tags."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.tags["CostCenter"] == "1234" && aws_cloudfront_distribution.this.tags["Team"] == "platform"
    error_message = "Caller tags from var.tags were not preserved on the distribution."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.tags["Name"] == "/aws/cloudfront/core-prod-web" && aws_cloudwatch_log_group.this.tags["Application"] == "core" && aws_cloudwatch_log_group.this.tags["Environment"] == "prod" && aws_cloudwatch_log_group.this.tags["CostCenter"] == "1234"
    error_message = "Log group tags must carry governance and caller tags with Name overridden to the log group name."
  }
}

run "verify_security_defaults" {
  command = plan

  variables {
    static_paths = ["/static/*"]
  }

  assert {
    condition     = aws_cloudfront_distribution.this.viewer_certificate[0].minimum_protocol_version == "TLSv1.2_2021"
    error_message = "Viewer certificate must enforce minimum_protocol_version TLSv1.2_2021."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.viewer_certificate[0].ssl_support_method == "sni-only" && aws_cloudfront_distribution.this.viewer_certificate[0].cloudfront_default_certificate == false
    error_message = "Viewer certificate must use SNI with the supplied ACM certificate, not the CloudFront default certificate."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.viewer_certificate[0].acm_certificate_arn == "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    error_message = "Viewer certificate did not use var.acm_certificate_arn."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.default_cache_behavior[0].viewer_protocol_policy == "redirect-to-https"
    error_message = "Default cache behavior must redirect HTTP viewers to HTTPS."
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this.ordered_cache_behavior) == 1 && alltrue([for b in aws_cloudfront_distribution.this.ordered_cache_behavior : b.viewer_protocol_policy == "redirect-to-https"])
    error_message = "Every ordered cache behavior must redirect HTTP viewers to HTTPS."
  }

  assert {
    condition = [
      for c in flatten([for o in aws_cloudfront_distribution.this.origin : o.custom_origin_config]) :
      c.origin_protocol_policy == "https-only" && c.origin_ssl_protocols == toset(["TLSv1.2"])
    ] == [true]
    error_message = "The custom origin must connect over HTTPS only with TLSv1.2."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.kms_key_id == "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
    error_message = "Delivery log group must be encrypted with var.kms_key_arn when cloudwatch_logs.kms_key_arn is not set."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.this.log_type == "ACCESS_LOGS" && aws_cloudwatch_log_delivery_source.this.region == "us-east-1"
    error_message = "Access log delivery source must be ACCESS_LOGS in us-east-1."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_destination.this.region == "us-east-1" && aws_cloudwatch_log_delivery_destination.this.output_format == "json"
    error_message = "Log delivery destination must be in us-east-1 with JSON output."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery.this.region == "us-east-1" && contains(aws_cloudwatch_log_delivery.this.record_fields, "ssl-protocol") && contains(aws_cloudwatch_log_delivery.this.record_fields, "c-ip") && length(aws_cloudwatch_log_delivery.this.record_fields) == 19
    error_message = "Log delivery must run in us-east-1 and record the 19 shipped access log fields, including c-ip and ssl-protocol."
  }
}

run "verify_s3_origin_with_origin_access_control" {
  command = plan

  variables {
    origin_access_controls = {
      assets = {
        name                              = "core-prod-web-assets"
        description                       = "OAC for the assets bucket"
        origin_access_control_origin_type = "s3"
        signing_behavior                  = "always"
        signing_protocol                  = "sigv4"
      }
    }

    default_cache_behavior_origin_id = "assets"
    origins = [
      {
        domain_name              = "core-prod-assets.s3.us-west-2.amazonaws.com"
        origin_id                = "assets"
        origin_access_control_id = "oac-example"
        is_s3                    = true
      }
    ]
  }

  assert {
    condition     = length(aws_cloudfront_origin_access_control.this) == 1
    error_message = "One origin access control must be created per origin_access_controls entry."
  }

  assert {
    condition = (
      aws_cloudfront_origin_access_control.this["assets"].name == "core-prod-web-assets" &&
      aws_cloudfront_origin_access_control.this["assets"].origin_access_control_origin_type == "s3" &&
      aws_cloudfront_origin_access_control.this["assets"].signing_behavior == "always" &&
      aws_cloudfront_origin_access_control.this["assets"].signing_protocol == "sigv4"
    )
    error_message = "Origin access control settings did not flow through from origin_access_controls."
  }

  assert {
    condition     = [for o in aws_cloudfront_distribution.this.origin : o.origin_access_control_id] == ["oac-example"]
    error_message = "The origin must carry the supplied origin_access_control_id."
  }

  assert {
    condition     = alltrue([for o in aws_cloudfront_distribution.this.origin : length(o.custom_origin_config) == 0])
    error_message = "S3 origins must not get a custom_origin_config block."
  }
}

run "verify_log_delivery_wiring" {
  command = apply

  assert {
    condition     = aws_cloudwatch_log_delivery_source.this.resource_arn == aws_cloudfront_distribution.this.arn
    error_message = "Log delivery source must point at the distribution."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_destination.this.delivery_destination_configuration[0].destination_resource_arn == aws_cloudwatch_log_group.this.arn
    error_message = "Log delivery destination must point at the module's KMS-encrypted log group."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery.this.delivery_source_name == aws_cloudwatch_log_delivery_source.this.name && aws_cloudwatch_log_delivery.this.delivery_destination_arn == aws_cloudwatch_log_delivery_destination.this.arn
    error_message = "Log delivery must connect the module's delivery source to its delivery destination."
  }

  assert {
    condition     = output.arn == aws_cloudfront_distribution.this.arn && output.id == aws_cloudfront_distribution.this.id
    error_message = "arn and id outputs must expose the distribution's ARN and id."
  }

  assert {
    condition     = output.domain_name == aws_cloudfront_distribution.this.domain_name && output.hosted_zone_id == aws_cloudfront_distribution.this.hosted_zone_id
    error_message = "domain_name and hosted_zone_id outputs must expose the distribution's values."
  }
}

run "verify_parameter_defaults" {
  command = plan

  assert {
    condition     = aws_cloudfront_distribution.this.enabled == true && aws_cloudfront_distribution.this.is_ipv6_enabled == true
    error_message = "Distribution must be enabled with IPv6."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.http_version == "http2and3" && aws_cloudfront_distribution.this.price_class == "PriceClass_All"
    error_message = "Distribution must default to http2and3 and PriceClass_All."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.staging == false && aws_cloudfront_distribution.this.retain_on_delete == false && aws_cloudfront_distribution.this.wait_for_deployment == true
    error_message = "Distribution must not be a staging distribution, must not be retained on delete, and must wait for deployment."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.aliases == toset(["app.example.com"])
    error_message = "Distribution aliases did not match var.aliases."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.default_cache_behavior[0].target_origin_id == "api"
    error_message = "Default cache behavior must target default_cache_behavior_origin_id."
  }

  assert {
    condition     = data.aws_cloudfront_cache_policy.caching_disabled.name == "Managed-CachingDisabled" && data.aws_cloudfront_origin_request_policy.all_viewer.name == "Managed-AllViewer"
    error_message = "Default behavior policies must be looked up by their managed policy names."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.default_cache_behavior[0].allowed_methods == toset(["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]) && aws_cloudfront_distribution.this.default_cache_behavior[0].cached_methods == toset(["GET", "HEAD"])
    error_message = "Default cache behavior must allow all methods and cache only GET and HEAD."
  }

  assert {
    condition = alltrue(flatten([
      for o in aws_cloudfront_distribution.this.origin : [
        o.connection_attempts == 3 && o.connection_timeout == 10 && length(o.custom_origin_config) == 1,
        [for c in o.custom_origin_config : c.http_port == 80 && c.https_port == 443 && c.origin_read_timeout == 120 && c.origin_keepalive_timeout == 5]
      ]
    ]))
    error_message = "Custom origin connection settings did not match the shipped defaults."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.restrictions[0].geo_restriction[0].restriction_type == "none" && length(aws_cloudfront_distribution.this.restrictions[0].geo_restriction[0].locations) == 0
    error_message = "Geo restriction must default to none with no locations."
  }

  assert {
    condition     = length(aws_cloudfront_origin_access_control.this) == 0
    error_message = "No origin access controls must be created by default."
  }

  assert {
    condition = (
      length(aws_cloudfront_distribution.this.ordered_cache_behavior) == 0 &&
      length(aws_cloudfront_distribution.this.origin_group) == 0 &&
      length(aws_cloudfront_distribution.this.custom_error_response) == 0 &&
      length(aws_cloudfront_distribution.this.cache_tag_config) == 0
    )
    error_message = "Ordered cache behaviors, origin groups, custom error responses and cache tag config must be off by default."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 90 && aws_cloudwatch_log_group.this.log_group_class == "STANDARD" && aws_cloudwatch_log_group.this.deletion_protection_enabled == false
    error_message = "Log group must use the configured retention, the STANDARD class, and default deletion protection off."
  }
}

run "verify_parameter_overrides" {
  command = plan

  variables {
    aliases                      = ["app.example.com", "www.example.com"]
    web_acl_id                   = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/core-prod-edge/12345678-1234-1234-1234-123456789012"
    default_root_object          = "index.html"
    static_paths                 = ["/static/*", "/assets/*"]
    cache_tag_config_header_name = "Cache-Tag"

    origins = [
      {
        domain_name              = "api.example.com"
        origin_id                = "api"
        origin_access_control_id = null
        is_s3                    = false
      },
      {
        domain_name              = "api-dr.example.com"
        origin_id                = "api-dr"
        origin_access_control_id = null
        is_s3                    = false
      }
    ]

    origin_groups = [
      {
        origin_id             = "api-failover"
        failover_status_codes = [500, 502, 503, 504]
        primary_member_id     = "api"
        secondary_member_id   = "api-dr"
      }
    ]

    custom_error_responses = [
      {
        error_code            = 404
        response_code         = 200
        error_caching_min_ttl = 300
        response_page_path    = "/index.html"
      }
    ]

    geo_restriction = {
      restriction_type = "whitelist"
      locations        = ["US", "CA"]
    }

    cloudwatch_logs = {
      retention_in_days           = 365
      kms_key_arn                 = "arn:aws:kms:us-east-1:123456789012:key/abcdefab-1234-1234-1234-abcdefabcdef"
      deletion_protection_enabled = true
    }
  }

  assert {
    condition     = aws_cloudfront_distribution.this.aliases == toset(["app.example.com", "www.example.com"])
    error_message = "aliases override did not flow through."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.web_acl_id == "arn:aws:wafv2:us-east-1:123456789012:global/webacl/core-prod-edge/12345678-1234-1234-1234-123456789012"
    error_message = "web_acl_id did not flow through to the distribution."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.default_root_object == "index.html"
    error_message = "default_root_object did not flow through to the distribution."
  }

  assert {
    condition     = [for b in aws_cloudfront_distribution.this.ordered_cache_behavior : b.path_pattern] == ["/static/*", "/assets/*"]
    error_message = "One ordered cache behavior must be created per static path, in order."
  }

  assert {
    condition = alltrue([
      for b in aws_cloudfront_distribution.this.ordered_cache_behavior :
      b.target_origin_id == "api" &&
      b.allowed_methods == toset(["GET", "HEAD", "OPTIONS"]) &&
      b.cached_methods == toset(["GET", "HEAD", "OPTIONS"])
    ])
    error_message = "Static path behaviors must target the default origin with read-only methods."
  }

  assert {
    condition     = data.aws_cloudfront_cache_policy.caching_optimized.name == "Managed-CachingOptimized" && data.aws_cloudfront_origin_request_policy.host_header_only.name == "Managed-AllViewerExceptHostHeader"
    error_message = "Static path policies must be looked up by their managed policy names."
  }

  assert {
    condition     = length(aws_cloudfront_distribution.this.origin) == 2 && toset([for o in aws_cloudfront_distribution.this.origin : o.origin_id]) == toset(["api", "api-dr"])
    error_message = "Every entry in var.origins must become a distribution origin."
  }

  assert {
    condition = anytrue([
      for g in aws_cloudfront_distribution.this.origin_group :
      g.origin_id == "api-failover" &&
      g.failover_criteria[0].status_codes == toset([500, 502, 503, 504]) &&
      [for m in g.member : m.origin_id] == ["api", "api-dr"]
    ])
    error_message = "Origin group failover settings did not flow through."
  }

  assert {
    condition = anytrue([
      for e in aws_cloudfront_distribution.this.custom_error_response :
      e.error_code == 404 && e.response_code == 200 && e.error_caching_min_ttl == 300 && e.response_page_path == "/index.html"
    ])
    error_message = "Custom error response did not flow through."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.cache_tag_config[0].header_name == "Cache-Tag"
    error_message = "cache_tag_config_header_name did not create the cache tag config block."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.restrictions[0].geo_restriction[0].restriction_type == "whitelist" && aws_cloudfront_distribution.this.restrictions[0].geo_restriction[0].locations == toset(["US", "CA"])
    error_message = "geo_restriction override did not flow through."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.kms_key_id == "arn:aws:kms:us-east-1:123456789012:key/abcdefab-1234-1234-1234-abcdefabcdef"
    error_message = "cloudwatch_logs.kms_key_arn must take precedence over var.kms_key_arn."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 365 && aws_cloudwatch_log_group.this.deletion_protection_enabled == true
    error_message = "cloudwatch_logs retention and deletion protection overrides did not flow through."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.viewer_certificate[0].minimum_protocol_version == "TLSv1.2_2021" && aws_cloudfront_distribution.this.default_cache_behavior[0].viewer_protocol_policy == "redirect-to-https"
    error_message = "TLS minimum and HTTPS redirect must stay enforced regardless of other inputs."
  }
}

run "verify_invalid_environment_fails" {
  command = plan

  variables {
    environment = "INVALID_UPPERCASE"
  }

  expect_failures = [var.environment]
}
