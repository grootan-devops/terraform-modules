module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags
  names = {
    state_machine = { max_length = 80 }
  }
}

module "encryption" {
  source = "../../core/encryption"

  application        = var.application
  environment        = var.environment
  name               = var.name
  purpose            = "sfn"
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
  managed_policy_arns      = var.iam_role.managed_policy_arns
  policy_statements        = var.iam_role.policy_statements
  policy_documents         = [jsonencode({ Version = "2012-10-17", Statement = local.role_statements })]
  trust = {
    services = ["states.${module.naming.dns_suffix}"]
    conditions = [
      { test = "StringEquals", variable = "aws:SourceAccount", values = [module.naming.account_id] },
      { test = "ArnLike", variable = "aws:SourceArn", values = [local.state_machine_arn, "${local.state_machine_arn}:*"] }
    ]
  }
}

resource "aws_sfn_state_machine" "this" {
  name       = local.state_machine_name
  role_arn   = local.role_arn
  type       = var.type
  definition = var.definition

  encryption_configuration {
    type                              = local.customer_key ? "CUSTOMER_MANAGED_KMS_KEY" : "AWS_OWNED_KEY"
    kms_key_id                        = local.kms_key_arn
    kms_data_key_reuse_period_seconds = local.customer_key ? 300 : null
  }

  logging_configuration {
    log_destination        = "${module.log_group.arn}:*"
    level                  = var.cloudwatch_logs.level
    include_execution_data = var.cloudwatch_logs.include_execution_data
  }

  tracing_configuration {
    enabled = var.tracing.enabled
  }

  tags = merge(module.naming.tags, { Name = local.state_machine_name })

  depends_on = [module.role]
}
