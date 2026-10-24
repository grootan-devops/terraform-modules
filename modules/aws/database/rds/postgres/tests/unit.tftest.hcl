# output "username" is derived from the sensitive var.credential but is not
# marked sensitive, so any plan that includes aws_db_instance.this fails when
# this module is the root module, as it is under `terraform test`
# ("Output refers to sensitive values"). Until that output is fixed, every run
# targets the resources that do not depend on the DB instance, and
# aws_db_instance.this, aws_db_instance_automated_backups_replication.this and
# the outputs are left untested.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"sts:AssumeRole\",\"Principal\":{\"Service\":\"monitoring.rds.amazonaws.com\"}}]}"
    }
  }
}

# The module declares configuration_aliases = [aws.replica] for cross-region
# automated backup replication.
mock_provider "aws" {
  alias = "replica"
}

variables {
  application    = "core"
  environment    = "prod"
  name           = "db"
  engine_version = "16.3"
  instance_class = "db.t4g.medium"
  multi_az       = true
  vpc_id         = "vpc-0a1b2c3d4e5f67890"
  subnet_ids     = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  kms_key_id     = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"

  credential = {
    username = "dbadmin"
    password = sha256("rds-postgres-test-fixture")
  }

  backup_retention_period                  = 30
  monitoring_interval                      = 0
  performance_insights_retention_period    = 7
  automated_backup_replication_kms_key_arn = "arn:aws:kms:us-east-1:123456789012:key/87654321-4321-4321-4321-210987654321"

  cloudwatch_logs = {
    retention_in_days = {
      postgresql        = 90
      upgrade           = 30
      iam-db-auth-error = 14
    }
    kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/abcdefab-1234-1234-1234-abcdefabcdef"
  }
}

# ------------------------------------------------------------------------------
# Naming
# ------------------------------------------------------------------------------

run "verify_rendered_names" {
  command = plan

  plan_options {
    target = [
      aws_db_subnet_group.this,
      aws_db_parameter_group.this,
      aws_security_group.this,
      aws_cloudwatch_log_group.this,
      aws_cloudwatch_log_metric_filter.postgresql_error_warning_fatal_panic,
      aws_cloudwatch_log_metric_filter.postgresql_auth_failure,
      aws_cloudwatch_query_definition.recent_errors,
      aws_cloudwatch_query_definition.slow_queries,
      aws_iam_role_policy_attachment.enhanced_monitoring,
    ]
  }

  assert {
    condition     = aws_db_subnet_group.this.name == "core-prod-db-sng"
    error_message = "Subnet group name must be the rendered name with a -sng suffix."
  }

  assert {
    condition     = aws_db_parameter_group.this.name == "core-prod-db-postgres"
    error_message = "Parameter group name must be the rendered name with a -postgres suffix."
  }

  assert {
    condition     = aws_security_group.this.name == "core-prod-db-rds"
    error_message = "Security group name must be the rendered name with a -rds suffix."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this["postgresql"].name == "/aws/rds/instance/core-prod-db/postgresql" && aws_cloudwatch_log_group.this["upgrade"].name == "/aws/rds/instance/core-prod-db/upgrade"
    error_message = "Log group names must follow the RDS /aws/rds/instance/<identifier>/<type> convention."
  }

  assert {
    condition     = aws_cloudwatch_log_metric_filter.postgresql_error_warning_fatal_panic[0].name == "core-prod-db-error-warning-fatal-panic" && aws_cloudwatch_log_metric_filter.postgresql_auth_failure[0].name == "core-prod-db-auth-failures"
    error_message = "Metric filter names must be derived from the rendered name."
  }

  assert {
    condition     = aws_cloudwatch_log_metric_filter.postgresql_error_warning_fatal_panic[0].metric_transformation[0].namespace == "Custom/RDSPostgreSQLLogs/core-prod-db"
    error_message = "Metric namespace must be derived from the rendered name."
  }

  assert {
    condition     = aws_cloudwatch_query_definition.recent_errors[0].name == "RDS/core-prod-db/RecentErrors" && aws_cloudwatch_query_definition.slow_queries[0].name == "RDS/core-prod-db/SlowQueries"
    error_message = "Query definition names must be derived from the rendered name."
  }

  assert {
    condition     = aws_db_parameter_group.this.description == "Database parameter group for core db" && aws_db_subnet_group.this.description == "Database subnet group for core db" && aws_security_group.this.description == "Security Group for RDS instance core db"
    error_message = "Descriptions must include application and name."
  }
}

