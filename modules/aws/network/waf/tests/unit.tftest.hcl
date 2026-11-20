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

  mock_resource "aws_wafv2_web_acl" {
    defaults = {
      arn = "arn:aws:wafv2:eu-west-1:123456789012:regional/webacl/core-prod/a1b2c3d4-5678-90ab-cdef-EXAMPLE11111"
    }
  }

  mock_resource "aws_wafv2_ip_set" {
    defaults = {
      arn = "arn:aws:wafv2:eu-west-1:123456789012:regional/ipset/core-prod-blocked/a1b2c3d4-5678-90ab-cdef-EXAMPLE22222"
    }
  }

  mock_resource "aws_wafv2_regex_pattern_set" {
    defaults = {
      arn = "arn:aws:wafv2:eu-west-1:123456789012:regional/regexpatternset/core-prod-admin/a1b2c3d4-5678-90ab-cdef-EXAMPLE33333"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-west-1:123456789012:log-group:aws-waf-logs-core-prod"
    }
  }
}

variables {
  application = "core"
  environment = "prod"
  tags        = { Team = "security" }
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = aws_wafv2_web_acl.this.name == "core-prod" && aws_wafv2_web_acl.this.scope == "REGIONAL" && length(aws_wafv2_web_acl.this.default_action[0].allow) == 1
    error_message = "A REGIONAL web ACL named <application>-<environment> that allows unmatched requests."
  }

  assert {
    condition     = toset([for r in aws_wafv2_web_acl.this.rule : r.name]) == toset(["managed-common", "managed-ip_reputation", "managed-known_bad"]) && toset([for r in aws_wafv2_web_acl.this.rule : r.priority]) == toset([10, 11, 12])
    error_message = "Three AWS managed rule groups by default (WAF.10)."
  }

  assert {
    condition     = alltrue([for r in aws_wafv2_web_acl.this.rule : r.visibility_config[0].cloudwatch_metrics_enabled && r.visibility_config[0].sampled_requests_enabled]) && aws_wafv2_web_acl.this.visibility_config[0].metric_name == "core-prod"
    error_message = "Metrics and sampled requests on the web ACL and every rule (WAF.12)."
  }

  assert {
    condition     = module.log_group.name == "aws-waf-logs-core-prod" && module.log_group.retention_in_days == 365 && module.log_group.kms_key_arn == null && output.kms_key_arn == null
    error_message = "Logs go to aws-waf-logs-<base>, kept 365 days with service encryption by default (WAF.11)."
  }

  assert {
    condition     = [for f in aws_wafv2_web_acl_logging_configuration.this.redacted_fields : f.single_header[0].name] == ["authorization", "cookie"]
    error_message = "Authorization and cookie headers are redacted by default."
  }

  assert {
    condition     = output.rule_metric_names == { "managed-common" = "core-prod-managed-common", "managed-ip_reputation" = "core-prod-managed-ip_reputation", "managed-known_bad" = "core-prod-managed-known_bad" } && output.metric_name == "core-prod"
    error_message = "Metric names are exported for alarms."
  }

  assert {
    condition     = aws_wafv2_web_acl.this.tags["Name"] == "core-prod" && aws_wafv2_web_acl.this.tags["Team"] == "security" && aws_wafv2_web_acl.this.tags["ManagedBy"] == "Terraform"
    error_message = "Caller and governance tags must be applied."
  }
}

run "cloudfront_scope" {
  command = plan

  variables {
    name           = "edge"
    scope          = "CLOUDFRONT"
    default_action = "block"
  }

  assert {
    condition     = aws_wafv2_web_acl.this.scope == "CLOUDFRONT" && aws_wafv2_web_acl.this.region == "us-east-1" && aws_wafv2_web_acl_logging_configuration.this.region == "us-east-1"
    error_message = "CLOUDFRONT scope creates the web ACL and its logging in us-east-1."
  }

  assert {
    condition     = aws_wafv2_web_acl.this.name == "core-prod-edge" && module.log_group.name == "aws-waf-logs-core-prod-edge" && length(aws_wafv2_web_acl.this.default_action[0].block) == 1
    error_message = "Names follow <application>-<environment>-<name>."
  }
}

