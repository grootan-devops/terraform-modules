# The logging configuration, associations and IP set references validate their
# ARN arguments even under the mock provider, so the Web ACL, log group and IP
# sets get well-formed ARNs instead of random strings.
mock_provider "aws" {
  mock_resource "aws_wafv2_web_acl" {
    defaults = {
      arn = "arn:aws:wafv2:us-west-2:123456789012:regional/webacl/core-prod-edge-acl/12345678-1234-1234-1234-123456789012"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-west-2:123456789012:log-group:aws-waf-logs-core-prod-edge"
    }
  }

  mock_resource "aws_wafv2_ip_set" {
    defaults = {
      arn = "arn:aws:wafv2:us-west-2:123456789012:regional/ipset/core-prod-edge-blocked/12345678-1234-1234-1234-123456789012"
    }
  }
}

variables {
  application = "core"
  environment = "prod"
  name        = "edge"
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
}

run "verify_rendered_names" {
  command = plan

  assert {
    condition     = aws_wafv2_web_acl.this.name == "core-prod-edge-acl"
    error_message = "Web ACL name did not match <application>-<environment>-<name>-acl."
  }

  assert {
    condition     = aws_wafv2_web_acl.this.description == "WAF for core-prod-edge"
    error_message = "Web ACL description did not use the rendered name."
  }

  assert {
    condition     = aws_wafv2_web_acl.this.visibility_config[0].metric_name == "core-prod-edge-acl-metric"
    error_message = "Web ACL metric name did not match <rendered_name>-acl-metric."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "aws-waf-logs-core-prod-edge"
    error_message = "WAF log group name must be aws-waf-logs-<rendered_name>."
  }

  assert {
    condition     = toset([for r in aws_wafv2_web_acl.this.rule : r.name]) == toset(["core-prod-edge-common", "core-prod-edge-ip_reputation", "core-prod-edge-known_bad"])
    error_message = "Managed rule names must be <rendered_name>-<rule key>."
  }

  assert {
    condition     = alltrue([for r in aws_wafv2_web_acl.this.rule : r.visibility_config[0].metric_name == "${r.name}-metric"])
    error_message = "Each rule metric name must be <rendered_name>-<rule key>-metric."
  }
}

run "verify_name_fallback_when_null" {
  command = plan

  variables {
    name = null
  }

  assert {
    condition     = aws_wafv2_web_acl.this.name == "core-prod-acl" && aws_wafv2_web_acl.this.tags["Name"] == "core-prod-acl"
    error_message = "Web ACL name did not fall back to <application>-<environment>-acl when name is null."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "aws-waf-logs-core-prod"
    error_message = "WAF log group name did not fall back to aws-waf-logs-<application>-<environment> when name is null."
  }
}

run "verify_name_fallback_when_empty" {
  command = plan

  variables {
    name = ""
  }

  assert {
    condition     = aws_wafv2_web_acl.this.name == "core-prod-acl" && aws_cloudwatch_log_group.this.name == "aws-waf-logs-core-prod"
    error_message = "Names did not fall back to <application>-<environment> when name is empty."
  }
}

run "verify_tags" {
  command = plan

  variables {
    tags = {
      CostCenter = "1234"
      Team       = "security"
    }

    ip_sets = {
      blocked = {
        name               = "blocked"
        description        = "Blocked addresses"
        ip_address_version = "IPV4"
        addresses          = ["198.51.100.14/32"]
      }
    }

    regex_pattern_sets = {
      bad_agents = {
        name        = "bad-agents"
        description = "Unwanted user agents"
        regexes     = ["^curl/.*$"]
      }
    }
  }

  assert {
    condition     = aws_wafv2_web_acl.this.tags["Application"] == "core" && aws_wafv2_web_acl.this.tags["Environment"] == "prod" && aws_wafv2_web_acl.this.tags["Name"] == "core-prod-edge-acl"
    error_message = "Web ACL is missing the Application or Environment tags, or its Name was not overridden to the ACL name."
  }

  assert {
    condition     = aws_wafv2_web_acl.this.tags["CostCenter"] == "1234" && aws_wafv2_web_acl.this.tags["Team"] == "security"
    error_message = "Caller tags from var.tags were not preserved on the Web ACL."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.tags["Name"] == "aws-waf-logs-core-prod-edge" && aws_cloudwatch_log_group.this.tags["Application"] == "core" && aws_cloudwatch_log_group.this.tags["CostCenter"] == "1234"
    error_message = "Log group tags must carry governance and caller tags with Name overridden to the log group name."
  }

  assert {
    condition     = aws_wafv2_ip_set.this["blocked"].tags["Name"] == "core-prod-edge-blocked" && aws_wafv2_ip_set.this["blocked"].tags["Environment"] == "prod" && aws_wafv2_ip_set.this["blocked"].tags["Team"] == "security"
    error_message = "IP set tags must carry governance and caller tags with Name overridden to the IP set name."
  }

  assert {
    condition     = aws_wafv2_regex_pattern_set.this["bad_agents"].tags["Name"] == "core-prod-edge-bad-agents" && aws_wafv2_regex_pattern_set.this["bad_agents"].tags["Application"] == "core"
    error_message = "Regex pattern set tags must carry governance tags with Name overridden to the pattern set name."
  }
}

