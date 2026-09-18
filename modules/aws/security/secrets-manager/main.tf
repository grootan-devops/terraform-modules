resource "aws_secretsmanager_secret" "this" {
  name                           = local.rendered_name
  name_prefix                    = var.name_prefix
  description                    = var.description
  kms_key_id                     = var.kms_key_arn
  recovery_window_in_days        = var.recovery_window_in_days
  force_overwrite_replica_secret = var.force_overwrite_replica_secret
  type                           = var.type
  region                         = var.region

  tags = local.tags
}

resource "aws_secretsmanager_secret_policy" "this" {
  count = var.policy != null ? 1 : 0

  secret_arn          = aws_secretsmanager_secret.this.arn
  policy              = var.policy
  block_public_policy = var.block_public_policy
  region              = var.region
}

resource "aws_secretsmanager_secret_rotation" "this" {
  count = var.rotation_config != null ? 1 : 0

  secret_id           = aws_secretsmanager_secret.this.id
  rotation_lambda_arn = var.rotation_config.rotation_lambda_arn
  rotate_immediately  = var.rotation_config.rotate_immediately

  rotation_rules {
    automatically_after_days = var.rotation_config.rotation_rules.automatically_after_days
    duration                 = var.rotation_config.rotation_rules.duration
    schedule_expression      = var.rotation_config.rotation_rules.schedule_expression
  }
}

resource "aws_secretsmanager_secret_version" "this" {
  count = (var.secret_string != null || var.secret_binary != null || var.secret_string_wo != null) ? 1 : 0

  secret_id                = aws_secretsmanager_secret.this.id
  secret_string            = var.secret_string
  secret_binary            = var.secret_binary
  secret_string_wo         = var.secret_string_wo
  secret_string_wo_version = var.secret_string_wo_version
  version_stages           = var.version_stages
  region                   = var.region

  lifecycle {
    precondition {
      condition = (
        (var.secret_string != null ? 1 : 0) +
        (var.secret_binary != null ? 1 : 0) +
        (var.secret_string_wo != null ? 1 : 0)
      ) <= 1
      error_message = "Only one of 'secret_string', 'secret_binary', or 'secret_string_wo' may be specified."
    }
  }
}
