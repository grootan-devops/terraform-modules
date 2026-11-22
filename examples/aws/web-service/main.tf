locals {
  db_user           = "app"
  proxy_port        = module.proxy.port
  arn_prefix        = "arn:${module.naming.partition}"
  log_group_prefix  = "${local.arn_prefix}:logs:${module.naming.region}:${module.naming.account_id}:log-group:"
  proxy_db_user_arn = "${module.proxy.db_user_arn_prefix}/${local.db_user}"
}

module "naming" {
  source = "../../../modules/aws/core/naming"

  application = var.application
  environment = var.environment
  names = {
    waf_logs = { uniqueness = "global", max_length = 50 }
  }
}

module "vpc" {
  source = "../../../modules/aws/network/vpc"

  application = var.application
  environment = var.environment
  cidr_block  = "10.20.0.0/16"
}

module "key" {
  source = "../../../modules/aws/security/kms"

  application = var.application
  environment = var.environment
  name        = "data"
  policy_statements = [
    {
      sid        = "AllowAccountServices"
      actions    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:CreateGrant", "kms:ListGrants", "kms:DescribeKey"]
      principals = { AWS = ["*"] }
      conditions = [
        { test = "StringEquals", variable = "kms:CallerAccount", values = [module.naming.account_id] },
        { test = "StringEquals", variable = "kms:ViaService", values = [for s in ["rds", "secretsmanager", "elasticache", "elasticfilesystem"] : "${s}.${module.naming.region}.${module.naming.dns_suffix}"] }
      ]
    },
    {
      sid        = "AllowCloudWatchLogs"
      actions    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
      principals = { Service = ["logs.${module.naming.region}.${module.naming.dns_suffix}"] }
      conditions = [{
        test     = "ArnLike"
        variable = "kms:EncryptionContext:aws:logs:arn"
        values = concat(
          [for p in ["/aws/rds/instance/", "/aws/rds/proxy/", "/aws/elasticache/", "/aws/batch/"] : "${local.log_group_prefix}${p}${module.naming.name}-*"],
          ["${local.log_group_prefix}/app/${module.naming.name}/*"]
        )
      }]
    }
  ]
}

module "logs" {
  source = "../../../modules/aws/storage/log-bucket"

  application = var.application
  environment = var.environment
  name        = "logs"
  elb_logs    = { enabled = true }
}

module "waf_logs" {
  source = "../../../modules/aws/storage/log-bucket"

  application    = var.application
  environment    = var.environment
  name           = "waf-logs"
  bucket_name    = "aws-waf-logs-${module.naming.names["waf_logs"]}"
  s3_access_logs = { enabled = false }
  vended_logs    = { enabled = true }
  access_logs    = { enabled = true, bucket = module.logs.name }
}

module "audit_logs" {
  source = "../../../modules/aws/observability/log-group"

  application       = var.application
  environment       = var.environment
  name              = "audit"
  log_group_name    = "/app/${module.naming.name}/audit"
  retention_in_days = 731
  kms_key_arn       = module.key.arn
}

module "zone" {
  source = "../../../modules/aws/network/route53"

  application = var.application
  environment = var.environment
  zone_name   = var.domain_name
  records = {
    web = { type = "A", alias = { name = module.alb.dns_name, zone_id = module.alb.zone_id, evaluate_target_health = true } }
  }
}

module "cert" {
  source = "../../../modules/aws/security/acm"

  application = var.application
  environment = var.environment
  domain_name = var.domain_name
  validation  = { zone_id = module.zone.zone_id }
}

module "waf" {
  source = "../../../modules/aws/network/waf"

  application      = var.application
  environment      = var.environment
  rate_limit_rules = { per_ip = { limit = 2000 } }
  logging          = { destination = "s3", s3_bucket_arn = module.waf_logs.arn }
}

module "alb" {
  source = "../../../modules/aws/network/alb"

