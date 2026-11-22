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

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    }
  }

  mock_resource "aws_security_group" {
    defaults = {
      id = "sg-0123456789abcdef0"
    }
  }

  mock_resource "aws_elasticache_replication_group" {
    defaults = {
      arn                      = "arn:aws:elasticache:eu-west-1:123456789012:replicationgroup:core-prod-cache"
      primary_endpoint_address = "master.core-prod-cache.abc123.euw1.cache.amazonaws.com"
      reader_endpoint_address  = "replica.core-prod-cache.abc123.euw1.cache.amazonaws.com"
      member_clusters          = ["core-prod-cache-001", "core-prod-cache-002"]
    }
  }
}

variables {
  application = "core"
  environment = "prod"
  name        = "cache"
  tags        = { Team = "payments" }
  vpc_id      = "vpc-0a1b2c3d4e5f67890"
  subnet_ids  = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = aws_elasticache_replication_group.this.replication_group_id == "core-prod-cache" && aws_elasticache_replication_group.this.engine == "valkey" && aws_elasticache_replication_group.this.engine_version == "9.1" && aws_elasticache_replication_group.this.port == 6379
    error_message = "Defaults: Valkey 9.1 on 6379, named <application>-<environment>-<name>."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.num_cache_clusters == 2 && aws_elasticache_replication_group.this.automatic_failover_enabled && aws_elasticache_replication_group.this.multi_az_enabled
    error_message = "Two nodes with automatic failover and Multi-AZ by default (ElastiCache.3)."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.at_rest_encryption_enabled == "true" && aws_elasticache_replication_group.this.kms_key_id == null && output.kms_key_arn == null
    error_message = "Encryption at rest with the AWS managed key by default (ElastiCache.4)."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.transit_encryption_enabled && aws_elasticache_replication_group.this.transit_encryption_mode == "required"
    error_message = "TLS must be required (ElastiCache.5)."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.auto_minor_version_upgrade == "true" && aws_elasticache_replication_group.this.snapshot_retention_limit == 7 && aws_elasticache_replication_group.this.final_snapshot_identifier == "core-prod-cache-final"
    error_message = "Minor upgrades on (ElastiCache.2), 7-day snapshots (ElastiCache.1) and a final snapshot."
  }

  assert {
    condition     = aws_elasticache_subnet_group.this.name == "core-prod-cache" && aws_elasticache_replication_group.this.subnet_group_name == "core-prod-cache"
    error_message = "A dedicated subnet group must be used (ElastiCache.7)."
  }

  assert {
    condition     = aws_elasticache_parameter_group.this.family == "valkey9" && aws_elasticache_parameter_group.this.name == "core-prod-cache-valkey9" && length(aws_elasticache_parameter_group.this.parameter) == 0
    error_message = "The parameter group follows the engine major version."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.user_group_ids == null && aws_elasticache_replication_group.this.auth_token_wo_version == null
    error_message = "No user group or AUTH token by default."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.tags["Name"] == "core-prod-cache" && aws_elasticache_replication_group.this.tags["Team"] == "payments" && aws_elasticache_replication_group.this.tags["ManagedBy"] == "Terraform" && aws_elasticache_subnet_group.this.tags["Application"] == "core"
    error_message = "Caller and governance tags must be applied."
  }
}

run "logs_on_by_default" {
  command = plan

  assert {
    condition     = toset([for c in aws_elasticache_replication_group.this.log_delivery_configuration : "${c.log_type}=${c.destination}"]) == toset(["slow-log=/aws/elasticache/core-prod-cache/slow-log", "engine-log=/aws/elasticache/core-prod-cache/engine-log"])
    error_message = "Slow and engine logs must go to the module log groups."
  }

  assert {
    condition     = alltrue([for c in aws_elasticache_replication_group.this.log_delivery_configuration : c.log_format == "json" && c.destination_type == "cloudwatch-logs"])
    error_message = "Logs are delivered as JSON to CloudWatch Logs."
  }

  assert {
    condition     = module.log_group["slow-log"].retention_in_days == 365 && module.log_group["engine-log"].kms_key_arn == null && output.log_group_names == { "engine-log" = "/aws/elasticache/core-prod-cache/engine-log", "slow-log" = "/aws/elasticache/core-prod-cache/slow-log" }
    error_message = "Log groups keep 365 days with service encryption by default."
  }
}

run "logs_disabled" {
  command = plan

  variables {
    cloudwatch_logs = { enabled = false }
  }

  assert {
    condition     = length(aws_elasticache_replication_group.this.log_delivery_configuration) == 0 && length(module.log_group) == 0 && length(output.log_group_names) == 0
    error_message = "cloudwatch_logs.enabled = false must drop the log groups and delivery."
  }
}