run "verify_security_defaults" {
  command = plan

  assert {
    condition     = aws_wafv2_web_acl.this.scope == "REGIONAL"
    error_message = "Web ACL scope must default to REGIONAL."
  }

  assert {
    condition     = length(aws_wafv2_web_acl.this.default_action[0].allow) == 1 && length(aws_wafv2_web_acl.this.default_action[0].block) == 0
    error_message = "Web ACL default action must default to allow."
  }

  assert {
    condition = toset([
      for r in aws_wafv2_web_acl.this.rule : r.statement[0].managed_rule_group_statement[0].name
    ]) == toset(["AWSManagedRulesCommonRuleSet", "AWSManagedRulesAmazonIpReputationList", "AWSManagedRulesKnownBadInputsRuleSet"])
    error_message = "Web ACL must ship the Common, Amazon IP Reputation and Known Bad Inputs managed rule groups."
  }

  assert {
    condition = alltrue([
      for r in aws_wafv2_web_acl.this.rule :
      r.statement[0].managed_rule_group_statement[0].vendor_name == "AWS" &&
      length(r.override_action[0].none) == 1 && length(r.override_action[0].count) == 0
    ])
    error_message = "Default managed rule groups must be AWS-vended and enforced (override_action none), not counted."
  }

  assert {
    condition = {
      for r in aws_wafv2_web_acl.this.rule : r.name => r.priority
      } == {
      "core-prod-edge-common"        = 10
      "core-prod-edge-ip_reputation" = 11
      "core-prod-edge-known_bad"     = 12
    }
    error_message = "Managed rules must take priorities from 10 in key order."
  }

  assert {
    condition     = aws_wafv2_web_acl.this.visibility_config[0].cloudwatch_metrics_enabled == true && aws_wafv2_web_acl.this.visibility_config[0].sampled_requests_enabled == true
    error_message = "Web ACL must publish CloudWatch metrics and sampled requests."
  }

  assert {
    condition     = alltrue([for r in aws_wafv2_web_acl.this.rule : r.visibility_config[0].cloudwatch_metrics_enabled && r.visibility_config[0].sampled_requests_enabled])
    error_message = "Every rule must publish CloudWatch metrics and sampled requests."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.kms_key_id == "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
    error_message = "WAF log group must be encrypted with var.kms_key_arn when cloudwatch_logs.kms_key_arn is not set."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 30 && aws_cloudwatch_log_group.this.log_group_class == "STANDARD"
    error_message = "WAF log group must default to 30-day retention in the STANDARD class."
  }

  assert {
    condition     = startswith(aws_cloudwatch_log_group.this.name, "aws-waf-logs-")
    error_message = "WAF log group name must start with aws-waf-logs-, which WAF logging requires."
  }

  assert {
    condition     = length(aws_wafv2_web_acl_logging_configuration.this.redacted_fields) == 0
    error_message = "No log fields must be redacted by default."
  }
}

run "verify_logging_wiring" {
  command = apply

  assert {
    condition     = aws_wafv2_web_acl_logging_configuration.this.resource_arn == aws_wafv2_web_acl.this.arn
    error_message = "Logging configuration must be attached to the module's Web ACL."
  }

  assert {
    condition     = aws_wafv2_web_acl_logging_configuration.this.log_destination_configs == toset([aws_cloudwatch_log_group.this.arn])
    error_message = "WAF logs must be delivered only to the module's KMS-encrypted log group."
  }

  assert {
    condition     = output.web_acl_arn == aws_wafv2_web_acl.this.arn && output.web_acl_id == aws_wafv2_web_acl.this.id && output.web_acl_capacity == aws_wafv2_web_acl.this.capacity
    error_message = "Outputs must expose the Web ACL ARN, id and capacity."
  }
}

