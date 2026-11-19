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

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/core-prod-orders-proxy-eu-west-1"
    }
  }

  mock_resource "aws_security_group" {
    defaults = {
      id = "sg-0123456789abcdef0"
    }
  }

  mock_resource "aws_db_proxy" {
    defaults = {
      id       = "core-prod-orders"
      arn      = "arn:aws:rds:eu-west-1:123456789012:db-proxy:prx-0123456789abcdef0"
      endpoint = "core-prod-orders.proxy-abcdefghijkl.eu-west-1.rds.amazonaws.com"
    }
  }

  mock_resource "aws_db_proxy_default_target_group" {
    defaults = {
      name = "default"
    }
  }

  mock_resource "aws_db_proxy_endpoint" {
    defaults = {
      endpoint = "core-prod-orders-reporting.endpoint.proxy-abcdefghijkl.eu-west-1.rds.amazonaws.com"
    }
  }
}

variables {
  application = "core"
  environment = "prod"
  name        = "orders"
  vpc_id      = "vpc-0a1b2c3d4e5f67890"
  subnet_ids  = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  tags        = { Team = "payments" }
  target = {
    db_instance_identifier = "core-prod-orders"
    security_group_ids     = ["sg-0dddddddddddddddd"]
  }
  auth = [{ secret_arn = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:rds!db-1234-AbCdEf" }]
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = aws_db_proxy.this.name == "core-prod-orders" && aws_db_proxy.this.engine_family == "POSTGRESQL" && aws_db_proxy.this.require_tls
    error_message = "Defaults: PostgreSQL proxy requiring TLS (RDS.43), named <application>-<environment>-<name>."
  }

  assert {
    condition     = one(aws_db_proxy.this.auth).iam_auth == "REQUIRED" && one(aws_db_proxy.this.auth).auth_scheme == "SECRETS" && aws_db_proxy.this.default_auth_scheme == "NONE"
    error_message = "Clients must use IAM authentication by default; the proxy uses the secret."
  }

  assert {
    condition     = !aws_db_proxy.this.debug_logging && aws_db_proxy.this.idle_client_timeout == 1800 && aws_db_proxy.this.vpc_subnet_ids == toset(["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"])
    error_message = "No SQL debug logging; 30-minute idle timeout; proxy in the given subnets."
  }

  assert {
    condition     = aws_db_proxy_target.this.db_instance_identifier == "core-prod-orders" && aws_db_proxy_target.this.db_proxy_name == "core-prod-orders"
    error_message = "The DB instance must be the proxy target."
  }

  assert {
    condition     = aws_db_proxy_default_target_group.this.connection_pool_config[0].max_connections_percent == 100 && aws_db_proxy_default_target_group.this.connection_pool_config[0].max_idle_connections_percent == 50 && aws_db_proxy_default_target_group.this.connection_pool_config[0].connection_borrow_timeout == 120
    error_message = "The connection pool must use the documented defaults."
  }

  assert {
    condition     = length(aws_db_proxy_endpoint.this) == 0 && length(module.log_group) == 0
    error_message = "No extra endpoints or log group by default."
  }

  assert {
    condition     = aws_db_proxy.this.tags["Name"] == "core-prod-orders" && aws_db_proxy.this.tags["Team"] == "payments" && aws_db_proxy.this.tags["ManagedBy"] == "Terraform"
    error_message = "Caller and governance tags must be applied."
  }
}

run "proxy_role" {
  command = plan

  assert {
    condition     = module.role[0].name == "core-prod-orders-proxy-eu-west-1" && jsondecode(module.role[0].trust_policy_json).Statement[0].Principal.Service == ["rds.amazonaws.com"]
    error_message = "The role is <base>-proxy-<region>, trusted by RDS."
  }

  assert {
    condition     = [for s in jsondecode(module.role[0].policy_json).Statement : s.Sid] == ["ReadSecrets", "DecryptSecrets"]
    error_message = "The role may only read the secrets and decrypt them."
  }

  assert {
    condition     = jsondecode(module.role[0].policy_json).Statement[0].Resource == ["arn:aws:secretsmanager:eu-west-1:123456789012:secret:rds!db-1234-AbCdEf"] && jsondecode(module.role[0].policy_json).Statement[1].Condition.StringEquals["kms:ViaService"] == "secretsmanager.eu-west-1.amazonaws.com"
    error_message = "Secrets are scoped to auth; decrypt only through Secrets Manager in this Region."
  }
}

run "security_group_wiring" {
  command   = apply
  state_key = "network"

  variables {
    security_group = {
      ingress_security_group_ids    = ["sg-0aaaaaaaaaaaaaaaa"]
      ingress_cidr_blocks           = ["10.0.0.0/16"]
      additional_security_group_ids = ["sg-0bbbbbbbbbbbbbbbb"]
    }
  }

  assert {
    condition     = toset(keys(module.security_group[0].ingress_rule_ids)) == toset(["sg-0", "cidr-0"])
    error_message = "One ingress rule per client source on the engine port."
  }

  assert {
    condition     = toset(keys(module.security_group[0].egress_rule_ids)) == toset(["db-0", "https-0"])
    error_message = "Egress to the database and HTTPS to AWS APIs."
  }

  assert {
    condition     = aws_db_proxy.this.vpc_security_group_ids == toset(["sg-0123456789abcdef0", "sg-0bbbbbbbbbbbbbbbb"]) && output.security_group_id == "sg-0123456789abcdef0"
    error_message = "The proxy must use the module group and the extra group."
  }
}

run "outputs" {
  command   = apply
  state_key = "network"

  assert {
    condition     = output.id == "core-prod-orders" && output.name == "core-prod-orders" && output.arn == "arn:aws:rds:eu-west-1:123456789012:db-proxy:prx-0123456789abcdef0"
    error_message = "id, arn and name must come from the proxy."
  }

  assert {
    condition     = output.endpoint == "core-prod-orders.proxy-abcdefghijkl.eu-west-1.rds.amazonaws.com" && output.role_arn == "arn:aws:iam::123456789012:role/core-prod-orders-proxy-eu-west-1" && output.role_name == "core-prod-orders-proxy-eu-west-1"
    error_message = "Endpoint and role must be output."
  }

  assert {
    condition     = length(output.endpoints) == 0 && output.log_group_name == null
    error_message = "No extra endpoints or log group by default."
  }
}

run "aws_api_egress_through_endpoints" {
  command   = apply
  state_key = "endpoints_egress"

  variables {
    target         = { db_instance_identifier = "core-prod-orders", port = 5433, security_group_ids = ["sg-0dddddddddddddddd"] }
    security_group = { egress_cidr_blocks = ["10.0.0.0/16"] }
  }

  assert {
    condition     = toset(keys(module.security_group[0].egress_rule_ids)) == toset(["db-0", "https-0"]) && length(module.security_group[0].ingress_rule_ids) == 0
    error_message = "egress_cidr_blocks replaces the default HTTPS destination; no ingress without sources."
  }
}

run "endpoints" {
  command = apply

  variables {
    endpoints = {
      reporting = {}
      shared    = { subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"], security_group_ids = ["sg-0ccccccccccccccccc"] }
    }
  }

  assert {
    condition     = aws_db_proxy_endpoint.this["reporting"].db_proxy_endpoint_name == "core-prod-orders-reporting" && aws_db_proxy_endpoint.this["reporting"].target_role == "READ_WRITE" && aws_db_proxy_endpoint.this["reporting"].vpc_subnet_ids == toset(["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]) && aws_db_proxy_endpoint.this["reporting"].vpc_security_group_ids == toset(["sg-0123456789abcdef0"])
    error_message = "An endpoint defaults to the proxy subnets and groups."
  }

  assert {
    condition     = aws_db_proxy_endpoint.this["shared"].vpc_subnet_ids == toset(["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"]) && aws_db_proxy_endpoint.this["shared"].vpc_security_group_ids == toset(["sg-0ccccccccccccccccc"])
    error_message = "An endpoint may use its own subnets and groups."
  }

  assert {
    condition     = output.endpoints["reporting"] == "core-prod-orders-reporting.endpoint.proxy-abcdefghijkl.eu-west-1.rds.amazonaws.com" && aws_db_proxy_endpoint.this["shared"].tags["Name"] == "core-prod-orders-shared"
    error_message = "Endpoint hostnames must be output; endpoints are tagged."
  }
}

run "log_group" {
  command = plan

  variables {
    cloudwatch_logs = { enabled = true, kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/99999999-2222-3333-4444-555555555555" }
  }

  assert {
    condition     = module.log_group[0].name == "/aws/rds/proxy/core-prod-orders" && module.log_group[0].retention_in_days == 365 && module.log_group[0].kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/99999999-2222-3333-4444-555555555555"
    error_message = "The proxy log group must be pre-created with retention and the given key."
  }
}

run "end_to_end_iam" {
  command = plan

  variables {
    default_auth_scheme = "IAM_AUTH"
    auth                = []
    iam_role = {
      policy_statements = [{ sid = "ConnectDatabase", actions = ["rds-db:connect"], resources = ["arn:aws:rds-db:eu-west-1:123456789012:dbuser:db-ABCDEFGHIJKLMNOPQRSTUVWXYZ/app"] }]
    }
  }

  assert {
    condition     = aws_db_proxy.this.default_auth_scheme == "IAM_AUTH" && length(aws_db_proxy.this.auth) == 0
    error_message = "End-to-end IAM needs no secrets."
  }

  assert {
    condition     = [for s in jsondecode(module.role[0].policy_json).Statement : s.Sid] == ["ConnectDatabase"]
    error_message = "Without secrets the role carries only the caller statements."
  }
}

run "bring_your_own_role" {
  command = plan

  variables {
    iam_role = { create = false, arn = "arn:aws:iam::123456789012:role/shared-proxy" }
  }

  assert {
    condition     = aws_db_proxy.this.role_arn == "arn:aws:iam::123456789012:role/shared-proxy" && length(module.role) == 0 && output.role_name == null
    error_message = "A caller role must replace the module role."
  }
}

run "bring_your_own_security_group" {
  command = plan

  variables {
    security_group = { create = false, additional_security_group_ids = ["sg-0bbbbbbbbbbbbbbbb"] }
  }

  assert {
    condition     = length(module.security_group) == 0 && aws_db_proxy.this.vpc_security_group_ids == toset(["sg-0bbbbbbbbbbbbbbbb"]) && output.security_group_id == null
    error_message = "create = false must use only the caller groups."
  }
}

run "mysql_pool_settings" {
  command = plan

  variables {
    engine_family   = "MYSQL"
    connection_pool = { max_connections_percent = 80, max_idle_connections_percent = 20, session_pinning_filters = ["EXCLUDE_VARIABLE_SETS"], init_query = "SET time_zone = 'UTC'" }
  }

  assert {
    condition     = aws_db_proxy.this.engine_family == "MYSQL" && aws_db_proxy_default_target_group.this.connection_pool_config[0].max_connections_percent == 80 && aws_db_proxy_default_target_group.this.connection_pool_config[0].session_pinning_filters == toset(["EXCLUDE_VARIABLE_SETS"])
    error_message = "Engine family and pool settings must apply."
  }
}

run "long_name_is_truncated_to_63" {
  command = plan

  variables {
    application = "customer-onboarding-plat"
    environment = "production01"
    name        = "orders-reconciliation-ledger-001"
  }

  assert {
    condition     = length(aws_db_proxy.this.name) == 63 && startswith(aws_db_proxy.this.name, "customer-onboarding-plat-production01-orders-reconciliat")
    error_message = "Proxy names must be cut to 63 characters with a hash."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Orders_Proxy"
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

run "rejects_unknown_engine_family" {
  command = plan

  variables {
    engine_family = "ORACLE"
  }

  expect_failures = [var.engine_family]
}

run "rejects_invalid_target_port" {
  command = plan

  variables {
    target = { db_instance_identifier = "core-prod-orders", port = 80 }
  }

  expect_failures = [var.target]
}

run "rejects_one_subnet" {
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

run "rejects_unknown_auth_scheme" {
  command = plan

  variables {
    default_auth_scheme = "PASSWORD"
  }

  expect_failures = [var.default_auth_scheme]
}

run "rejects_no_auth_with_secrets_scheme" {
  command = plan

  variables {
    auth = []
  }

  expect_failures = [var.auth]
}

run "rejects_iam_auth_enabled_outside_sqlserver" {
  command = plan

  variables {
    auth = [{ secret_arn = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:db", iam_auth = "ENABLED" }]
  }

  expect_failures = [var.auth]
}

run "rejects_auth_without_secret" {
  command = plan

  variables {
    auth = [{ iam_auth = "REQUIRED" }]
  }

  expect_failures = [var.auth]
}

run "rejects_long_idle_timeout" {
  command = plan

  variables {
    idle_client_timeout = 28801
  }

  expect_failures = [var.idle_client_timeout]
}

run "rejects_idle_above_max_connections" {
  command = plan

  variables {
    connection_pool = { max_connections_percent = 40, max_idle_connections_percent = 60 }
  }

  expect_failures = [var.connection_pool]
}

run "rejects_long_borrow_timeout" {
  command = plan

  variables {
    connection_pool = { connection_borrow_timeout = 3601 }
  }

  expect_failures = [var.connection_pool]
}

run "rejects_role_without_arn" {
  command = plan

  variables {
    iam_role = { create = false }
  }

  expect_failures = [var.iam_role]
}

run "rejects_invalid_endpoint_key" {
  command = plan

  variables {
    endpoints = { Reporting_1 = {} }
  }

  expect_failures = [var.endpoints]
}

run "alarms_by_default" {
  command = plan

  assert {
    condition     = sort(keys(output.alarm_names)) == tolist(["rdsproxy-proxy-borrowed-connections", "rdsproxy-proxy-client-auth-failures", "rdsproxy-proxy-connection-setup-failures"])
    error_message = "Default alarms: connection setup failures, client auth failures and pool saturation."
  }

  assert {
    condition     = alltrue([for n in values(output.alarm_names) : startswith(n, "core-prod-orders-rdsproxy-proxy-")]) && module.alarms[0].alarm_settings["rdsproxy-proxy-borrowed-connections"].threshold == 80
    error_message = "Alarm names start with the module base name; pool saturation alarms at 80 %."
  }

  assert {
    condition     = alltrue([for k, r in module.alarms[0].alarm_routes : r.topic_arn == null])
    error_message = "Without topic_arns, alarms have no actions."
  }
}

run "alarms_off" {
  command = plan

  variables {
    alarms = { enabled = false }
  }

  assert {
    condition     = length(module.alarms) == 0 && length(output.alarm_names) == 0 && length(output.alarm_arns) == 0
    error_message = "alarms.enabled = false creates no alarms."
  }
}

run "alarms_tuned_and_routed" {
  command   = apply
  state_key = "alarms"

  variables {
    alarms = {
      topic_arns = {
        critical = "arn:aws:sns:eu-west-1:123456789012:platform-prod-critical"
        warning  = "arn:aws:sns:eu-west-1:123456789012:platform-prod-warning"
        info     = "arn:aws:sns:eu-west-1:123456789012:platform-prod-info"
      }
      overrides = {
        borrowed_connections = { threshold = 90 }
        client_auth_failures = { enabled = false }
        client_connections   = { enabled = true, threshold = 500 }
      }
    }
  }

  assert {
    condition     = sort(keys(output.alarm_arns)) == tolist(["rdsproxy-proxy-borrowed-connections", "rdsproxy-proxy-client-connections", "rdsproxy-proxy-connection-setup-failures"])
    error_message = "A disabled alarm is dropped; an opt-in alarm is added."
  }

  assert {
    condition     = module.alarms[0].alarm_settings["rdsproxy-proxy-borrowed-connections"].threshold == 90 && module.alarms[0].alarm_settings["rdsproxy-proxy-borrowed-connections"].evaluation_periods == 5 && module.alarms[0].alarm_settings["rdsproxy-proxy-client-connections"].threshold == 500
    error_message = "Overrides change one setting; the rest keep the preset defaults."
  }

  assert {
    condition     = module.alarms[0].alarm_routes["rdsproxy-proxy-connection-setup-failures"].topic_arn == "arn:aws:sns:eu-west-1:123456789012:platform-prod-critical" && module.alarms[0].alarm_routes["rdsproxy-proxy-borrowed-connections"].topic_arn == "arn:aws:sns:eu-west-1:123456789012:platform-prod-warning"
    error_message = "Each alarm notifies the topic for its severity."
  }
}

run "alarms_plan_with_unknown_arns" {
  command   = plan
  state_key = "alarms_plan"

  assert {
    condition     = length(module.alarms) == 1 && length(output.alarm_names) == 3
    error_message = "Alarm keys and names must be known at plan with an unknown role ARN."
  }
}

run "rejects_invalid_alarm_topic" {
  command = plan

  variables {
    alarms = { topic_arns = { critical = "arn:aws:sqs:eu-west-1:123456789012:core-prod-critical" } }
  }

  expect_failures = [var.alarms]
}