  application          = var.application
  environment          = var.environment
  internal             = false
  vpc_id               = module.vpc.vpc_id
  subnet_ids           = module.vpc.public_subnet_ids
  security_group       = { ingress_cidr_blocks = ["0.0.0.0/0"] }
  https_listener       = { certificate_arn = module.cert.arn }
  target_groups        = { web = { port = 8080 } }
  default_target_group = "web"
  access_logs          = { enabled = true, bucket = module.logs.name }
  waf                  = { enabled = true, web_acl_arn = module.waf.arn }
}

module "private_link" {
  source = "../../../modules/aws/network/nlb"

  application = var.application
  environment = var.environment
  name        = "partners"
  vpc_id      = module.vpc.vpc_id
  subnet_ids  = module.vpc.private_subnet_ids
  listeners   = { https = { port = 443, target_group = "alb" } }
  target_groups = {
    alb = { port = 443, target_type = "alb", health_check = { protocol = "HTTPS", path = "/" }, targets = { alb = { id = module.alb.arn } } }
  }
  security_group   = { egress_security_group_ids = [module.alb.security_group_id] }
  endpoint_service = { enabled = true, allowed_principals = [var.partner_principal_arn] }
}

module "db" {
  source = "../../../modules/aws/database/rds/postgres"

  application    = var.application
  environment    = var.environment
  name           = "orders"
  engine_version = "18"
  vpc_id         = module.vpc.vpc_id
  subnet_ids     = module.vpc.private_subnet_ids
  security_group = { ingress_security_group_ids = [module.proxy.security_group_id] }
  kms            = { key_id = module.key.arn }
}

module "db_clients" {
  source = "../../../modules/aws/network/security-group"

  application = var.application
  environment = var.environment
  name        = "db-clients"
  description = "Clients of the orders database proxy"
  vpc_id      = module.vpc.vpc_id
  egress_rules = {
    proxy = { description = "PostgreSQL to the RDS Proxy", from_port = local.proxy_port, to_port = local.proxy_port, referenced_security_group_id = module.proxy.security_group_id }
  }
}

module "proxy" {
  source = "../../../modules/aws/database/rds/proxy"

  application         = var.application
  environment         = var.environment
  name                = "orders"
  vpc_id              = module.vpc.vpc_id
  subnet_ids          = module.vpc.private_subnet_ids
  default_auth_scheme = "IAM_AUTH"
  target = {
    db_instance_identifier = module.db.id
    port                   = module.db.port
    security_group_ids     = [module.db.security_group_id]
  }
  security_group = { ingress_security_group_ids = [module.db_clients.id] }
  iam_role = {
    policy_statements = [{
      sid       = "ConnectToDatabase"
      actions   = ["rds-db:connect"]
      resources = ["${local.arn_prefix}:rds-db:${module.naming.region}:${module.naming.account_id}:dbuser:${module.db.resource_id}/${local.db_user}"]
    }]
  }
  cloudwatch_logs = { enabled = true, kms_key_arn = module.key.arn }
}

ephemeral "aws_secretsmanager_random_password" "cache_token" {
  password_length     = 64
  exclude_punctuation = true
}

module "cache_token" {
  source = "../../../modules/aws/security/secrets-manager"

  application              = var.application
  environment              = var.environment
  name                     = "cache-token"
  description              = "Valkey AUTH token for the web service"
  kms                      = { key_id = module.key.arn }
  secret_string_wo         = ephemeral.aws_secretsmanager_random_password.cache_token.random_password
  secret_string_wo_version = var.cache_token_version
}

module "cache" {
  source = "../../../modules/aws/database/elasticache/valkey"

  application           = var.application
  environment           = var.environment
  name                  = "cache"
  vpc_id                = module.vpc.vpc_id
  subnet_ids            = module.vpc.private_subnet_ids
  security_group        = { ingress_security_group_ids = [module.app.security_group_id] }
  kms                   = { key_id = module.key.arn }
  auth_token_wo         = ephemeral.aws_secretsmanager_random_password.cache_token.random_password
  auth_token_wo_version = var.cache_token_version
}

module "shared" {
  source = "../../../modules/aws/storage/efs"

