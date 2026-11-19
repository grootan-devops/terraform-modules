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

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/core-prod-orders-monitoring-eu-west-1"
    }
  }

  mock_resource "aws_security_group" {
    defaults = {
      id = "sg-0123456789abcdef0"
    }
  }

  mock_resource "aws_db_instance" {
    defaults = {
      arn         = "arn:aws:rds:eu-west-1:123456789012:db:core-prod-orders"
      address     = "core-prod-orders.abcdefghijkl.eu-west-1.rds.amazonaws.com"
      endpoint    = "core-prod-orders.abcdefghijkl.eu-west-1.rds.amazonaws.com:5432"
      resource_id = "db-ABCDEFGHIJKLMNOPQRSTUVWXYZ"
      master_user_secret = [{
        kms_key_id    = "arn:aws:kms:eu-west-1:123456789012:key/aws-secretsmanager"
        secret_arn    = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:rds!db-1234-AbCdEf"
        secret_status = "active"
      }]
    }
  }
}

variables {
  application    = "core"
  environment    = "prod"
  name           = "orders"
  engine_version = "18"
  vpc_id         = "vpc-0a1b2c3d4e5f67890"
  subnet_ids     = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  tags           = { Team = "payments" }
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = aws_db_instance.this.identifier == "core-prod-orders" && aws_db_instance.this.engine == "postgres" && aws_db_instance.this.engine_version == "18" && aws_db_instance.this.engine_lifecycle_support == "open-source-rds-extended-support-disabled" && aws_db_instance.this.instance_class == "db.t4g.medium" && aws_db_instance.this.port == 5432
    error_message = "Defaults: PostgreSQL on db.t4g.medium, port 5432, named <application>-<environment>-<name>."
  }

  assert {
    condition     = aws_db_instance.this.multi_az && !aws_db_instance.this.publicly_accessible && aws_db_instance.this.network_type == "IPV4"
    error_message = "Multi-AZ (RDS.5) and private (RDS.2) by default."
  }

  assert {
    condition     = aws_db_instance.this.storage_encrypted && module.encryption.key_arn == null && output.kms_key_arn == null
    error_message = "Storage encrypted with the AWS managed key by default (RDS.3)."
  }

  assert {
    condition     = aws_db_instance.this.allocated_storage == 20 && aws_db_instance.this.max_allocated_storage == 1000 && aws_db_instance.this.storage_type == "gp3"
    error_message = "Storage defaults: 20 GiB gp3 growing to 1000 GiB."
  }

  assert {
    condition     = aws_db_instance.this.username == "dbadmin" && aws_db_instance.this.manage_master_user_password && aws_db_instance.this.password_wo_version == null
    error_message = "The master password is managed in Secrets Manager for dbadmin by default (RDS.25)."
  }

  assert {
    condition     = aws_db_instance.this.deletion_protection && !aws_db_instance.this.skip_final_snapshot && aws_db_instance.this.copy_tags_to_snapshot && !aws_db_instance.this.delete_automated_backups
    error_message = "Deletion protection (RDS.8), final snapshot and tag copy (RDS.17)."
  }

  assert {
    condition     = aws_db_instance.this.backup_retention_period == 14 && length(aws_db_instance_automated_backups_replication.this) == 0
    error_message = "14-day backups (RDS.11); no cross-Region replication by default."
  }

  assert {
    condition     = aws_db_instance.this.iam_database_authentication_enabled && aws_db_instance.this.auto_minor_version_upgrade && !aws_db_instance.this.allow_major_version_upgrade
    error_message = "IAM authentication (RDS.10) and minor upgrades (RDS.13)."
  }

  assert {
    condition     = aws_db_instance.this.monitoring_interval == 60 && aws_db_instance.this.performance_insights_enabled && aws_db_instance.this.performance_insights_retention_period == 7 && aws_db_instance.this.database_insights_mode == "standard"
    error_message = "Enhanced Monitoring every 60 s (RDS.6) and Performance Insights for 7 days."
  }

  assert {
    condition     = aws_db_instance.this.enabled_cloudwatch_logs_exports == toset(["postgresql", "upgrade"])
    error_message = "postgresql and upgrade logs must be exported (RDS.9, RDS.36)."
  }

  assert {
    condition     = length(aws_db_event_subscription.this) == 0
    error_message = "No event subscriptions by default."
  }

  assert {
    condition     = aws_db_instance.this.tags["Name"] == "core-prod-orders" && aws_db_instance.this.tags["Team"] == "payments" && aws_db_instance.this.tags["ManagedBy"] == "Terraform" && aws_db_subnet_group.this.tags["Environment"] == "prod"
    error_message = "Caller and governance tags must be applied (RDS.30, RDS.33)."
  }
}

