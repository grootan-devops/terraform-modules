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

  mock_resource "aws_route53_zone" {
    defaults = {
      zone_id      = "Z0123456789ABCDEFGHIJ"
      arn          = "arn:aws:route53:::hostedzone/Z0123456789ABCDEFGHIJ"
      name_servers = ["ns-1.awsdns-01.org", "ns-2.awsdns-02.co.uk", "ns-3.awsdns-03.com", "ns-4.awsdns-04.net"]
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/route53/example.com"
    }
  }

  mock_resource "aws_route53_key_signing_key" {
    defaults = {
      ds_record = "12345 13 2 ABCDEF0123456789"
    }
  }

  mock_resource "aws_route53_health_check" {
    defaults = {
      id = "abcdef12-3456-7890-abcd-ef1234567890"
    }
  }
}

variables {
  application = "core"
  environment = "prod"
  zone_name   = "example.com"
  tags        = { Team = "dns" }
}

run "public_zone_defaults" {
  command = plan

  assert {
    condition     = aws_route53_zone.this.name == "example.com" && !aws_route53_zone.this.force_destroy && length(aws_route53_zone.this.vpc) == 0 && aws_route53_zone.this.comment == "core-prod zone"
    error_message = "A public zone that Terraform never force-destroys."
  }

  assert {
    condition     = module.log_group[0].name == "/aws/route53/example.com" && module.log_group[0].retention_in_days == 365 && module.log_group[0].kms_key_arn == null && length(aws_route53_query_log.this) == 1
    error_message = "Public zones log DNS queries to a 365-day log group (Route53.2)."
  }

  assert {
    condition     = aws_cloudwatch_log_resource_policy.query_logging[0].region == "us-east-1" && aws_cloudwatch_log_resource_policy.query_logging[0].policy_name == "core-prod-route53-example-com"
    error_message = "The query log resource policy is created in us-east-1 per zone."
  }

  assert {
    condition     = length(module.dnssec_key) == 1 && aws_route53_key_signing_key.this[0].status == "ACTIVE" && aws_route53_key_signing_key.this[0].name == "core_prod" && aws_route53_hosted_zone_dnssec.this[0].signing_status == "SIGNING"
    error_message = "Public zones are DNSSEC-signed by default."
  }

  assert {
    condition     = [for s in jsondecode(module.dnssec_key[0].policy_json).Statement : s.Sid] == ["EnableIAMPolicies", "AllowRoute53DNSSECService", "AllowRoute53DNSSECServiceToCreateGrant"] && jsondecode(module.dnssec_key[0].policy_json).Statement[1].Principal.Service == ["dnssec-route53.amazonaws.com"] && jsondecode(module.dnssec_key[0].policy_json).Statement[1].Condition.StringEquals["aws:SourceAccount"] == ["123456789012"] && jsondecode(module.dnssec_key[0].policy_json).Statement[2].Condition.Bool["kms:GrantIsForAWSResource"] == ["true"]
    error_message = "The DNSSEC key policy grants dnssec-route53.amazonaws.com as AWS documents."
  }

  assert {
    condition     = aws_route53_zone.this.tags["Name"] == "example.com" && aws_route53_zone.this.tags["Team"] == "dns" && aws_route53_zone.this.tags["ManagedBy"] == "Terraform"
    error_message = "Caller and governance tags must be applied."
  }
}

run "query_logging_and_dnssec_wiring" {
  command = apply

  assert {
    condition     = jsondecode(aws_cloudwatch_log_resource_policy.query_logging[0].policy_document).Statement[0].Principal.Service == "route53.amazonaws.com" && jsondecode(aws_cloudwatch_log_resource_policy.query_logging[0].policy_document).Statement[0].Resource == "arn:aws:logs:us-east-1:123456789012:log-group:/aws/route53/example.com:*" && jsondecode(aws_cloudwatch_log_resource_policy.query_logging[0].policy_document).Statement[0].Condition.ArnLike["aws:SourceArn"] == "arn:aws:route53:::hostedzone/Z0123456789ABCDEFGHIJ"
    error_message = "Route 53 may write only this zone's queries to its log group."
  }

  assert {
    condition     = aws_route53_query_log.this[0].cloudwatch_log_group_arn == module.log_group[0].arn && aws_route53_query_log.this[0].zone_id == "Z0123456789ABCDEFGHIJ"
    error_message = "The query log writes to the module log group."
  }

  assert {
    condition     = aws_route53_key_signing_key.this[0].key_management_service_arn == module.dnssec_key[0].arn && output.ds_record == "12345 13 2 ABCDEF0123456789"
    error_message = "The key-signing key uses the module key; the DS record is exported."
  }

  assert {
    condition     = output.zone_id == "Z0123456789ABCDEFGHIJ" && length(output.name_servers) == 4 && output.arn == "arn:aws:route53:::hostedzone/Z0123456789ABCDEFGHIJ"
    error_message = "Zone outputs are exported."
  }
}

run "private_zone" {
  command = plan

  variables {
    name    = "internal"
    vpc_ids = ["vpc-0a1b2c3d4e5f67890", "vpc-0fedcba9876543210"]
  }

  assert {
    condition     = length(aws_route53_zone.this.vpc) == 2 && length(module.log_group) == 0 && length(aws_route53_query_log.this) == 0 && length(module.dnssec_key) == 0 && length(aws_route53_hosted_zone_dnssec.this) == 0
    error_message = "Private zones attach VPCs and have no query logging or DNSSEC."
  }
}

