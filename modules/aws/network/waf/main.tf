module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags
}

module "encryption" {
  source = "../../core/encryption"

  application        = var.application
  environment        = var.environment
  name               = var.name
  purpose            = "waf"
  tags               = var.tags
  region             = local.region
  kms                = var.kms
  service_statements = local.kms_service_statements
}

resource "aws_wafv2_ip_set" "this" {
  for_each = var.ip_sets

  region             = local.region
  name               = "${local.base}-${each.key}"
  description        = each.value.description
  scope              = var.scope
  ip_address_version = each.value.ip_address_version
  addresses          = each.value.addresses

  tags = merge(module.naming.tags, { Name = "${local.base}-${each.key}" })
}

resource "aws_wafv2_regex_pattern_set" "this" {
  for_each = var.regex_pattern_sets

  region      = local.region
  name        = "${local.base}-${each.key}"
  description = each.value.description
  scope       = var.scope

  dynamic "regular_expression" {
    for_each = each.value.regexes
    content {
      regex_string = regular_expression.value
    }
  }

  tags = merge(module.naming.tags, { Name = "${local.base}-${each.key}" })
}

resource "aws_wafv2_web_acl" "this" {
  region        = local.region
  name          = local.base
  description   = "${local.base} web ACL"
  scope         = var.scope
  token_domains = length(var.token_domains) > 0 ? var.token_domains : null

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
    metric_name                = local.metric_name
    sampled_requests_enabled   = true
  }

  dynamic "rule" {
    for_each = var.managed_rules
    content {
      name     = "managed-${rule.key}"
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
          version     = rule.value.version
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = local.rule_metric_names["managed-${rule.key}"]
        sampled_requests_enabled   = true
      }
    }
  }

  dynamic "rule" {
    for_each = var.rate_limit_rules
    content {
      name     = "rate-${rule.key}"
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

        dynamic "challenge" {
          for_each = rule.value.action == "challenge" ? [1] : []
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
        metric_name                = local.rule_metric_names["rate-${rule.key}"]
        sampled_requests_enabled   = true
      }
    }
  }

  dynamic "rule" {
    for_each = var.ip_block_rules
    content {
      name     = "ip-${rule.key}"
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
        metric_name                = local.rule_metric_names["ip-${rule.key}"]
        sampled_requests_enabled   = true
      }
    }
  }

  dynamic "rule" {
    for_each = var.geo_block_rules
    content {
      name     = "geo-${rule.key}"
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
        metric_name                = local.rule_metric_names["geo-${rule.key}"]
        sampled_requests_enabled   = true
      }
    }
  }

  dynamic "rule" {
    for_each = var.regex_match_rules
    content {
      name     = "regex-${rule.key}"
      priority = index(keys(var.regex_match_rules), rule.key) + 400

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
        regex_pattern_set_reference_statement {
          arn = aws_wafv2_regex_pattern_set.this[rule.value.regex_pattern_set_key].arn

          field_to_match {
            dynamic "uri_path" {
              for_each = rule.value.field_to_match == "uri_path" ? [1] : []
              content {}
            }

            dynamic "query_string" {
              for_each = rule.value.field_to_match == "query_string" ? [1] : []
              content {}
            }

            dynamic "single_header" {
              for_each = rule.value.field_to_match == "single_header" ? [1] : []
              content {
                name = lower(rule.value.header_name)
              }
            }
          }

          text_transformation {
            priority = 0
            type     = rule.value.text_transformation
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = local.rule_metric_names["regex-${rule.key}"]
        sampled_requests_enabled   = true
      }
    }
  }

  tags = module.naming.tags
}