run "subnet_and_parameter_groups" {
  command = plan

  assert {
    condition     = aws_db_subnet_group.this.name == "core-prod-orders" && aws_db_instance.this.db_subnet_group_name == "core-prod-orders"
    error_message = "A dedicated subnet group must be used."
  }

  assert {
    condition     = aws_db_parameter_group.this.family == "postgres18" && aws_db_parameter_group.this.name == "core-prod-orders-postgres18" && aws_db_instance.this.parameter_group_name == "core-prod-orders-postgres18"
    error_message = "The parameter group follows the engine major version."
  }

  assert {
    condition     = toset([for p in aws_db_parameter_group.this.parameter : "${p.name}=${p.value}"]) == toset(["rds.force_ssl=1"])
    error_message = "rds.force_ssl must be 1 (RDS.38)."
  }
}

run "monitoring_role" {
  command = plan

  assert {
    condition     = module.monitoring_role[0].name == "core-prod-orders-monitoring-eu-west-1" && module.monitoring_role[0].policy_json == null
    error_message = "The monitoring role is <base>-monitoring-<region> with only the managed policy."
  }

  assert {
    condition     = jsondecode(module.monitoring_role[0].trust_policy_json).Statement[0].Principal.Service == ["monitoring.rds.amazonaws.com"]
    error_message = "Only Enhanced Monitoring may assume the role."
  }

  assert {
    condition     = jsondecode(module.monitoring_role[0].trust_policy_json).Statement[0].Condition.StringEquals["aws:SourceAccount"] == ["123456789012"] && jsondecode(module.monitoring_role[0].trust_policy_json).Statement[0].Condition.ArnLike["aws:SourceArn"] == ["arn:aws:rds:eu-west-1:123456789012:db:core-prod-orders"]
    error_message = "The trust must be limited to this account and instance."
  }
}

run "log_groups" {
  command = plan

  assert {
    condition     = module.log_group["postgresql"].name == "/aws/rds/instance/core-prod-orders/postgresql" && module.log_group["upgrade"].name == "/aws/rds/instance/core-prod-orders/upgrade"
    error_message = "Every export gets its log group before the instance writes to it."
  }

  assert {
    condition     = module.log_group["postgresql"].retention_in_days == 365 && module.log_group["postgresql"].kms_key_arn == null
    error_message = "Log groups keep 365 days with service encryption by default (CloudWatch.16)."
  }

  assert {
    condition     = aws_cloudwatch_query_definition.recent_errors.log_group_names == tolist(["/aws/rds/instance/core-prod-orders/postgresql"]) && aws_cloudwatch_query_definition.slow_queries.name == "RDS/core-prod-orders/SlowQueries"
    error_message = "Saved queries must target the PostgreSQL log."
  }
}

run "security_group_wiring" {
  command   = apply
  state_key = "network"

  variables {
    security_group = {
      ingress_security_group_ids    = ["sg-0aaaaaaaaaaaaaaaa"]
      ingress_cidr_blocks           = ["10.0.0.0/16"]
      ingress_prefix_list_ids       = ["pl-0123456789abcdef0"]
      additional_security_group_ids = ["sg-0bbbbbbbbbbbbbbbb"]
    }
  }

  assert {
    condition     = toset(keys(module.security_group[0].ingress_rule_ids)) == toset(["sg-0", "cidr-0", "pl-0"]) && length(module.security_group[0].egress_rule_ids) == 0
    error_message = "One ingress rule per source on the database port; no egress by default."
  }

  assert {
    condition     = aws_db_instance.this.vpc_security_group_ids == toset(["sg-0123456789abcdef0", "sg-0bbbbbbbbbbbbbbbb"]) && output.security_group_id == "sg-0123456789abcdef0"
    error_message = "The instance must use the module group and the extra group."
  }
}

