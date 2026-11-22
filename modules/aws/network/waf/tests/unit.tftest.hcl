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
    condition     = length(module.log_group) == 1 && module.log_group[0].name == "aws-waf-logs-core-prod" && module.log_group[0].retention_in_days == 365 && module.log_group[0].kms_key_arn == null && output.kms_key_arn == null
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
    condition     = aws_wafv2_web_acl.this.name == "core-prod-edge" && module.log_group[0].name == "aws-waf-logs-core-prod-edge" && length(aws_wafv2_web_acl.this.default_action[0].block) == 1
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
    condition     = output.arn == "arn:aws:wafv2:eu-west-1:123456789012:regional/webacl/core-prod/a1b2c3d4-5678-90ab-cdef-EXAMPLE11111" && aws_wafv2_web_acl_logging_configuration.this.resource_arn == output.arn && aws_wafv2_web_acl_logging_configuration.this.log_destination_configs == toset([module.log_group[0].arn])
    error_message = "Logging is configured for the web ACL to its log group."
  }
}

run "module_key_is_planned_safely" {
  command = plan

  variables {
    kms = { create = true }
  }

  assert {
    condition     = module.encryption.created && module.log_group[0].name == "aws-waf-logs-core-prod"
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
    condition     = module.log_group[0].kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && output.kms_key_arn == module.log_group[0].kms_key_arn
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
    condition     = module.log_group[0].kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && module.log_group[0].retention_in_days == 731
    error_message = "A key ID becomes the key ARN; retention follows cloudwatch_logs."
  }

  assert {
    condition     = length(aws_wafv2_web_acl_logging_configuration.this.redacted_fields) == 2
    error_message = "Redaction follows redacted_fields."
  }
}

run "logs_to_s3" {
  command   = apply
  state_key = "s3"

  variables {
    logging = { destination = "s3", s3_bucket_arn = "arn:aws:s3:::aws-waf-logs-core-prod" }
  }

  assert {
    condition     = length(module.log_group) == 0 && output.log_group_name == null && output.log_group_arn == null
    error_message = "The s3 destination creates no log group."
  }

  assert {
    condition     = aws_wafv2_web_acl_logging_configuration.this.log_destination_configs == toset(["arn:aws:s3:::aws-waf-logs-core-prod"]) && aws_wafv2_web_acl_logging_configuration.this.resource_arn == output.arn
    error_message = "The web ACL logs to the aws-waf-logs- bucket (WAF.11)."
  }

  assert {
    condition     = [for f in aws_wafv2_web_acl_logging_configuration.this.redacted_fields : f.single_header[0].name] == ["authorization", "cookie"]
    error_message = "Redaction applies to the s3 destination too."
  }
}

run "logs_to_s3_plan_safely" {
  command   = plan
  state_key = "s3_plan"

  variables {
    scope   = "CLOUDFRONT"
    logging = { destination = "s3", s3_bucket_arn = "arn:aws:s3:::aws-waf-logs-core-prod" }
  }

  assert {
    condition     = length(module.log_group) == 0 && !module.encryption.created && aws_wafv2_web_acl_logging_configuration.this.region == "us-east-1" && aws_wafv2_web_acl_logging_configuration.this.log_destination_configs == toset(["arn:aws:s3:::aws-waf-logs-core-prod"])
    error_message = "The s3 destination plans from the literal destination."
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

run "rejects_log_bucket_without_waf_prefix" {
  command = plan

  variables {
    logging = { destination = "s3", s3_bucket_arn = "arn:aws:s3:::core-prod-logs-123456789012-eu-west-1" }
  }

  expect_failures = [var.logging]
}

run "rejects_kms_with_s3_logging" {
  command = plan

  variables {
    kms     = { create = true }
    logging = { destination = "s3", s3_bucket_arn = "arn:aws:s3:::aws-waf-logs-core-prod" }
  }

  expect_failures = [var.logging]
}
