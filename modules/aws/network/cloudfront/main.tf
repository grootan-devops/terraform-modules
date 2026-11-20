module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags
  names = {
    delivery   = { suffix = "cloudfront", max_length = 60 }
    oac-s3     = { suffix = "s3", max_length = 64 }
    oac-lambda = { suffix = "lambda", max_length = 64 }
  }
}

module "encryption" {
  source = "../../core/encryption"

  application        = var.application
  environment        = var.environment
  name               = var.name
  purpose            = "cloudfront"
  tags               = var.tags
  region             = local.region
  kms                = var.kms
  service_statements = local.kms_service_statements
}

data "aws_cloudfront_cache_policy" "managed" {
  for_each = local.managed_cache_policies

  name = each.key
}

data "aws_cloudfront_origin_request_policy" "managed" {
  for_each = local.managed_origin_request_policies

  name = each.key
}

data "aws_cloudfront_response_headers_policy" "managed" {
  for_each = local.managed_response_headers_policies

  name = each.key
}

resource "aws_cloudfront_origin_access_control" "this" {
  for_each = local.oac_types

  name                              = module.naming.names["oac-${each.key}"]
  description                       = "${local.base} ${each.key} origins"
  origin_access_control_origin_type = each.key
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  comment             = local.base
  aliases             = var.aliases
  default_root_object = var.default_root_object
  http_version        = "http2and3"
  is_ipv6_enabled     = true
  price_class         = var.price_class
  web_acl_id          = var.waf.enabled ? var.waf.web_acl_arn : null
  retain_on_delete    = false
  staging             = false
  wait_for_deployment = true

  viewer_certificate {
    cloudfront_default_certificate = local.default_certificate
    acm_certificate_arn            = local.default_certificate ? null : var.acm_certificate_arn
    ssl_support_method             = local.default_certificate ? null : "sni-only"
    minimum_protocol_version       = local.default_certificate ? "TLSv1" : var.minimum_protocol_version
  }

  dynamic "origin" {
    for_each = var.origins
    content {
      origin_id                = origin.key
      domain_name              = origin.value.domain_name
      origin_path              = origin.value.origin_path
      origin_access_control_id = origin.value.type == "custom" ? null : aws_cloudfront_origin_access_control.this[origin.value.type].id
      connection_attempts      = 3
      connection_timeout       = 10

      dynamic "custom_origin_config" {
        for_each = origin.value.type == "s3" ? [] : [1]
        content {
          http_port                = 80
          https_port               = 443
          origin_protocol_policy   = "https-only"
          origin_ssl_protocols     = ["TLSv1.2"]
          origin_read_timeout      = 60
          origin_keepalive_timeout = 5
        }
      }
    }
  }

  dynamic "origin_group" {
    for_each = var.origin_groups
    content {
      origin_id = origin_group.key

      failover_criteria {
        status_codes = origin_group.value.status_codes
      }

      member {
        origin_id = origin_group.value.primary
      }

      member {
        origin_id = origin_group.value.secondary
      }
    }
  }

  default_cache_behavior {
    target_origin_id           = var.default_cache_behavior.target_origin_id
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = var.default_cache_behavior.allowed_methods
    cached_methods             = var.default_cache_behavior.cached_methods
    compress                   = var.default_cache_behavior.compress
    cache_policy_id            = try(local.cache_policy_ids[var.default_cache_behavior.cache_policy], var.default_cache_behavior.cache_policy)
    origin_request_policy_id   = try(local.origin_request_policy_ids[var.default_cache_behavior.origin_request_policy], var.default_cache_behavior.origin_request_policy)
    response_headers_policy_id = try(local.response_headers_policy_ids[var.default_cache_behavior.response_headers_policy], var.default_cache_behavior.response_headers_policy)
  }

  dynamic "ordered_cache_behavior" {
    for_each = var.ordered_cache_behaviors
    content {
      path_pattern               = ordered_cache_behavior.value.path_pattern
      target_origin_id           = ordered_cache_behavior.value.target_origin_id
      viewer_protocol_policy     = "redirect-to-https"
      allowed_methods            = ordered_cache_behavior.value.allowed_methods
      cached_methods             = ordered_cache_behavior.value.cached_methods
      compress                   = ordered_cache_behavior.value.compress
      cache_policy_id            = try(local.cache_policy_ids[ordered_cache_behavior.value.cache_policy], ordered_cache_behavior.value.cache_policy)
      origin_request_policy_id   = try(local.origin_request_policy_ids[ordered_cache_behavior.value.origin_request_policy], ordered_cache_behavior.value.origin_request_policy)
      response_headers_policy_id = try(local.response_headers_policy_ids[ordered_cache_behavior.value.response_headers_policy], ordered_cache_behavior.value.response_headers_policy)
    }
  }

  dynamic "custom_error_response" {
    for_each = var.custom_error_responses
    content {
      error_code            = custom_error_response.value.error_code
      response_code         = custom_error_response.value.response_code
      response_page_path    = custom_error_response.value.response_page_path
      error_caching_min_ttl = custom_error_response.value.error_caching_min_ttl
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = var.geo_restriction.restriction_type
      locations        = var.geo_restriction.locations
    }
  }

  tags = module.naming.tags
}