run "outputs" {
  command   = apply
  state_key = "network"

  assert {
    condition     = output.id == "core-prod-orders" && output.arn == "arn:aws:rds:eu-west-1:123456789012:db:core-prod-orders" && output.resource_id == "db-ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    error_message = "id, arn and resource_id must come from the instance."
  }

  assert {
    condition     = output.address == "core-prod-orders.abcdefghijkl.eu-west-1.rds.amazonaws.com" && output.endpoint == "core-prod-orders.abcdefghijkl.eu-west-1.rds.amazonaws.com:5432" && output.port == 5432
    error_message = "Connection details must be output."
  }

  assert {
    condition     = output.master_user_secret_arn == "arn:aws:secretsmanager:eu-west-1:123456789012:secret:rds!db-1234-AbCdEf" && output.monitoring_role_arn == "arn:aws:iam::123456789012:role/core-prod-orders-monitoring-eu-west-1"
    error_message = "The managed secret and monitoring role must be output."
  }

  assert {
    condition     = output.log_group_names == { postgresql = "/aws/rds/instance/core-prod-orders/postgresql", upgrade = "/aws/rds/instance/core-prod-orders/upgrade" }
    error_message = "Log group names must be output by export."
  }
}

run "egress_for_extensions" {
  command   = apply
  state_key = "egress"

  variables {
    security_group = { egress_cidr_blocks = ["10.0.0.0/16"] }
  }

  assert {
    condition     = keys(module.security_group[0].egress_rule_ids) == ["cidr-0"] && length(module.security_group[0].ingress_rule_ids) == 0
    error_message = "Egress only follows egress_cidr_blocks."
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

run "module_key_encrypts_everything" {
  command   = apply
  state_key = "module_key"

  variables {
    kms = { create = true }
  }

  assert {
    condition     = aws_db_instance.this.kms_key_id == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && aws_db_instance.this.performance_insights_kms_key_id == aws_db_instance.this.kms_key_id
    error_message = "The module key must encrypt storage and Performance Insights."
  }

  assert {
    condition     = aws_db_instance.this.master_user_secret_kms_key_id == aws_db_instance.this.kms_key_id && module.log_group["postgresql"].kms_key_arn == aws_db_instance.this.kms_key_id
    error_message = "The module key must encrypt the master secret and the logs."
  }
}

run "caller_keys" {
  command = plan

  variables {
    kms             = { key_id = "11111111-2222-3333-4444-555555555555" }
    credential      = { kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/22222222-2222-3333-4444-555555555555" }
    cloudwatch_logs = { kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/99999999-2222-3333-4444-555555555555", retention_in_days = 731, exports = ["postgresql", "upgrade", "iam-db-auth-error"] }
  }

  assert {
    condition     = aws_db_instance.this.kms_key_id == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && aws_db_instance.this.master_user_secret_kms_key_id == "arn:aws:kms:eu-west-1:123456789012:key/22222222-2222-3333-4444-555555555555"
    error_message = "A key ID must be used as the key ARN; credential.kms_key_arn overrides the secret key."
  }

  assert {
    condition     = module.log_group["iam-db-auth-error"].kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/99999999-2222-3333-4444-555555555555" && module.log_group["postgresql"].retention_in_days == 731
    error_message = "cloudwatch_logs must override the log key and retention for every export."
  }
}

run "write_only_password" {
  command = plan

  variables {
    credential          = { username = "orders_owner", manage_master_user_password = false }
    password_wo         = "correct-horse-battery-staple"
    password_wo_version = 1
  }

  assert {
    condition     = aws_db_instance.this.manage_master_user_password == null && aws_db_instance.this.password_wo_version == 1 && aws_db_instance.this.username == "orders_owner"
    error_message = "password_wo must replace the managed secret."
  }
}

run "backup_replication" {
  command = plan

  variables {
    backup_replication = { enabled = true, region = "eu-central-1", kms_key_arn = "arn:aws:kms:eu-central-1:123456789012:key/33333333-2222-3333-4444-555555555555" }
  }

  assert {
    condition     = aws_db_instance_automated_backups_replication.this[0].region == "eu-central-1" && aws_db_instance_automated_backups_replication.this[0].kms_key_id == "arn:aws:kms:eu-central-1:123456789012:key/33333333-2222-3333-4444-555555555555" && aws_db_instance_automated_backups_replication.this[0].retention_period == 14
    error_message = "Backups must replicate to the other Region with its key and the same retention."
  }
}

run "event_subscriptions" {
  command = plan

  variables {
    event_subscription = { enabled = true, sns_topic_arn = "arn:aws:sns:eu-west-1:123456789012:core-prod-alarms" }
  }

  assert {
    condition     = aws_db_event_subscription.this["instance"].source_type == "db-instance" && aws_db_event_subscription.this["instance"].source_ids == toset(["core-prod-orders"]) && contains(aws_db_event_subscription.this["instance"].event_categories, "maintenance")
    error_message = "Instance events must be sent to the topic (RDS.20)."
  }

  assert {
    condition     = aws_db_event_subscription.this["parameter-group"].source_type == "db-parameter-group" && aws_db_event_subscription.this["parameter-group"].source_ids == toset(["core-prod-orders-postgres18"]) && aws_db_event_subscription.this["parameter-group"].event_categories == toset(["configuration change"])
    error_message = "Parameter group changes must be sent to the topic (RDS.21)."
  }

  assert {
    condition     = aws_db_event_subscription.this["instance"].sns_topic == "arn:aws:sns:eu-west-1:123456789012:core-prod-alarms" && aws_db_event_subscription.this["instance"].name == "core-prod-orders-instance" && aws_db_event_subscription.this["instance"].tags["ManagedBy"] == "Terraform"
    error_message = "Subscriptions are named after the instance and tagged."
  }
}

run "bring_your_own_monitoring_role" {
  command = plan

  variables {
    iam_role = { create = false, arn = "arn:aws:iam::123456789012:role/rds-monitoring" }
  }

  assert {
    condition     = length(module.monitoring_role) == 0 && aws_db_instance.this.monitoring_role_arn == "arn:aws:iam::123456789012:role/rds-monitoring" && output.monitoring_role_arn == "arn:aws:iam::123456789012:role/rds-monitoring"
    error_message = "A caller role must replace the monitoring role."
  }
}

run "extend_the_monitoring_role" {
  command = plan

  variables {
    iam_role = {
      permissions_boundary_arn = "arn:aws:iam::123456789012:policy/boundary"
      policy_statements        = [{ sid = "Extra", actions = ["logs:PutLogEvents"], resources = ["arn:aws:logs:eu-west-1:123456789012:log-group:RDSOSMetrics:*"] }]
    }
  }

  assert {
    condition     = [for s in jsondecode(module.monitoring_role[0].policy_json).Statement : s.Sid] == ["Extra"]
    error_message = "Caller statements must be added to the monitoring role."
  }
}

run "custom_sizing" {
  command = plan

  variables {
    engine_version      = "16.4"
    instance_class      = "db.r8g.large"
    multi_az            = false
    deletion_protection = false
    storage             = { allocated_storage = 100, max_allocated_storage = 0, type = "io2", iops = 3000 }
    parameters          = { "log_min_duration_statement" = { value = "500" }, "shared_preload_libraries" = { value = "pg_stat_statements", apply_method = "pending-reboot" } }
    monitoring_interval = 15
    port                = 5433
  }

  assert {
    condition     = !aws_db_instance.this.multi_az && !aws_db_instance.this.deletion_protection && aws_db_instance.this.storage_type == "io2" && aws_db_instance.this.iops == 3000 && aws_db_instance.this.max_allocated_storage == 0
    error_message = "Sizing and protection overrides must apply."
  }

  assert {
    condition     = aws_db_parameter_group.this.family == "postgres16" && length(aws_db_parameter_group.this.parameter) == 3 && aws_db_instance.this.monitoring_interval == 15 && aws_db_instance.this.port == 5433
    error_message = "Parameters are added to rds.force_ssl in the family of the version."
  }
}

run "long_identifier_is_truncated_to_63" {
  command = plan

  variables {
    application = "customer-onboarding-plat"
    environment = "production01"
    name        = "orders-reconciliation-ledger-001"
  }

  assert {
    condition     = length(aws_db_instance.this.identifier) == 63 && startswith(aws_db_instance.this.identifier, "customer-onboarding-plat-production01-orders-reconciliat")
    error_message = "Identifiers must be cut to 63 characters with a hash."
  }

  assert {
    condition     = module.log_group["postgresql"].name == "/aws/rds/instance/${aws_db_instance.this.identifier}/postgresql"
    error_message = "Log groups follow the real identifier."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Orders_DB"
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

run "extended_support_opt_in" {
  command = plan

  variables {
    extended_support = true
  }

  assert {
    condition     = aws_db_instance.this.engine_lifecycle_support == "open-source-rds-extended-support"
    error_message = "Extended Support only when asked."
  }
}

run "rejects_old_engine_version" {
  command = plan

  variables {
    engine_version = "14"
  }

  expect_failures = [var.engine_version]
}

run "rejects_invalid_instance_class" {
  command = plan

  variables {
    instance_class = "m7g.large"
  }

  expect_failures = [var.instance_class]
}

run "rejects_unknown_storage_type" {
  command = plan

  variables {
    storage = { type = "standard" }
  }

  expect_failures = [var.storage]
}

run "rejects_autoscaling_limit_below_size" {
  command = plan

  variables {
    storage = { allocated_storage = 100, max_allocated_storage = 50 }
  }

  expect_failures = [var.storage]
}

run "rejects_force_ssl_override" {
  command = plan

  variables {
    parameters = { "rds.force_ssl" = { value = "0" } }
  }

  expect_failures = [var.parameters]
}

run "rejects_unknown_apply_method" {
  command = plan

  variables {
    parameters = { "work_mem" = { value = "65536", apply_method = "later" } }
  }

  expect_failures = [var.parameters]
}

run "rejects_invalid_username" {
  command = plan

  variables {
    credential = { username = "1admin" }
  }

  expect_failures = [var.credential]
}

run "rejects_default_admin_username" {
  command = plan

  variables {
    credential = { username = "Postgres" }
  }

  expect_failures = [var.credential]
}

run "rejects_password_with_managed_secret" {
  command = plan

  variables {
    password_wo         = "correct-horse-battery-staple"
    password_wo_version = 1
  }

  expect_failures = [var.password_wo]
}

run "rejects_no_password_source" {
  command = plan

  variables {
    credential = { manage_master_user_password = false }
  }

  expect_failures = [var.password_wo]
}

run "rejects_password_without_version" {
  command = plan

  variables {
    credential  = { manage_master_user_password = false }
    password_wo = "correct-horse-battery-staple"
  }

  expect_failures = [var.password_wo_version]
}

run "rejects_one_subnet" {
  command = plan

  variables {
    subnet_ids = ["subnet-0123456789abcdef0"]
  }

  expect_failures = [var.subnet_ids]
}

run "rejects_low_port" {
  command = plan

  variables {
    port = 80
  }

  expect_failures = [var.port]
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
    kms = { key_id = "alias/orders" }
  }

  expect_failures = [var.kms]
}

run "rejects_short_backup_retention" {
  command = plan

  variables {
    backup_retention_period = 6
  }

  expect_failures = [var.backup_retention_period]
}

run "rejects_backup_replication_without_key" {
  command = plan

  variables {
    backup_replication = { enabled = true, region = "eu-central-1" }
  }

  expect_failures = [var.backup_replication]
}

run "rejects_invalid_backup_region" {
  command = plan

  variables {
    backup_replication = { enabled = true, region = "frankfurt", kms_key_arn = "arn:aws:kms:eu-central-1:123456789012:key/33333333-2222-3333-4444-555555555555" }
  }

  expect_failures = [var.backup_replication]
}

run "rejects_monitoring_off" {
  command = plan

  variables {
    monitoring_interval = 0
  }

  expect_failures = [var.monitoring_interval]
}

run "rejects_role_without_arn" {
  command = plan

  variables {
    iam_role = { create = false }
  }

  expect_failures = [var.iam_role]
}

run "rejects_invalid_performance_insights_retention" {
  command = plan

  variables {
    performance_insights_retention_period = 30
  }

  expect_failures = [var.performance_insights_retention_period]
}

run "rejects_exports_without_postgresql" {
  command = plan

  variables {
    cloudwatch_logs = { exports = ["upgrade"] }
  }

  expect_failures = [var.cloudwatch_logs]
}

run "rejects_subscription_without_topic" {
  command = plan

  variables {
    event_subscription = { enabled = true }
  }

  expect_failures = [var.event_subscription]
}

run "rejects_subscription_without_critical_categories" {
  command = plan

  variables {
    event_subscription = { enabled = true, sns_topic_arn = "arn:aws:sns:eu-west-1:123456789012:core-prod-alarms", event_categories = ["failure"] }
  }

  expect_failures = [var.event_subscription]
}