  application    = var.application
  environment    = var.environment
  name           = "shared"
  vpc_id         = module.vpc.vpc_id
  subnet_ids     = module.vpc.private_subnet_ids
  security_group = { ingress_security_group_ids = [module.app.security_group_id, module.reports.security_group_id] }
  kms            = { key_id = module.key.arn }
  client_access  = { principal_arns = [module.app.task_role_arns["web"], module.reports.role_arn] }
  access_points = {
    reports = { uid = 1000, gid = 1000, path = "/reports" }
  }
}

module "app" {
  source = "../../../modules/aws/compute/ecs"

  application              = var.application
  environment              = var.environment
  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnet_ids
  readonly_root_filesystem = true
  security_group = {
    ingress_security_group_ids    = [module.alb.security_group_id]
    additional_security_group_ids = [module.db_clients.id]
  }
  services = {
    web = {
      image             = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/shop-web:1.0.0"
      container_port    = 8080
      user              = "1000:1000"
      target_group_arns = [module.alb.target_group_arns["web"]]
      writable_paths    = ["/tmp"]
      environment = {
        DB_HOST         = module.proxy.endpoint
        DB_PORT         = tostring(local.proxy_port)
        DB_USER         = local.db_user
        CACHE_HOST      = module.cache.primary_endpoint_address
        CACHE_PORT      = tostring(module.cache.port)
        AUDIT_LOG_GROUP = module.audit_logs.name
        REPORTS_PATH    = "/mnt/reports"
      }
      secrets = { CACHE_AUTH_TOKEN = module.cache_token.arn }
      efs_volumes = {
        reports = { file_system_id = module.shared.id, access_point_id = module.shared.access_point_ids["reports"], container_path = "/mnt/reports", read_only = true }
      }
      task_role = {
        policy_statements = [
          { sid = "ConnectThroughProxy", actions = ["rds-db:connect"], resources = [local.proxy_db_user_arn] },
          { sid = "WriteAuditLog", actions = ["logs:CreateLogStream", "logs:PutLogEvents"], resources = ["${module.audit_logs.arn}:*"] }
        ]
      }
    }
  }
}

module "reports" {
  source = "../../../modules/aws/compute/batch"

  application              = var.application
  environment              = var.environment
  name                     = "reports"
  readonly_root_filesystem = true
  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnet_ids
  security_group           = { additional_security_group_ids = [module.db_clients.id] }
  kms                      = { key_id = module.key.arn }

  compute_environments = { fargate = { max_vcpus = 16 } }
  job_queues           = { nightly = { priority = 1, compute_environments = ["fargate"] } }
  job_definitions = {
    nightly = {
      image           = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/shop-reports:1.0.0"
      user            = "1000:1000"
      writable_paths  = ["/tmp"]
      timeout_seconds = 3600
      attempts        = 2
      environment = {
        DB_HOST      = module.proxy.endpoint
        DB_PORT      = tostring(local.proxy_port)
        DB_USER      = local.db_user
        REPORTS_PATH = "/mnt/reports"
      }
      efs_volumes = {
        reports = { file_system_id = module.shared.id, access_point_id = module.shared.access_point_ids["reports"], container_path = "/mnt/reports" }
      }
    }
  }
  iam_role = {
    policy_statements = [{ sid = "ConnectThroughProxy", actions = ["rds-db:connect"], resources = [local.proxy_db_user_arn] }]
  }
}

module "reports_dlq" {
  source = "../../../modules/aws/integration/sqs"

  application       = var.application
  environment       = var.environment
  name              = "reports-dlq"
  dead_letter_queue = { enabled = false }
}

module "schedules" {
  source = "../../../modules/aws/integration/eventbridge"

  application = var.application
  environment = var.environment
  name        = "reports"
  bus         = { enabled = false }
  scheduler = {
    enabled = true
    schedules = {
      nightly-reports = {
        expression = "cron(0 3 * * ? *)"
        target = {
          type              = "batch"
          arn               = module.reports.job_queue_arns["nightly"]
          dead_letter_queue = { arn = module.reports_dlq.arn }
          batch             = { job_definition_arn = module.reports.job_definition_arns["nightly"] }
        }
      }
    }
  }
}
