locals {
  pool_name      = module.naming.names.pool
  kms_key_arn    = module.encryption.key_arn
  pool_arn       = aws_cognito_user_pool.this.arn
  log_group_name = "/aws/vendedlogs/cognito/${local.pool_name}"
  log_group_arn  = "arn:${module.naming.partition}:logs:${module.naming.region}:${module.naming.account_id}:log-group:${local.log_group_name}"
  auth_events    = var.user_pool_tier == "PLUS" && var.threat_protection.enabled
  custom_senders = length(setintersection(toset(keys(var.lambda_triggers)), toset(["custom_email_sender", "custom_sms_sender"]))) > 0

  managed_login_version = coalesce(var.domain.managed_login_version, var.user_pool_tier == "LITE" ? 1 : 2)
  managed_login         = var.domain.enabled && local.managed_login_version == 2
  ses_identity          = try(regex(":identity/(.+)$", var.email.ses_identity_arn)[0], null)
  ses_identity_region   = try(split(":", var.email.ses_identity_arn)[3], null)

  kms_service_statements = [{
    sid        = "AllowCloudWatchLogs"
    actions    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    principals = { Service = ["logs.${module.naming.region}.${module.naming.dns_suffix}"] }
    conditions = [{ test = "ArnLike", variable = "kms:EncryptionContext:aws:logs:arn", values = [local.log_group_arn] }]
  }]

  custom_attribute_names = [for k in keys(var.custom_attributes) : "custom:${k}"]
  read_attributes        = concat(var.read_attributes, local.custom_attribute_names)
  write_attributes       = concat(var.write_attributes, local.custom_attribute_names)

  trigger = { for k, t in var.lambda_triggers : k => t.arn }

  ses_identity_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCognitoToSend"
      Effect    = "Allow"
      Principal = { Service = ["cognito-idp.${module.naming.dns_suffix}", "email.cognito-idp.${module.naming.dns_suffix}"] }
      Action    = ["ses:SendEmail", "ses:SendRawEmail"]
      Resource  = var.email.ses_identity_arn
      Condition = {
        StringEquals = { "aws:SourceAccount" = module.naming.account_id }
        ArnLike      = { "aws:SourceArn" = local.pool_arn }
      }
    }]
  })
}