run "verify_parameter_defaults" {
  command = plan

  assert {
    condition     = length(aws_wafv2_web_acl.this.rule) == 3
    error_message = "Only the three default managed rules must be present by default."
  }

  assert {
    condition     = length(aws_wafv2_api_key.this) == 0
    error_message = "No WAF API key must be created when token_domains is empty."
  }

  assert {
    condition     = length(aws_wafv2_ip_set.this) == 0 && length(aws_wafv2_regex_pattern_set.this) == 0
    error_message = "No IP sets or regex pattern sets must be created by default."
  }

  assert {
    condition     = length(aws_wafv2_web_acl_association.this) == 0
    error_message = "No Web ACL associations must be created by default."
  }
}

run "verify_parameter_overrides" {
  command = plan

  variables {
    scope          = "CLOUDFRONT"
    default_action = "block"
    token_domains  = ["app.example.com", "www.example.com"]

    managed_rules = {
      common = {
        name            = "AWSManagedRulesCommonRuleSet"
        vendor_name     = "AWS"
        override_action = "none"
      }
      sqli = {
        name            = "AWSManagedRulesSQLiRuleSet"
        vendor_name     = "AWS"
        override_action = "count"
      }
    }

    cloudwatch_logs = {
      retention_in_days = 90
      kms_key_arn       = "arn:aws:kms:us-west-2:123456789012:key/abcdefab-1234-1234-1234-abcdefabcdef"
    }

    redacted_fields = {
      headers      = ["Authorization", "Cookie"]
      query_string = true
      uri_path     = true
    }
  }

  assert {
    condition     = aws_wafv2_web_acl.this.scope == "CLOUDFRONT"
    error_message = "scope override did not flow through to the Web ACL."
  }

  assert {
    condition     = length(aws_wafv2_web_acl.this.default_action[0].block) == 1 && length(aws_wafv2_web_acl.this.default_action[0].allow) == 0
    error_message = "default_action = block did not flow through to the Web ACL."
  }

  assert {
    condition     = length(aws_wafv2_api_key.this) == 1 && aws_wafv2_api_key.this[0].scope == "CLOUDFRONT" && aws_wafv2_api_key.this[0].token_domains == toset(["app.example.com", "www.example.com"])
    error_message = "token_domains must create one API key in the Web ACL scope."
  }

  assert {
    condition = {
      for r in aws_wafv2_web_acl.this.rule : r.statement[0].managed_rule_group_statement[0].name => {
        priority = r.priority
        count    = length(r.override_action[0].count)
        none     = length(r.override_action[0].none)
      }
      } == {
      AWSManagedRulesCommonRuleSet = { priority = 10, count = 0, none = 1 }
      AWSManagedRulesSQLiRuleSet   = { priority = 11, count = 1, none = 0 }
    }
    error_message = "managed_rules override must replace the default set, with each rule's override_action and priority."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 90 && aws_cloudwatch_log_group.this.kms_key_id == "arn:aws:kms:us-west-2:123456789012:key/abcdefab-1234-1234-1234-abcdefabcdef"
    error_message = "cloudwatch_logs retention and KMS key overrides did not flow through."
  }

  assert {
    condition     = toset(flatten([for f in aws_wafv2_web_acl_logging_configuration.this.redacted_fields : [for h in f.single_header : h.name]])) == toset(["authorization", "cookie"])
    error_message = "Redacted headers must be logged as lowercase single_header fields."
  }

  assert {
    condition = (
      length([for f in aws_wafv2_web_acl_logging_configuration.this.redacted_fields : f if length(f.query_string) == 1]) == 1 &&
      length([for f in aws_wafv2_web_acl_logging_configuration.this.redacted_fields : f if length(f.uri_path) == 1]) == 1 &&
      length(aws_wafv2_web_acl_logging_configuration.this.redacted_fields) == 4
    )
    error_message = "query_string and uri_path redaction must each add one redacted field."
  }
}