run "verify_name_fallback_when_null" {
  command = plan

  plan_options {
    target = [
      aws_db_subnet_group.this,
      aws_db_parameter_group.this,
      aws_security_group.this,
      aws_cloudwatch_log_group.this,
    ]
  }

  variables {
    name = null
  }

  assert {
    condition     = aws_db_subnet_group.this.name == "core-prod-sng" && aws_db_parameter_group.this.name == "core-prod-postgres" && aws_security_group.this.name == "core-prod-rds"
    error_message = "A null name must fall back to <application>-<environment>."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this["postgresql"].name == "/aws/rds/instance/core-prod/postgresql"
    error_message = "Log group names must use the <application>-<environment> fallback."
  }

  assert {
    condition     = aws_db_parameter_group.this.description == "Database parameter group for core"
    error_message = "Descriptions must fall back to the application name alone."
  }
}

# ------------------------------------------------------------------------------
# Tags
# ------------------------------------------------------------------------------

run "verify_governance_tags" {
  command = plan

  plan_options {
    target = [
      aws_db_subnet_group.this,
      aws_db_parameter_group.this,
      aws_security_group.this,
      aws_cloudwatch_log_group.this,
    ]
  }

  assert {
    condition     = aws_db_subnet_group.this.tags["Application"] == "core" && aws_db_subnet_group.this.tags["Environment"] == "prod" && aws_db_subnet_group.this.tags["Name"] == "core-prod-db-sng"
    error_message = "Subnet group must carry governance tags with its own Name."
  }

  assert {
    condition     = aws_db_parameter_group.this.tags["Application"] == "core" && aws_db_parameter_group.this.tags["Environment"] == "prod" && aws_db_parameter_group.this.tags["Name"] == "core-prod-db-postgres"
    error_message = "Parameter group must carry governance tags with its own Name."
  }

  assert {
    condition     = aws_security_group.this.tags["Application"] == "core" && aws_security_group.this.tags["Environment"] == "prod" && aws_security_group.this.tags["Name"] == "core-prod-db-rds"
    error_message = "Security group must carry governance tags with its own Name."
  }

  assert {
    condition = alltrue([
      for k, lg in aws_cloudwatch_log_group.this :
      lg.tags["Application"] == "core" && lg.tags["Environment"] == "prod" && lg.tags["Name"] == "/aws/rds/instance/core-prod-db/${k}"
    ])
    error_message = "Log groups must carry governance tags with their own Name."
  }
}

run "verify_caller_tags_preserved" {
  command = plan

  plan_options {
    target = [
      aws_db_subnet_group.this,
      aws_db_parameter_group.this,
      aws_security_group.this,
      aws_cloudwatch_log_group.this,
      aws_iam_role_policy_attachment.enhanced_monitoring,
    ]
  }

  variables {
    monitoring_interval = 60
    tags = {
      AuditLevel = "PCI-DSS-L1"
      CostCenter = "1234"
    }
  }

  assert {
    condition = alltrue([
      for t in concat(
        [
          aws_db_subnet_group.this.tags,
          aws_db_parameter_group.this.tags,
          aws_security_group.this.tags,
          aws_iam_role.enhanced_monitoring[0].tags,
        ],
        [for lg in aws_cloudwatch_log_group.this : lg.tags],
      ) : t["AuditLevel"] == "PCI-DSS-L1" && t["CostCenter"] == "1234" && t["Application"] == "core" && t["Environment"] == "prod"
    ])
    error_message = "Caller tags must be preserved alongside governance tags on every taggable resource."
  }

  assert {
    condition     = aws_db_subnet_group.this.tags["Name"] == "core-prod-db-sng" && aws_iam_role.enhanced_monitoring[0].tags["Name"] == "core-prod-db-monitoring-role"
    error_message = "Name tags must survive caller tags."
  }
}

# ------------------------------------------------------------------------------
# Security defaults
# ------------------------------------------------------------------------------