run "slow_log_only_as_text" {
  command = plan

  variables {
    cloudwatch_logs = { log_types = ["slow-log"], log_format = "text", retention_in_days = 731 }
  }

  assert {
    condition     = length(aws_elasticache_replication_group.this.log_delivery_configuration) == 1 && one(aws_elasticache_replication_group.this.log_delivery_configuration).log_format == "text" && module.log_group["slow-log"].retention_in_days == 731
    error_message = "log_types, log_format and retention must be honoured."
  }
}

run "security_group_wiring" {
  command   = apply
  state_key = "network"

  variables {
    security_group = {
      ingress_security_group_ids    = ["sg-0aaaaaaaaaaaaaaaa"]
      ingress_cidr_blocks           = ["10.0.0.0/16", "fd00::/8"]
      ingress_prefix_list_ids       = ["pl-0123456789abcdef0"]
      additional_security_group_ids = ["sg-0bbbbbbbbbbbbbbbb"]
    }
  }

  assert {
    condition     = toset(keys(module.security_group[0].ingress_rule_ids)) == toset(["sg-0", "cidr-0", "cidr-1", "pl-0"]) && length(module.security_group[0].egress_rule_ids) == 0
    error_message = "One ingress rule per source on the Valkey port and no egress."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.security_group_ids == toset(["sg-0123456789abcdef0", "sg-0bbbbbbbbbbbbbbbb"]) && output.security_group_id == "sg-0123456789abcdef0"
    error_message = "The replication group must use the module group and the extra group."
  }
}

run "bring_your_own_security_group" {
  command = plan

  variables {
    security_group = { create = false, additional_security_group_ids = ["sg-0bbbbbbbbbbbbbbbb"] }
  }

  assert {
    condition     = length(module.security_group) == 0 && aws_elasticache_replication_group.this.security_group_ids == toset(["sg-0bbbbbbbbbbbbbbbb"]) && output.security_group_id == null
    error_message = "create = false must use only the caller groups."
  }
}

run "outputs" {
  command   = apply
  state_key = "network"

  assert {
    condition     = output.id == "core-prod-cache" && output.arn == "arn:aws:elasticache:eu-west-1:123456789012:replicationgroup:core-prod-cache" && output.port == 6379
    error_message = "id, arn and port must come from the replication group."
  }

  assert {
    condition     = output.primary_endpoint_address == "master.core-prod-cache.abc123.euw1.cache.amazonaws.com" && output.reader_endpoint_address == "replica.core-prod-cache.abc123.euw1.cache.amazonaws.com" && output.member_clusters == toset(["core-prod-cache-001", "core-prod-cache-002"])
    error_message = "Endpoints and member clusters must be output."
  }
}

run "module_key_is_planned_safely" {
  command   = plan
  state_key = "module_key"

  variables {
    kms = { create = true }
  }

  assert {
    condition     = module.encryption.created
    error_message = "kms.create must plan without knowing the key ARN."
  }
}

run "module_key_encrypts_data_and_logs" {
  command   = apply
  state_key = "module_key"

  variables {
    kms = { create = true }
  }

  assert {
    condition     = aws_elasticache_replication_group.this.kms_key_id == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && module.log_group["engine-log"].kms_key_arn == aws_elasticache_replication_group.this.kms_key_id
    error_message = "The module key must encrypt the data and the logs."
  }
}

