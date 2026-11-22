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

  mock_data "aws_availability_zones" {
    defaults = {
      names    = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
      zone_ids = ["euw1-az1", "euw1-az2", "euw1-az3"]
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_data "aws_vpc" {
    defaults = {
      cidr_block = "10.20.0.0/16"
    }
  }

  mock_ephemeral "aws_secretsmanager_random_password" {
    defaults = {
      random_password = sha256("cache-token-fixture")
    }
  }
}

override_resource {
  target          = module.key.aws_kms_key.this
  override_during = plan
  values = {
    arn = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
  }
}

override_resource {
  target          = module.proxy.aws_db_proxy.this
  override_during = plan
  values = {
    arn = "arn:aws:rds:eu-west-1:123456789012:db-proxy:prx-0123456789abcdef0"
  }
}

run "plans_with_unknown_ids" {
  command = plan

  assert {
    condition     = output.alb_name == "shop-dev" && output.log_bucket == "shop-dev-logs-123456789012-eu-west-1"
    error_message = "One-per-environment modules use the base name; buckets carry the account and Region."
  }

  assert {
    condition     = output.nlb_name == "shop-dev-partners-nlb" && output.nlb_name != output.alb_name
    error_message = "The NLB never shares a name with the ALB."
  }

  assert {
    condition     = output.waf_log_bucket == "aws-waf-logs-shop-dev-123456789012-eu-west-1" && output.waf_log_bucket != output.log_bucket && output.web_acl_name == "shop-dev"
    error_message = "WAF logs need their own aws-waf-logs- bucket, named from core/naming."
  }

  assert {
    condition     = module.proxy.name == "shop-dev-orders" && module.proxy.log_group_name == "/aws/rds/proxy/shop-dev-orders" && !contains(values(module.db.log_group_names), module.proxy.log_group_name)
    error_message = "The proxy and the instance it fronts share the name, never a log group."
  }

  assert {
    condition     = length(distinct([module.proxy.role_name, module.reports.role_name, module.app.task_role_names["web"]])) == 3
    error_message = "Every role that reaches the database is its own role."
  }

  assert {
    condition     = output.cache_token_secret_name == "shop-dev-cache-token" && module.cache.id == "shop-dev-cache" && output.kms_key_alias == "alias/shop-dev-data"
    error_message = "Cache, its token secret and the shared key follow the naming standard."
  }

  assert {
    condition     = output.audit_log_group == "/app/shop-dev/audit" && output.file_system_name == "shop-dev-shared"
    error_message = "The audit log group and the shared file system follow the naming standard."
  }

  assert {
    condition     = alltrue([for arn in [module.db.kms_key_arn, module.cache.kms_key_arn, module.cache_token.kms_key_arn, module.shared.kms_key_arn, module.reports.kms_key_arn, module.audit_logs.kms_key_arn] : arn == module.key.arn])
    error_message = "Database, cache, token secret, file system, batch logs and audit logs all use the one shared key."
  }

  assert {
    condition     = output.db_proxy_user_arn == "arn:aws:rds-db:eu-west-1:123456789012:dbuser:prx-0123456789abcdef0/app"
    error_message = "Clients connect through the proxy with IAM, scoped to the proxy's resource ID and the app user."
  }

  assert {
    condition     = keys(module.db_clients.egress_rule_ids) == ["proxy"] && length(module.cache.log_group_names) == 2 && keys(module.shared.access_point_ids) == ["reports"]
    error_message = "One client group reaches the proxy; the cache ships two log types; one access point for reports."
  }

  assert {
    condition     = output.report_job_queues == { nightly = "shop-dev-reports-nightly" } && module.schedules.schedule_group_name == "shop-dev-reports" && keys(module.schedules.schedule_arns) == ["nightly-reports"]
    error_message = "The nightly report job runs on its own Batch queue from a Scheduler schedule."
  }
}
