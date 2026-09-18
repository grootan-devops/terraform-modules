resource "aws_wafv2_api_key" "this" {
  count         = length(var.token_domains) > 0 ? 1 : 0
  scope         = var.scope
  token_domains = var.token_domains
}

resource "aws_wafv2_ip_set" "this" {
  for_each           = var.ip_sets
  name               = "${local.name_prefix}-${each.value.name}"
  description        = each.value.description
  scope              = var.scope
  ip_address_version = each.value.ip_address_version
  addresses          = each.value.addresses

  tags = merge(local.tags, { Name = "${local.name_prefix}-${each.value.name}" })
}

resource "aws_wafv2_regex_pattern_set" "this" {
  for_each    = var.regex_pattern_sets
  name        = "${local.name_prefix}-${each.value.name}"
  description = each.value.description
  scope       = var.scope

  dynamic "regular_expression" {
    for_each = each.value.regexes
    content {
      regex_string = regular_expression.value
    }
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-${each.value.name}" })
}

resource "aws_wafv2_web_acl" "this" {
  name        = "${local.name_prefix}-acl"
  description = "WAF for ${local.name_prefix}"
  scope       = var.scope

  default_action {
    dynamic "allow" {
      for_each = var.default_action == "allow" ? [1] : []
      content {}
    }
    dynamic "block" {
      for_each = var.default_action == "block" ? [1] : []
      content {}
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-acl-metric"
    sampled_requests_enabled   = true
  }

  # MANAGED RULES
  dynamic "rule" {
    for_each = var.managed_rules
    content {
      name     = "${local.name_prefix}-${rule.key}"
      priority = index(keys(var.managed_rules), rule.key) + 10

      override_action {
        dynamic "none" {
          for_each = rule.value.override_action == "none" ? [1] : []
          content {}
        }
        dynamic "count" {
          for_each = rule.value.override_action == "count" ? [1] : []
          content {}
        }
      }

      statement {
        managed_rule_group_statement {
          name        = rule.value.name
          vendor_name = rule.value.vendor_name
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.name_prefix}-${rule.key}-metric"
        sampled_requests_enabled   = true
      }
    }
  }

  # RATE LIMIT RULES
  dynamic "rule" {
    for_each = var.rate_limit_rules
    content {
      name     = "${local.name_prefix}-${rule.key}"
      priority = index(keys(var.rate_limit_rules), rule.key) + 100

      action {
        dynamic "block" {
          for_each = rule.value.action == "block" ? [1] : []
          content {}
        }
        dynamic "count" {
          for_each = rule.value.action == "count" ? [1] : []
          content {}
        }
        dynamic "captcha" {
          for_each = rule.value.action == "captcha" ? [1] : []
          content {}
        }
      }

      statement {
        rate_based_statement {
          limit              = rule.value.limit
          aggregate_key_type = "IP"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.name_prefix}-${rule.key}-metric"
        sampled_requests_enabled   = true
      }
    }
  }

  # IP BLOCK RULES
  dynamic "rule" {
    for_each = var.ip_block_rules
    content {
      name     = "${local.name_prefix}-${rule.key}"
      priority = index(keys(var.ip_block_rules), rule.key) + 200

      action {
        dynamic "block" {
          for_each = rule.value.action == "block" ? [1] : []
          content {}
        }
        dynamic "count" {
          for_each = rule.value.action == "count" ? [1] : []
          content {}
        }
      }

      statement {
        ip_set_reference_statement {
          arn = aws_wafv2_ip_set.this[rule.value.ip_set_key].arn
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.name_prefix}-${rule.key}-metric"
        sampled_requests_enabled   = true
      }
    }
  }

  # GEO BLOCK RULES
  dynamic "rule" {
    for_each = var.geo_block_rules
    content {
      name     = "${local.name_prefix}-${rule.key}"
      priority = index(keys(var.geo_block_rules), rule.key) + 300

      action {
        dynamic "block" {
          for_each = rule.value.action == "block" ? [1] : []
          content {}
        }
        dynamic "count" {
          for_each = rule.value.action == "count" ? [1] : []
          content {}
        }
      }

      statement {
        geo_match_statement {
          country_codes = rule.value.countries
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${local.name_prefix}-${rule.key}-metric"
        sampled_requests_enabled   = true
      }
    }
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-acl" })
}

resource "aws_wafv2_web_acl_association" "this" {
  count        = length(var.association_arns)
  resource_arn = var.association_arns[count.index]
  web_acl_arn  = aws_wafv2_web_acl.this.arn
}

resource "aws_cloudwatch_log_group" "this" {
  name              = "aws-waf-logs-${local.name_prefix}"
  retention_in_days = var.cloudwatch_logs.retention_in_days
  kms_key_id        = coalesce(var.cloudwatch_logs.kms_key_arn, var.kms_key_arn)
  log_group_class   = "STANDARD"

  tags = merge(local.tags, { Name = "aws-waf-logs-${local.name_prefix}" })
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  log_destination_configs = [aws_cloudwatch_log_group.this.arn]
  resource_arn            = aws_wafv2_web_acl.this.arn

  dynamic "redacted_fields" {
    for_each = var.redacted_fields.headers
    content {
      single_header {
        name = lower(redacted_fields.value)
      }
    }
  }

  dynamic "redacted_fields" {
    for_each = var.redacted_fields.query_string ? [1] : []
    content {
      query_string {}
    }
  }

  dynamic "redacted_fields" {
    for_each = var.redacted_fields.uri_path ? [1] : []
    content {
      uri_path {}
    }
  }
}