run "verify_security_defaults" {
  command = plan

  plan_options {
    target = [
      aws_db_parameter_group.this,
      aws_cloudwatch_log_group.this,
    ]
  }

  assert {
    condition     = length([for p in aws_db_parameter_group.this.parameter : p if p.name == "rds.force_ssl" && p.value == "1"]) == 1
    error_message = "The parameter group must enforce rds.force_ssl = 1."
  }

  assert {
    condition     = alltrue([for lg in aws_cloudwatch_log_group.this : lg.kms_key_id == var.cloudwatch_logs.kms_key_arn])
    error_message = "Every log group must be encrypted with cloudwatch_logs.kms_key_arn."
  }

  assert {
    condition     = alltrue([for lg in aws_cloudwatch_log_group.this : lg.deletion_protection_enabled == true])
    error_message = "Log group deletion protection must be enabled by default."
  }
}

run "verify_force_ssl_cannot_be_overridden" {
  command = plan

  plan_options {
    target = [aws_db_parameter_group.this]
  }

  variables {
    parameters = [
      { name = "rds.force_ssl", value = "0" },
      { name = "shared_preload_libraries", value = "pg_stat_statements", apply_method = "pending-reboot" },
      { name = "log_min_duration_statement", value = "500" }
    ]
  }

  assert {
    condition     = length([for p in aws_db_parameter_group.this.parameter : p if p.name == "rds.force_ssl"]) == 1
    error_message = "Only the module's own rds.force_ssl parameter may be present."
  }

  assert {
    condition     = length([for p in aws_db_parameter_group.this.parameter : p if p.name == "rds.force_ssl" && p.value == "1"]) == 1
    error_message = "A caller-supplied rds.force_ssl must not weaken SSL enforcement."
  }

  assert {
    condition     = length([for p in aws_db_parameter_group.this.parameter : p if p.name == "shared_preload_libraries" && p.value == "pg_stat_statements" && p.apply_method == "pending-reboot"]) == 1
    error_message = "Caller parameters must pass through with their apply_method."
  }

  assert {
    condition     = length([for p in aws_db_parameter_group.this.parameter : p if p.name == "log_min_duration_statement" && p.value == "500" && p.apply_method == "immediate"]) == 1
    error_message = "Caller parameters without apply_method must default to immediate."
  }

  assert {
    condition     = length(aws_db_parameter_group.this.parameter) == 3
    error_message = "The parameter group must hold rds.force_ssl plus the caller's other parameters."
  }
}

# ------------------------------------------------------------------------------
# Parameters
# ------------------------------------------------------------------------------

run "verify_shipped_defaults" {
  command = plan

  plan_options {
    target = [
      aws_db_subnet_group.this,
      aws_db_parameter_group.this,
      aws_security_group.this,
      aws_cloudwatch_log_group.this,
      aws_cloudwatch_log_metric_filter.postgresql_error_warning_fatal_panic,
      aws_cloudwatch_log_metric_filter.postgresql_auth_failure,
      aws_cloudwatch_query_definition.recent_errors,
      aws_cloudwatch_query_definition.slow_queries,
      aws_iam_role_policy_attachment.enhanced_monitoring,
    ]
  }

  assert {
    condition     = aws_db_parameter_group.this.family == "postgres16"
    error_message = "Parameter group family must be derived from the engine major version."
  }

  assert {
    condition     = length(aws_db_parameter_group.this.parameter) == 1
    error_message = "Only rds.force_ssl must be set when no parameters are passed."
  }

  assert {
    condition     = toset(keys(aws_cloudwatch_log_group.this)) == toset(["postgresql", "upgrade"])
    error_message = "One log group must be created per default export (postgresql, upgrade)."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this["postgresql"].retention_in_days == 90 && aws_cloudwatch_log_group.this["upgrade"].retention_in_days == 30
    error_message = "Log retention must be taken per log type from cloudwatch_logs.retention_in_days."
  }

  assert {
    condition     = alltrue([for lg in aws_cloudwatch_log_group.this : lg.log_group_class == "STANDARD"])
    error_message = "Log groups must use the STANDARD class."
  }

  assert {
    condition     = length(aws_cloudwatch_log_metric_filter.postgresql_error_warning_fatal_panic) == 1 && aws_cloudwatch_log_metric_filter.postgresql_error_warning_fatal_panic[0].log_group_name == "/aws/rds/instance/core-prod-db/postgresql"
    error_message = "The error metric filter must watch the postgresql log group."
  }

  assert {
    condition     = length(aws_cloudwatch_log_metric_filter.postgresql_auth_failure) == 1 && aws_cloudwatch_log_metric_filter.postgresql_auth_failure[0].log_group_name == "/aws/rds/instance/core-prod-db/postgresql"
    error_message = "Without iam-db-auth-error exports, the auth-failure filter must watch the postgresql log group."
  }

  assert {
    condition     = length(aws_cloudwatch_query_definition.recent_errors) == 1 && length(aws_cloudwatch_query_definition.slow_queries) == 1
    error_message = "Logs Insights query definitions must be created when postgresql logs are exported."
  }

  assert {
    condition     = aws_cloudwatch_query_definition.recent_errors[0].log_group_names == tolist(["/aws/rds/instance/core-prod-db/postgresql"])
    error_message = "Query definitions must read the postgresql log group."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.enhanced_monitoring) == 0 && length(aws_iam_role.enhanced_monitoring) == 0
    error_message = "No enhanced monitoring role must be created when monitoring_interval is 0."
  }

  assert {
    condition     = length(aws_security_group.this.egress) == 1 && one(aws_security_group.this.egress).cidr_blocks == tolist(["0.0.0.0/0"])
    error_message = "Default egress must allow 0.0.0.0/0."
  }

  assert {
    condition     = aws_db_subnet_group.this.subnet_ids == toset(var.subnet_ids) && aws_security_group.this.vpc_id == var.vpc_id
    error_message = "Subnet group and security group must use the caller's subnets and VPC."
  }
}