run "custom_rules" {
  command = apply

  variables {
    managed_rules      = { common = { name = "AWSManagedRulesCommonRuleSet", override_action = "count", version = "Version_1.10" } }
    rate_limit_rules   = { api = { limit = 2000 }, login = { limit = 100, action = "captcha" } }
    ip_sets            = { blocked = { addresses = ["198.51.100.0/24"] } }
    ip_block_rules     = { blocked = { ip_set_key = "blocked" } }
    geo_block_rules    = { sanctioned = { countries = ["KP"] } }
    regex_pattern_sets = { admin = { regexes = ["^/admin"] } }
    regex_match_rules  = { admin = { regex_pattern_set_key = "admin", field_to_match = "single_header", header_name = "X-Path" } }
    token_domains      = ["example.com"]
  }

  assert {
    condition     = { for r in aws_wafv2_web_acl.this.rule : r.name => r.priority } == { "managed-common" = 10, "rate-api" = 100, "rate-login" = 101, "ip-blocked" = 200, "geo-sanctioned" = 300, "regex-admin" = 400 }
    error_message = "Rules get prefixed names and priority bands per type."
  }

  assert {
    condition     = aws_wafv2_ip_set.this["blocked"].name == "core-prod-blocked" && aws_wafv2_ip_set.this["blocked"].ip_address_version == "IPV4" && aws_wafv2_regex_pattern_set.this["admin"].name == "core-prod-admin"
    error_message = "IP and regex sets are named <base>-<key>."
  }

  assert {
    condition     = one([for r in aws_wafv2_web_acl.this.rule : r.statement[0].ip_set_reference_statement[0].arn if r.name == "ip-blocked"]) == aws_wafv2_ip_set.this["blocked"].arn && one([for r in aws_wafv2_web_acl.this.rule : r.statement[0].regex_pattern_set_reference_statement[0].field_to_match[0].single_header[0].name if r.name == "regex-admin"]) == "x-path"
    error_message = "Rules reference their sets; header names are lower case."
  }

  assert {
    condition     = toset(aws_wafv2_web_acl.this.token_domains) == toset(["example.com"]) && length(output.rule_metric_names) == 6
    error_message = "Token domains and every rule metric name are set."
  }

  assert {
    condition     = output.arn == "arn:aws:wafv2:eu-west-1:123456789012:regional/webacl/core-prod/a1b2c3d4-5678-90ab-cdef-EXAMPLE11111" && aws_wafv2_web_acl_logging_configuration.this.resource_arn == output.arn && aws_wafv2_web_acl_logging_configuration.this.log_destination_configs == toset([module.log_group.arn])
    error_message = "Logging is configured for the web ACL to its log group."
  }
}

run "module_key_is_planned_safely" {
  command = plan

  variables {
    kms = { create = true }
  }

  assert {
    condition     = module.encryption.created && module.log_group.name == "aws-waf-logs-core-prod"
    error_message = "kms.create must plan without knowing the key ARN."
  }
}

run "module_key_encrypts_logs" {
  command   = apply
  state_key = "kms"

  variables {
    kms = { create = true }
  }

  assert {
    condition     = module.log_group.kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && output.kms_key_arn == module.log_group.kms_key_arn
    error_message = "The module key must encrypt the log group."
  }
}