run "records_and_health_checks" {
  command   = apply
  state_key = "records"

  variables {
    health_checks = { primary = { fqdn = "primary.example.com", resource_path = "/health" } }
    records = {
      apex    = { type = "A", alias = { name = "core-prod-1234567890.eu-west-1.elb.amazonaws.com", zone_id = "Z32O12XQLNTSW2", evaluate_target_health = true } }
      mail    = { type = "MX", records = ["10 mail.example.com"], ttl = 3600 }
      primary = { name = "app", type = "CNAME", records = ["primary.example.com"], ttl = 60, set_identifier = "primary", failover = "PRIMARY", health_check = "primary" }
    }
  }

  assert {
    condition     = aws_route53_record.this["apex"].name == "example.com" && aws_route53_record.this["apex"].ttl == null && aws_route53_record.this["apex"].alias[0].evaluate_target_health && aws_route53_record.this["mail"].ttl == 3600
    error_message = "Alias records have no TTL; the apex is the zone name."
  }

  assert {
    condition     = aws_route53_record.this["primary"].name == "app.example.com" && aws_route53_record.this["primary"].failover_routing_policy[0].type == "PRIMARY" && aws_route53_record.this["primary"].health_check_id == aws_route53_health_check.this["primary"].id
    error_message = "Failover records use their health check."
  }

  assert {
    condition     = aws_route53_health_check.this["primary"].port == 443 && aws_route53_health_check.this["primary"].enable_sni && aws_route53_health_check.this["primary"].tags["Name"] == "core-prod-primary" && aws_route53_health_check.this["primary"].tags["ManagedBy"] == "Terraform"
    error_message = "HTTPS health checks use 443 with SNI and are tagged (Route53.1)."
  }

  assert {
    condition     = keys(output.record_fqdns) == ["apex", "mail", "primary"] && output.health_check_ids["primary"] == "abcdef12-3456-7890-abcd-ef1234567890"
    error_message = "Record FQDNs and health check IDs are exported."
  }
}

run "module_key_is_planned_safely" {
  command = plan

  variables {
    kms = { create = true }
  }

  assert {
    condition     = module.encryption.created && length(module.log_group) == 1
    error_message = "kms.create must plan without knowing the key ARN."
  }
}

run "module_key_encrypts_query_logs" {
  command   = apply
  state_key = "kms"

  variables {
    kms = { create = true }
  }

  assert {
    condition     = module.log_group[0].kms_key_arn == "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555" && output.kms_key_arn == module.log_group[0].kms_key_arn
    error_message = "The us-east-1 module key must encrypt the query log group."
  }
}

run "caller_key_id" {
  command = plan

  variables {
    kms = { key_id = "11111111-2222-3333-4444-555555555555" }
  }

  assert {
    condition     = module.log_group[0].kms_key_arn == "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    error_message = "A key ID becomes a us-east-1 key ARN."
  }
}

run "dnssec_off" {
  command = plan

  variables {
    dnssec = { enabled = false }
  }

  assert {
    condition     = length(module.dnssec_key) + length(aws_route53_key_signing_key.this) + length(aws_route53_hosted_zone_dnssec.this) == 0 && output.ds_record == null && length(aws_route53_query_log.this) == 1
    error_message = "dnssec.enabled = false turns off signing only."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Public_Zone"
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

run "rejects_invalid_zone_name" {
  command = plan

  variables {
    zone_name = "Example.com."
  }

  expect_failures = [var.zone_name]
}

run "rejects_invalid_record_type" {
  command = plan

  variables {
    records = { x = { type = "ALIAS", records = ["1.2.3.4"] } }
  }

  expect_failures = [var.records]
}

run "rejects_record_without_values" {
  command = plan

  variables {
    records = { x = { type = "A" } }
  }

  expect_failures = [var.records]
}

run "rejects_failover_without_identifier" {
  command = plan

  variables {
    records = { x = { type = "A", records = ["192.0.2.10"], failover = "PRIMARY" } }
  }

  expect_failures = [var.records]
}

run "rejects_unknown_health_check" {
  command = plan

  variables {
    records = { x = { type = "A", records = ["192.0.2.10"], health_check = "missing" } }
  }

  expect_failures = [var.records]
}

run "rejects_health_check_without_endpoint" {
  command = plan

  variables {
    health_checks = { x = { type = "TCP" } }
  }

  expect_failures = [var.health_checks]
}

run "rejects_invalid_health_check_interval" {
  command = plan

  variables {
    health_checks = { x = { fqdn = "app.example.com", request_interval = 20 } }
  }

  expect_failures = [var.health_checks]
}

run "rejects_log_key_outside_us_east_1" {
  command = plan

  variables {
    cloudwatch_logs = { kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" }
  }

  expect_failures = [var.cloudwatch_logs]
}

run "rejects_invalid_dnssec_window" {
  command = plan

  variables {
    dnssec = { deletion_window_in_days = 3 }
  }

  expect_failures = [var.dnssec]
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