run "verify_no_ingress_by_default" {
  # The ingress set is optional+computed, so its contents are only final after apply.
  command = apply

  plan_options {
    target = [aws_security_group.this]
  }

  assert {
    condition     = length(aws_security_group.this.ingress) == 0
    error_message = "No ingress rule must exist when allowed_cidr_blocks is empty."
  }
}

run "verify_enhanced_monitoring_enabled" {
  command = apply

  plan_options {
    target = [aws_iam_role_policy_attachment.enhanced_monitoring]
  }

  variables {
    monitoring_interval = 60
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.enhanced_monitoring) == 1
    error_message = "Enhanced monitoring must create the policy attachment when monitoring_interval > 0."
  }

  assert {
    condition     = aws_iam_role.enhanced_monitoring[0].name == "core-prod-db-monitoring-role"
    error_message = "Monitoring role name must be the rendered name with a -monitoring-role suffix."
  }

  assert {
    condition     = aws_iam_role.enhanced_monitoring[0].tags["Name"] == "core-prod-db-monitoring-role" && aws_iam_role.enhanced_monitoring[0].tags["Application"] == "core" && aws_iam_role.enhanced_monitoring[0].tags["Environment"] == "prod"
    error_message = "Monitoring role must carry governance tags with its own Name."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.enhanced_monitoring[0].policy_arn == "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
    error_message = "Monitoring role must get the AWS managed AmazonRDSEnhancedMonitoringRole policy in the current partition."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.enhanced_monitoring[0].role == aws_iam_role.enhanced_monitoring[0].name
    error_message = "The policy must be attached to the module's monitoring role."
  }

  assert {
    condition     = contains(flatten([for p in data.aws_iam_policy_document.enhanced_monitoring_assume_role.statement[0].principals : p.identifiers]), "monitoring.rds.amazonaws.com")
    error_message = "Monitoring role must be assumable only by monitoring.rds.amazonaws.com."
  }
}