run "caller_key_and_redaction" {
  command = plan

  variables {
    kms             = { key_id = "11111111-2222-3333-4444-555555555555" }
    cloudwatch_logs = { retention_in_days = 731 }
    redacted_fields = { headers = [], query_string = true, uri_path = true }
  }

  assert {
    condition     = module.log_group.kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && module.log_group.retention_in_days == 731
    error_message = "A key ID becomes the key ARN; retention follows cloudwatch_logs."
  }

  assert {
    condition     = length(aws_wafv2_web_acl_logging_configuration.this.redacted_fields) == 2
    error_message = "Redaction follows redacted_fields."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Edge_ACL"
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

run "rejects_invalid_scope" {
  command = plan

  variables {
    scope = "GLOBAL"
  }

  expect_failures = [var.scope]
}

run "rejects_invalid_default_action" {
  command = plan

  variables {
    default_action = "count"
  }

  expect_failures = [var.default_action]
}

run "rejects_invalid_override_action" {
  command = plan

  variables {
    managed_rules = { common = { name = "AWSManagedRulesCommonRuleSet", override_action = "block" } }
  }

  expect_failures = [var.managed_rules]
}

run "rejects_invalid_rate_limit" {
  command = plan

  variables {
    rate_limit_rules = { api = { limit = 5 } }
  }

  expect_failures = [var.rate_limit_rules]
}

run "rejects_invalid_ip_version" {
  command = plan

  variables {
    ip_sets = { blocked = { addresses = ["198.51.100.0/24"], ip_address_version = "IPV5" } }
  }

  expect_failures = [var.ip_sets]
}

run "rejects_unknown_ip_set" {
  command = plan

  variables {
    ip_block_rules = { blocked = { ip_set_key = "missing" } }
  }

  expect_failures = [var.ip_block_rules]
}

run "rejects_geo_rule_without_countries" {
  command = plan

  variables {
    geo_block_rules = { none = { countries = [] } }
  }

  expect_failures = [var.geo_block_rules]
}

run "rejects_unknown_regex_set" {
  command = plan

  variables {
    regex_match_rules = { admin = { regex_pattern_set_key = "missing" } }
  }

  expect_failures = [var.regex_match_rules]
}

run "rejects_header_match_without_name" {
  command = plan

  variables {
    regex_pattern_sets = { admin = { regexes = ["^/admin"] } }
    regex_match_rules  = { admin = { regex_pattern_set_key = "admin", field_to_match = "single_header" } }
  }

  expect_failures = [var.regex_match_rules]
}

run "rejects_create_and_key_id" {
  command = plan

  variables {
    kms = { create = true, key_id = "11111111-2222-3333-4444-555555555555" }
  }

  expect_failures = [var.kms]
}

run "rejects_invalid_key_id" {
  command = plan

  variables {
    kms = { key_id = "alias/waf" }
  }

  expect_failures = [var.kms]
}

run "rejects_web_acl_without_rules" {
  command = plan

  variables {
    managed_rules = {}
  }

  expect_failures = [var.managed_rules]
}

run "alarms_by_default" {
  command = plan

  assert {
    condition     = length(module.alarms) == 1 && length(output.alarm_names) == 0
    error_message = "Without a blocked_requests threshold, no alarm is created."
  }
}

run "alarms_off" {
  command = plan

  variables {
    alarms = { enabled = false, overrides = { blocked_requests = { threshold = 1000 } } }
  }

  assert {
    condition     = length(module.alarms) == 0 && length(output.alarm_names) == 0 && length(output.alarm_arns) == 0
    error_message = "alarms.enabled = false creates no alarms."
  }
}

run "alarms_tuned_and_routed" {
  command = apply

  variables {
    alarms = {
      topic_arns = {
        critical = "arn:aws:sns:eu-west-1:123456789012:platform-prod-critical"
        warning  = "arn:aws:sns:eu-west-1:123456789012:platform-prod-warning"
        info     = "arn:aws:sns:eu-west-1:123456789012:platform-prod-info"
      }
      overrides = {
        blocked_requests = { threshold = 1000 }
      }
    }
  }

  assert {
    condition     = sort(keys(output.alarm_arns)) == tolist(["waf-acl-blocked-requests"]) && alltrue([for n in values(output.alarm_names) : startswith(n, "core-prod-waf-acl-")])
    error_message = "A blocked_requests threshold turns the alarm on; names start with the module base name."
  }

  assert {
    condition     = module.alarms[0].alarm_settings["waf-acl-blocked-requests"].threshold == 1000 && module.alarms[0].alarm_settings["waf-acl-blocked-requests"].evaluation_periods == 1 && module.alarms[0].alarm_settings["waf-acl-blocked-requests"].period == 300
    error_message = "The threshold is the caller's; the rest keep the preset defaults."
  }

  assert {
    condition     = module.alarms[0].alarm_routes["waf-acl-blocked-requests"].topic_arn == "arn:aws:sns:eu-west-1:123456789012:platform-prod-warning" && module.alarms[0].alarm_routes["waf-acl-blocked-requests"].region == "eu-west-1"
    error_message = "A REGIONAL web ACL alarm notifies the provider Region topic for its severity."
  }
}

run "alarms_cloudfront_scope_route_to_us_east_1" {
  command = plan

  variables {
    scope = "CLOUDFRONT"
    alarms = {
      topic_arns = {
        critical = "arn:aws:sns:us-east-1:123456789012:platform-prod-critical"
        warning  = "arn:aws:sns:us-east-1:123456789012:platform-prod-warning"
        info     = "arn:aws:sns:us-east-1:123456789012:platform-prod-info"
      }
      overrides = {
        blocked_requests = { threshold = 500, severity = "critical" }
      }
    }
  }

  assert {
    condition     = module.alarms[0].alarm_routes["waf-acl-blocked-requests"].region == "us-east-1" && module.alarms[0].alarm_routes["waf-acl-blocked-requests"].topic_arn == "arn:aws:sns:us-east-1:123456789012:platform-prod-critical"
    error_message = "A CLOUDFRONT web ACL alarm lives in us-east-1 and notifies the us-east-1 topic."
  }
}

run "alarms_plan_with_unknown_arns" {
  command   = plan
  state_key = "alarms_unknown_arns"

  variables {
    kms    = { create = true }
    alarms = { overrides = { blocked_requests = { threshold = 1000 } } }
  }

  assert {
    condition     = length(module.alarms) == 1 && length(output.alarm_names) == 1
    error_message = "Alarm keys and names must be known at plan with a module key."
  }
}

run "rejects_invalid_alarm_topic" {
  command = plan

  variables {
    alarms = { topic_arns = { critical = "arn:aws:sqs:eu-west-1:123456789012:core-prod-critical" } }
  }

  expect_failures = [var.alarms]
}
