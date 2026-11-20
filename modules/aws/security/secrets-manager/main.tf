module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags
  names = {
    secret = { max_length = 512 }
  }
}

module "encryption" {
  source = "../../core/encryption"

  application = var.application
  environment = var.environment
  name        = var.name
  purpose     = "secrets"
  tags        = var.tags
  kms         = merge(var.kms, { create = var.kms.create && !local.multi_region_key })
}

module "key" {
  source = "../kms"
  count  = local.multi_region_key ? 1 : 0

  application             = var.application
  environment             = var.environment
  name                    = var.name
  purpose                 = "secrets"
  tags                    = var.tags
  deletion_window_in_days = var.kms.deletion_window_in_days
  multi_region            = true
  replica_regions         = keys(var.replica_regions)
  policy_statements       = var.kms.policy_statements
}

module "policy" {
  source = "../../core/policy-document"

  default_resources = ["*"]
  statements        = var.policy_statements
}

resource "aws_secretsmanager_secret" "this" {
  name                    = local.secret_name
  description             = coalesce(var.description, "${local.secret_name} secret")
  kms_key_id              = local.kms_key_arn
  recovery_window_in_days = var.recovery_window_in_days

  dynamic "replica" {
    for_each = var.replica_regions

    content {
      region     = replica.key
      kms_key_id = replica.value.kms_key_arn != null ? replica.value.kms_key_arn : try(local.replica_key_arns[replica.key], null)
    }
  }

  tags = merge(module.naming.tags, { Name = local.secret_name })
}

resource "aws_secretsmanager_secret_version" "this" {
  count = var.secret_string_wo_version == null ? 0 : 1

  secret_id                = aws_secretsmanager_secret.this.id
  secret_string_wo         = var.secret_string_wo
  secret_string_wo_version = var.secret_string_wo_version
}

resource "aws_secretsmanager_secret_policy" "this" {
  count = length(var.policy_statements) > 0 ? 1 : 0

  secret_arn          = aws_secretsmanager_secret.this.arn
  policy              = module.policy.json
  block_public_policy = true
}

resource "aws_secretsmanager_secret_rotation" "this" {
  count = var.rotation.enabled ? 1 : 0

  secret_id           = aws_secretsmanager_secret.this.id
  rotation_lambda_arn = var.rotation.lambda_arn
  rotate_immediately  = var.rotation.rotate_immediately

  rotation_rules {
    automatically_after_days = var.rotation.schedule_expression == null ? var.rotation.automatically_after_days : null
    schedule_expression      = var.rotation.schedule_expression
    duration                 = var.rotation.duration
  }
}