run "verify_overrides" {
  command = plan

  plan_options {
    target = [
      aws_db_parameter_group.this,
      aws_security_group.this,
      aws_cloudwatch_log_group.this,
      aws_cloudwatch_log_metric_filter.postgresql_error_warning_fatal_panic,
      aws_cloudwatch_log_metric_filter.postgresql_auth_failure,
    ]
  }

  variables {
    engine_version      = "17.2"
    allowed_cidr_blocks = ["10.0.0.0/16"]
    egress_cidr_blocks  = ["10.0.0.0/8"]

    cloudwatch_logs = {
      exports = ["postgresql", "upgrade", "iam-db-auth-error"]
      retention_in_days = {
        postgresql        = 365
        upgrade           = 180
        iam-db-auth-error = 60
      }
      kms_key_arn                 = "arn:aws:kms:us-west-2:123456789012:key/abcdefab-1234-1234-1234-abcdefabcdef"
      deletion_protection_enabled = false
    }
  }

  assert {
    condition     = aws_db_parameter_group.this.family == "postgres17"
    error_message = "engine_version override must drive the parameter group family."
  }

  assert {
    condition     = length(aws_security_group.this.ingress) == 1
    error_message = "One ingress rule must be created when allowed_cidr_blocks is set."
  }

  assert {
    condition     = one(aws_security_group.this.ingress).from_port == 5432 && one(aws_security_group.this.ingress).to_port == 5432 && one(aws_security_group.this.ingress).protocol == "tcp" && one(aws_security_group.this.ingress).cidr_blocks == tolist(["10.0.0.0/16"])
    error_message = "Ingress must be limited to TCP 5432 from allowed_cidr_blocks."
  }

  assert {
    condition     = one(aws_security_group.this.egress).cidr_blocks == tolist(["10.0.0.0/8"])
    error_message = "egress_cidr_blocks override must pass through."
  }

  assert {
    condition     = toset(keys(aws_cloudwatch_log_group.this)) == toset(["postgresql", "upgrade", "iam-db-auth-error"])
    error_message = "One log group must be created per export."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this["postgresql"].retention_in_days == 365 && aws_cloudwatch_log_group.this["upgrade"].retention_in_days == 180 && aws_cloudwatch_log_group.this["iam-db-auth-error"].retention_in_days == 60
    error_message = "Per-type retention overrides must pass through."
  }

  assert {
    condition     = alltrue([for lg in aws_cloudwatch_log_group.this : lg.deletion_protection_enabled == false])
    error_message = "cloudwatch_logs.deletion_protection_enabled override must pass through."
  }

  assert {
    condition     = aws_cloudwatch_log_metric_filter.postgresql_auth_failure[0].log_group_name == "/aws/rds/instance/core-prod-db/iam-db-auth-error"
    error_message = "With iam-db-auth-error exported, the auth-failure filter must watch that log group."
  }

  assert {
    condition     = alltrue([for lg in aws_cloudwatch_log_group.this : lg.kms_key_id == var.cloudwatch_logs.kms_key_arn])
    error_message = "Log encryption must hold when other inputs are overridden."
  }
}

run "verify_logs_without_postgresql_export" {
  command = plan

  plan_options {
    target = [
      aws_cloudwatch_log_group.this,
      aws_cloudwatch_log_metric_filter.postgresql_error_warning_fatal_panic,
      aws_cloudwatch_log_metric_filter.postgresql_auth_failure,
      aws_cloudwatch_query_definition.recent_errors,
      aws_cloudwatch_query_definition.slow_queries,
    ]
  }

  variables {
    cloudwatch_logs = {
      exports = ["upgrade"]
      retention_in_days = {
        postgresql        = 90
        upgrade           = 30
        iam-db-auth-error = 14
      }
      kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/abcdefab-1234-1234-1234-abcdefabcdef"
    }
  }

  assert {
    condition     = toset(keys(aws_cloudwatch_log_group.this)) == toset(["upgrade"])
    error_message = "Only the exported log type must get a log group."
  }

  assert {
    condition     = length(aws_cloudwatch_log_metric_filter.postgresql_error_warning_fatal_panic) == 0 && length(aws_cloudwatch_log_metric_filter.postgresql_auth_failure) == 0
    error_message = "Metric filters must not be created without postgresql or iam-db-auth-error exports."
  }

  assert {
    condition     = length(aws_cloudwatch_query_definition.recent_errors) == 0 && length(aws_cloudwatch_query_definition.slow_queries) == 0
    error_message = "Query definitions must not be created without postgresql exports."
  }
}

# ------------------------------------------------------------------------------
# Validation
# ------------------------------------------------------------------------------

run "verify_invalid_environment_fails" {
  command = plan

  plan_options {
    target = [aws_db_parameter_group.this]
  }

  variables {
    environment = "INVALID_UPPERCASE"
  }

  expect_failures = [var.environment]
}

run "verify_invalid_cloudwatch_log_export_fails" {
  command = plan

  # With targeting, a variable is only validated when a targeted resource uses it.
  plan_options {
    target = [aws_cloudwatch_log_group.this]
  }

  variables {
    cloudwatch_logs = {
      exports = ["postgresql", "audit"]
      retention_in_days = {
        postgresql        = 90
        upgrade           = 30
        iam-db-auth-error = 14
      }
      kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/abcdefab-1234-1234-1234-abcdefabcdef"
    }
  }

  expect_failures = [var.cloudwatch_logs]
}