run "verify_optional_rules_and_associations" {
  command = apply

  variables {
    ip_sets = {
      blocked = {
        name               = "blocked"
        description        = "Blocked addresses"
        ip_address_version = "IPV4"
        addresses          = ["198.51.100.14/32", "203.0.113.0/24"]
      }
    }

    regex_pattern_sets = {
      bad_agents = {
        name        = "bad-agents"
        description = "Unwanted user agents"
        regexes     = ["^curl/.*$", "^python-requests/.*$"]
      }
    }

    rate_limit_rules = {
      per_ip = {
        name   = "per-ip"
        limit  = 2000
        action = "block"
      }
      per_ip_challenge = {
        name   = "per-ip-challenge"
        limit  = 500
        action = "captcha"
      }
    }

    ip_block_rules = {
      blocked_ips = {
        name       = "blocked-ips"
        ip_set_key = "blocked"
        action     = "block"
      }
    }

    geo_block_rules = {
      embargoed = {
        name      = "embargoed"
        action    = "count"
        countries = ["KP", "IR"]
      }
    }

    association_arns = [
      "arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/core-prod-web/0123456789abcdef",
    ]
  }

  assert {
    condition     = length(aws_wafv2_web_acl.this.rule) == 7
    error_message = "Web ACL must hold the 3 managed rules plus every rate limit, IP block and geo rule."
  }

  assert {
    condition = {
      for r in aws_wafv2_web_acl.this.rule : r.name => r.priority
      } == {
      "core-prod-edge-common"           = 10
      "core-prod-edge-ip_reputation"    = 11
      "core-prod-edge-known_bad"        = 12
      "core-prod-edge-per_ip"           = 100
      "core-prod-edge-per_ip_challenge" = 101
      "core-prod-edge-blocked_ips"      = 200
      "core-prod-edge-embargoed"        = 300
    }
    error_message = "Rule priorities must be 10+ for managed, 100+ for rate limit, 200+ for IP block and 300+ for geo rules."
  }

  assert {
    condition = anytrue([
      for r in aws_wafv2_web_acl.this.rule :
      r.name == "core-prod-edge-per_ip" &&
      r.statement[0].rate_based_statement[0].limit == 2000 &&
      r.statement[0].rate_based_statement[0].aggregate_key_type == "IP" &&
      length(r.action[0].block) == 1
    ])
    error_message = "Rate limit rule must be an IP rate-based statement with the configured limit and block action."
  }

  assert {
    condition = anytrue([
      for r in aws_wafv2_web_acl.this.rule :
      r.name == "core-prod-edge-per_ip_challenge" && length(r.action[0].captcha) == 1 && length(r.action[0].block) == 0
    ])
    error_message = "Rate limit rule with action captcha must use the CAPTCHA action."
  }

  assert {
    condition = anytrue([
      for r in aws_wafv2_web_acl.this.rule :
      r.name == "core-prod-edge-blocked_ips" &&
      r.statement[0].ip_set_reference_statement[0].arn == aws_wafv2_ip_set.this["blocked"].arn &&
      length(r.action[0].block) == 1
    ])
    error_message = "IP block rule must reference the module's IP set and block."
  }

  assert {
    condition = anytrue([
      for r in aws_wafv2_web_acl.this.rule :
      r.name == "core-prod-edge-embargoed" &&
      r.statement[0].geo_match_statement[0].country_codes == tolist(["KP", "IR"]) &&
      length(r.action[0].count) == 1
    ])
    error_message = "Geo rule must match the configured countries with the configured action."
  }

  assert {
    condition = (
      aws_wafv2_ip_set.this["blocked"].name == "core-prod-edge-blocked" &&
      aws_wafv2_ip_set.this["blocked"].scope == "REGIONAL" &&
      aws_wafv2_ip_set.this["blocked"].ip_address_version == "IPV4" &&
      aws_wafv2_ip_set.this["blocked"].addresses == toset(["198.51.100.14/32", "203.0.113.0/24"])
    )
    error_message = "IP set name, scope, version or addresses did not flow through."
  }

  assert {
    condition = (
      aws_wafv2_regex_pattern_set.this["bad_agents"].name == "core-prod-edge-bad-agents" &&
      aws_wafv2_regex_pattern_set.this["bad_agents"].scope == "REGIONAL" &&
      toset([for r in aws_wafv2_regex_pattern_set.this["bad_agents"].regular_expression : r.regex_string]) == toset(["^curl/.*$", "^python-requests/.*$"])
    )
    error_message = "Regex pattern set name, scope or expressions did not flow through."
  }

  assert {
    condition = (
      length(aws_wafv2_web_acl_association.this) == 1 &&
      aws_wafv2_web_acl_association.this[0].resource_arn == "arn:aws:elasticloadbalancing:us-west-2:123456789012:loadbalancer/app/core-prod-web/0123456789abcdef" &&
      aws_wafv2_web_acl_association.this[0].web_acl_arn == aws_wafv2_web_acl.this.arn
    )
    error_message = "One association must be created per association ARN, pointing at the module's Web ACL."
  }
}

run "verify_invalid_environment_fails" {
  command = plan

  variables {
    environment = "INVALID_UPPERCASE"
  }

  expect_failures = [var.environment]
}