run "caller_key_id_and_log_key_override" {
  command = plan

  variables {
    kms             = { key_id = "11111111-2222-3333-4444-555555555555" }
    cloudwatch_logs = { kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/99999999-2222-3333-4444-555555555555" }
  }

  assert {
    condition     = aws_elasticache_replication_group.this.kms_key_id == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && module.log_group["slow-log"].kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/99999999-2222-3333-4444-555555555555"
    error_message = "A key ID must be used as the key ARN; cloudwatch_logs.kms_key_arn overrides the log key."
  }
}

run "single_node" {
  command = plan

  variables {
    num_cache_clusters = 1
    subnet_ids         = ["subnet-0123456789abcdef0"]
  }

  assert {
    condition     = !aws_elasticache_replication_group.this.automatic_failover_enabled && !aws_elasticache_replication_group.this.multi_az_enabled
    error_message = "A single node cannot fail over."
  }
}

run "auth_token" {
  command = plan

  variables {
    auth_token_wo              = "0123456789abcdefghij"
    auth_token_wo_version      = 2
    auth_token_update_strategy = "SET"
  }

  assert {
    condition     = aws_elasticache_replication_group.this.auth_token_wo_version == 2 && aws_elasticache_replication_group.this.auth_token_update_strategy == "SET" && aws_elasticache_replication_group.this.user_group_ids == null
    error_message = "The write-only AUTH token must be versioned."
  }
}

run "user_group" {
  command = plan

  variables {
    user_group_id = "core-prod-users"
  }

  assert {
    condition     = aws_elasticache_replication_group.this.user_group_ids == toset(["core-prod-users"])
    error_message = "user_group_id must be associated."
  }
}

run "engine_parameters_and_snapshots" {
  command = plan

  variables {
    engine_version           = "8.2"
    parameters               = { "maxmemory-policy" = "allkeys-lru" }
    snapshot_retention_limit = 14
    snapshot_window          = "01:00-02:00"
  }

  assert {
    condition     = aws_elasticache_parameter_group.this.family == "valkey8" && aws_elasticache_parameter_group.this.name == "core-prod-cache-valkey8" && one(aws_elasticache_parameter_group.this.parameter).value == "allkeys-lru"
    error_message = "Parameters must go into the family of the engine version."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.snapshot_retention_limit == 14 && aws_elasticache_replication_group.this.snapshot_window == "01:00-02:00"
    error_message = "Snapshot settings must apply."
  }
}

run "long_name_is_truncated_to_40" {
  command = plan

  variables {
    name = "session-store-for-checkout-svc01"
  }

  assert {
    condition     = length(aws_elasticache_replication_group.this.replication_group_id) == 40 && startswith(aws_elasticache_replication_group.this.replication_group_id, "core-prod-session-store-for-check-")
    error_message = "Replication group IDs must be cut to 40 characters with a hash."
  }

  assert {
    condition     = aws_elasticache_subnet_group.this.name == "core-prod-session-store-for-checkout-svc01"
    error_message = "Other names keep the full name."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Cache_1"
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

run "rejects_valkey_7_1" {
  command = plan

  variables {
    engine_version = "7.1"
  }

  expect_failures = [var.engine_version]
}

run "rejects_old_engine_version" {
  command = plan

  variables {
    engine_version = "6.2"
  }

  expect_failures = [var.engine_version]
}

run "rejects_too_many_nodes" {
  command = plan

  variables {
    num_cache_clusters = 7
  }

  expect_failures = [var.num_cache_clusters]
}

run "rejects_privileged_port" {
  command = plan

  variables {
    port = 80
  }

  expect_failures = [var.port]
}

run "rejects_disabled_snapshots" {
  command = plan

  variables {
    snapshot_retention_limit = 0
  }

  expect_failures = [var.snapshot_retention_limit]
}

run "rejects_malformed_snapshot_window" {
  command = plan

  variables {
    snapshot_window = "5am-6am"
  }

  expect_failures = [var.snapshot_window]
}

run "rejects_short_auth_token" {
  command = plan

  variables {
    auth_token_wo         = "short"
    auth_token_wo_version = 1
  }

  expect_failures = [var.auth_token_wo]
}

run "rejects_auth_token_with_user_group" {
  command = plan

  variables {
    auth_token_wo         = "0123456789abcdefghij"
    auth_token_wo_version = 1
    user_group_id         = "core-prod-users"
  }

  expect_failures = [var.auth_token_wo]
}

run "rejects_auth_token_without_version" {
  command = plan

  variables {
    auth_token_wo = "0123456789abcdefghij"
  }

  expect_failures = [var.auth_token_wo_version]
}

run "rejects_unknown_update_strategy" {
  command = plan

  variables {
    auth_token_update_strategy = "REPLACE"
  }

  expect_failures = [var.auth_token_update_strategy]
}

run "rejects_kms_create_with_key_id" {
  command = plan

  variables {
    kms = { create = true, key_id = "11111111-2222-3333-4444-555555555555" }
  }

  expect_failures = [var.kms]
}

run "rejects_invalid_key_id" {
  command = plan

  variables {
    kms = { key_id = "alias/cache" }
  }

  expect_failures = [var.kms]
}

run "rejects_one_subnet_with_replicas" {
  command = plan

  variables {
    subnet_ids = ["subnet-0123456789abcdef0"]
  }

  expect_failures = [var.subnet_ids]
}

run "rejects_open_ingress" {
  command = plan

  variables {
    security_group = { ingress_cidr_blocks = ["0.0.0.0/0"] }
  }

  expect_failures = [var.security_group]
}

run "rejects_no_security_group" {
  command = plan

  variables {
    security_group = { create = false }
  }

  expect_failures = [var.security_group]
}

run "rejects_unknown_log_type" {
  command = plan

  variables {
    cloudwatch_logs = { log_types = ["audit-log"] }
  }

  expect_failures = [var.cloudwatch_logs]
}

run "rejects_unknown_log_format" {
  command = plan

  variables {
    cloudwatch_logs = { log_format = "xml" }
  }

  expect_failures = [var.cloudwatch_logs]
}
