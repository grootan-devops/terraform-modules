resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  http_version        = "http2and3"
  price_class         = "PriceClass_All"
  comment             = "CDN for ${var.application}-${var.environment}"
  aliases             = var.aliases
  default_root_object = var.default_root_object
  wait_for_deployment = true
  web_acl_id          = var.web_acl_id
  staging             = false
  retain_on_delete    = false

  viewer_certificate {
    acm_certificate_arn            = var.acm_certificate_arn
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = "TLSv1.2_2021"
    cloudfront_default_certificate = false
  }

  dynamic "origin" {
    for_each = var.origins
    content {
      domain_name              = origin.value.domain_name
      origin_id                = origin.value.origin_id
      origin_access_control_id = origin.value.origin_access_control_id

      connection_attempts = 3
      connection_timeout  = 10

      dynamic "custom_origin_config" {
        for_each = origin.value.is_s3 ? [] : [1]
        content {
          http_port                = 80
          https_port               = 443
          origin_protocol_policy   = "https-only"
          origin_ssl_protocols     = ["TLSv1.2"]
          origin_read_timeout      = 120
          origin_keepalive_timeout = 5
        }
      }
    }
  }

  dynamic "origin_group" {
    for_each = var.origin_groups
    content {
      origin_id = origin_group.value.origin_id

      failover_criteria {
        status_codes = origin_group.value.failover_status_codes
      }

      member {
        origin_id = origin_group.value.primary_member_id
      }

      member {
        origin_id = origin_group.value.secondary_member_id
      }
    }
  }

  default_cache_behavior {
    target_origin_id         = var.default_cache_behavior_origin_id
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer.id
  }

  dynamic "ordered_cache_behavior" {
    for_each = var.static_paths
    content {
      path_pattern             = ordered_cache_behavior.value
      target_origin_id         = var.default_cache_behavior_origin_id
      viewer_protocol_policy   = "redirect-to-https"
      allowed_methods          = ["GET", "HEAD", "OPTIONS"]
      cached_methods           = ["GET", "HEAD", "OPTIONS"]
      cache_policy_id          = data.aws_cloudfront_cache_policy.caching_optimized.id
      origin_request_policy_id = data.aws_cloudfront_origin_request_policy.host_header_only.id
    }
  }

  dynamic "custom_error_response" {
    for_each = var.custom_error_responses
    content {
      error_code            = custom_error_response.value.error_code
      response_code         = custom_error_response.value.response_code
      error_caching_min_ttl = custom_error_response.value.error_caching_min_ttl
      response_page_path    = custom_error_response.value.response_page_path
    }
  }

  dynamic "cache_tag_config" {
    for_each = var.cache_tag_config_header_name != null ? [1] : []
    content {
      header_name = var.cache_tag_config_header_name
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = var.geo_restriction.restriction_type
      locations        = var.geo_restriction.locations
    }
  }

  tags = local.tags
}

resource "aws_cloudfront_origin_access_control" "this" {
  for_each = var.origin_access_controls

  name                              = each.value.name
  description                       = each.value.description
  origin_access_control_origin_type = each.value.origin_access_control_origin_type
  signing_behavior                  = each.value.signing_behavior
  signing_protocol                  = each.value.signing_protocol
}
