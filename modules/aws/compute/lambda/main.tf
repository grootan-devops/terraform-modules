module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags
  names = {
    function = { max_length = 64 }
  }
}

module "encryption" {
  source = "../../core/encryption"

  purpose = "lambda"

  application        = var.application
  environment        = var.environment
  name               = var.name
  tags               = var.tags
  kms                = var.kms
  service_statements = local.kms_service_statements
}

module "log_group" {
  source = "../../observability/log-group"

  application                 = var.application
  environment                 = var.environment
  name                        = var.name
  tags                        = var.tags
  log_group_name              = local.log_group_name
  retention_in_days           = var.cloudwatch_logs.retention_in_days
  log_group_class             = var.cloudwatch_logs.log_group_class
  deletion_protection_enabled = var.cloudwatch_logs.deletion_protection_enabled
  kms_key_arn                 = try(coalesce(var.cloudwatch_logs.kms_key_arn, local.kms_key_arn), null)
}

module "role" {
  source = "../../security/iam-role"
  count  = var.iam_role.create ? 1 : 0

  application              = var.application
  environment              = var.environment
  name                     = var.name
  purpose                  = "exec"
  tags                     = var.tags
  role_name                = var.iam_role.name
  path                     = var.iam_role.path
  permissions_boundary_arn = var.iam_role.permissions_boundary_arn
  managed_policy_arns      = local.managed_policy_arns
  policy_statements        = var.iam_role.policy_statements
  policy_documents         = [jsonencode({ Version = "2012-10-17", Statement = local.role_statements })]
  trust = {
    services   = ["lambda.${module.naming.dns_suffix}"]
    conditions = [{ test = "StringEquals", variable = "aws:SourceAccount", values = [module.naming.account_id] }]
  }
}

module "security_group" {
  source = "../../network/security-group"
  count  = local.in_vpc && var.security_group.create ? 1 : 0

  application  = var.application
  environment  = var.environment
  name         = var.name
  purpose      = "fn"
  tags         = var.tags
  vpc_id       = var.vpc_id
  egress_rules = local.egress_rules
}

resource "aws_lambda_function" "this" {
  function_name           = local.function_name
  description             = coalesce(var.description, "${local.function_name} function")
  role                    = local.role_arn
  package_type            = var.package.type
  runtime                 = local.zip ? var.package.runtime : null
  handler                 = local.handler
  filename                = local.placeholder ? data.archive_file.placeholder[0].output_path : var.package.filename
  s3_bucket               = var.package.s3_bucket
  s3_key                  = var.package.s3_key
  image_uri               = var.package.image_uri
  source_kms_key_arn      = var.package.source_kms_key_arn
  architectures           = [var.architecture]
  memory_size             = var.memory_size
  timeout                 = var.timeout
  layers                  = local.layers
  kms_key_arn             = local.kms_key_arn
  code_signing_config_arn = var.code_signing_config_arn
  publish                 = true

  reserved_concurrent_executions = coalesce(var.concurrency.reserved, -1)

  ephemeral_storage {
    size = var.ephemeral_storage_size
  }

  logging_config {
    log_format            = "JSON"
    log_group             = module.log_group.name
    application_log_level = var.cloudwatch_logs.application_log_level
    system_log_level      = var.cloudwatch_logs.system_log_level
  }

  tracing_config {
    mode = var.tracing
  }

  dynamic "environment" {
    for_each = length(var.environment_variables) > 0 ? [1] : []
    content {
      variables = var.environment_variables
    }
  }

  dynamic "vpc_config" {
    for_each = local.in_vpc ? [1] : []
    content {
      subnet_ids         = var.subnet_ids
      security_group_ids = local.security_group_ids
    }
  }

  dynamic "dead_letter_config" {
    for_each = var.dead_letter_target_arn == null ? [] : [1]
    content {
      target_arn = var.dead_letter_target_arn
    }
  }

  dynamic "durable_config" {
    for_each = var.durable_execution.enabled ? [1] : []
    content {
      execution_timeout = var.durable_execution.execution_timeout
      retention_period  = var.durable_execution.retention_period
    }
  }

  tags = merge(module.naming.tags, { Name = local.function_name })

  depends_on = [module.role]

  lifecycle {
    ignore_changes = [filename, s3_bucket, s3_key, s3_object_version, source_code_hash, image_uri]
  }
}
