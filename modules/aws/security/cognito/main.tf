module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags
  names = {
    pool       = { max_length = 128 }
    domain     = { uniqueness = "global", max_length = 63 }
    ses_policy = { suffix = "cognito", max_length = 64 }
  }
}

module "encryption" {
  source = "../../core/encryption"

  application        = var.application
  environment        = var.environment
  name               = var.name
  purpose            = "cognito"
  tags               = var.tags
  kms                = var.kms
  service_statements = local.kms_service_statements
}

module "log_group" {
  source = "../../observability/log-group"
  count  = var.cloudwatch_logs.enabled ? 1 : 0

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

resource "aws_cognito_user_pool" "this" {
  name                     = local.pool_name
  user_pool_tier           = var.user_pool_tier
  deletion_protection      = var.deletion_protection ? "ACTIVE" : "INACTIVE"
  mfa_configuration        = var.mfa_configuration
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  admin_create_user_config {
    allow_admin_create_user_only = !var.self_sign_up.enabled

    invite_message_template {
      email_subject = var.invite_message.email_subject
      email_message = var.invite_message.email_message
    }
  }

  verification_message_template {
    default_email_option  = var.verification_message.default_email_option
    email_subject         = var.verification_message.email_subject
    email_message         = var.verification_message.email_message
    email_subject_by_link = var.verification_message.email_subject_by_link
    email_message_by_link = var.verification_message.email_message_by_link
  }

  email_configuration {
    email_sending_account  = var.email.sending_account
    source_arn             = var.email.ses_identity_arn
    from_email_address     = var.email.from_email_address
    reply_to_email_address = var.email.reply_to_email_address
    configuration_set      = var.email.configuration_set
  }

  password_policy {
    minimum_length                   = var.password_policy.minimum_length
    password_history_size            = var.user_pool_tier == "LITE" ? null : var.password_policy.password_history_size
    require_lowercase                = var.password_policy.require_lowercase
    require_numbers                  = var.password_policy.require_numbers
    require_symbols                  = var.password_policy.require_symbols
    require_uppercase                = var.password_policy.require_uppercase
    temporary_password_validity_days = var.password_policy.temporary_password_validity_days
  }

  software_token_mfa_configuration {
    enabled = true
  }

  device_configuration {
    challenge_required_on_new_device      = true
    device_only_remembered_on_user_prompt = true
  }

  username_configuration {
    case_sensitive = false
  }

  user_attribute_update_settings {
    attributes_require_verification_before_update = ["email"]
  }

  dynamic "sign_in_policy" {
    for_each = var.user_pool_tier == "LITE" ? [] : [1]

    content {
      allowed_first_auth_factors = var.allowed_first_auth_factors
    }
  }

  dynamic "web_authn_configuration" {
    for_each = contains(var.allowed_first_auth_factors, "WEB_AUTHN") ? [1] : []

    content {
      relying_party_id  = var.web_authn.relying_party_id
      user_verification = var.web_authn.user_verification
    }
  }

  dynamic "user_pool_add_ons" {
    for_each = var.threat_protection.enabled ? [1] : []

    content {
      advanced_security_mode = var.threat_protection.mode

      dynamic "advanced_security_additional_flows" {
        for_each = var.threat_protection.custom_auth_mode == null ? [] : [1]

        content {
          custom_auth_mode = var.threat_protection.custom_auth_mode
        }
      }
    }
  }

  schema {
    name                     = "email"
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                  = true
    required                 = true

    string_attribute_constraints {
      min_length = "5"
      max_length = "2048"
    }
  }

  dynamic "schema" {
    for_each = var.custom_attributes

    content {
      name                     = schema.key
      attribute_data_type      = schema.value.type
      developer_only_attribute = schema.value.developer_only
      mutable                  = schema.value.mutable
      required                 = false

      dynamic "string_attribute_constraints" {
        for_each = schema.value.type == "String" && (schema.value.min_length != null || schema.value.max_length != null) ? [1] : []

        content {
          min_length = schema.value.min_length == null ? null : tostring(schema.value.min_length)
          max_length = schema.value.max_length == null ? null : tostring(schema.value.max_length)
        }
      }

      dynamic "number_attribute_constraints" {
        for_each = schema.value.type == "Number" && (schema.value.min_value != null || schema.value.max_value != null) ? [1] : []

        content {
          min_value = schema.value.min_value == null ? null : tostring(schema.value.min_value)
          max_value = schema.value.max_value == null ? null : tostring(schema.value.max_value)
        }
      }
    }
  }

  dynamic "lambda_config" {
    for_each = length(var.lambda_triggers) > 0 ? [1] : []

    content {
      create_auth_challenge          = try(local.trigger["create_auth_challenge"], null)
      custom_message                 = try(local.trigger["custom_message"], null)
      define_auth_challenge          = try(local.trigger["define_auth_challenge"], null)
      post_authentication            = try(local.trigger["post_authentication"], null)
      post_confirmation              = try(local.trigger["post_confirmation"], null)
      pre_authentication             = try(local.trigger["pre_authentication"], null)
      pre_sign_up                    = try(local.trigger["pre_sign_up"], null)
      user_migration                 = try(local.trigger["user_migration"], null)
      verify_auth_challenge_response = try(local.trigger["verify_auth_challenge_response"], null)
      kms_key_id                     = local.custom_senders ? local.kms_key_arn : null

      dynamic "pre_token_generation_config" {
        for_each = contains(keys(var.lambda_triggers), "pre_token_generation") ? [var.lambda_triggers["pre_token_generation"]] : []

        content {
          lambda_arn     = pre_token_generation_config.value.arn
          lambda_version = pre_token_generation_config.value.version
        }
      }

      dynamic "custom_email_sender" {
        for_each = contains(keys(var.lambda_triggers), "custom_email_sender") ? [var.lambda_triggers["custom_email_sender"]] : []

        content {
          lambda_arn     = custom_email_sender.value.arn
          lambda_version = custom_email_sender.value.version
        }
      }

      dynamic "custom_sms_sender" {
        for_each = contains(keys(var.lambda_triggers), "custom_sms_sender") ? [var.lambda_triggers["custom_sms_sender"]] : []

        content {
          lambda_arn     = custom_sms_sender.value.arn
          lambda_version = custom_sms_sender.value.version
        }
      }
    }
  }

  tags = merge(module.naming.tags, { Name = local.pool_name })
}

resource "aws_cognito_log_delivery_configuration" "this" {
  count = var.cloudwatch_logs.enabled ? 1 : 0

  user_pool_id = aws_cognito_user_pool.this.id

  log_configurations {
    event_source = "userNotification"
    log_level    = "ERROR"

    cloud_watch_logs_configuration {
      log_group_arn = module.log_group[0].arn
    }
  }

  dynamic "log_configurations" {
    for_each = local.auth_events ? [1] : []

    content {
      event_source = "userAuthEvents"
      log_level    = "INFO"

      cloud_watch_logs_configuration {
        log_group_arn = module.log_group[0].arn
      }
    }
  }
}

resource "aws_cognito_risk_configuration" "this" {
  count = local.auth_events ? 1 : 0

  user_pool_id = aws_cognito_user_pool.this.id

  compromised_credentials_risk_configuration {
    event_filter = ["SIGN_IN", "PASSWORD_CHANGE", "SIGN_UP"]

    actions {
      event_action = "BLOCK"
    }
  }

  account_takeover_risk_configuration {
    actions {
      low_action {
        event_action = "NO_ACTION"
        notify       = false
      }

      medium_action {
        event_action = "MFA_IF_CONFIGURED"
        notify       = false
      }

      high_action {
        event_action = "BLOCK"
        notify       = false
      }
    }
  }
}

resource "aws_cognito_user_pool_client" "this" {
  for_each = var.clients

  name                                 = each.key
  user_pool_id                         = aws_cognito_user_pool.this.id
  generate_secret                      = each.value.generate_secret
  prevent_user_existence_errors        = "ENABLED"
  enable_token_revocation              = true
  explicit_auth_flows                  = each.value.explicit_auth_flows
  read_attributes                      = coalesce(each.value.read_attributes, local.read_attributes)
  write_attributes                     = coalesce(each.value.write_attributes, local.write_attributes)
  access_token_validity                = each.value.access_token_validity_minutes
  id_token_validity                    = each.value.id_token_validity_minutes
  refresh_token_validity               = each.value.refresh_token_validity_days
  callback_urls                        = length(each.value.callback_urls) > 0 ? each.value.callback_urls : null
  logout_urls                          = length(each.value.logout_urls) > 0 ? each.value.logout_urls : null
  allowed_oauth_flows_user_pool_client = length(each.value.allowed_oauth_flows) > 0
  allowed_oauth_flows                  = length(each.value.allowed_oauth_flows) > 0 ? each.value.allowed_oauth_flows : null
  allowed_oauth_scopes                 = length(each.value.allowed_oauth_scopes) > 0 ? each.value.allowed_oauth_scopes : null
  supported_identity_providers         = each.value.supported_identity_providers

  dynamic "refresh_token_rotation" {
    for_each = each.value.refresh_token_rotation.enabled ? [each.value.refresh_token_rotation] : []

    content {
      feature                    = "ENABLED"
      retry_grace_period_seconds = refresh_token_rotation.value.retry_grace_period_seconds
    }
  }

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}

resource "aws_cognito_user_group" "this" {
  for_each = var.groups

  name         = each.key
  user_pool_id = aws_cognito_user_pool.this.id
  description  = each.value.description
  precedence   = each.value.precedence
  role_arn     = each.value.role_arn
}

resource "aws_cognito_user_pool_domain" "this" {
  count = var.domain.enabled ? 1 : 0

  domain                = coalesce(var.domain.custom_domain, module.naming.names.domain)
  user_pool_id          = aws_cognito_user_pool.this.id
  certificate_arn       = var.domain.certificate_arn
  managed_login_version = local.managed_login_version
}

resource "aws_cognito_managed_login_branding" "this" {
  for_each = local.managed_login ? toset(keys(var.clients)) : toset([])

  user_pool_id                = aws_cognito_user_pool.this.id
  client_id                   = aws_cognito_user_pool_client.this[each.key].id
  use_cognito_provided_values = true

  depends_on = [aws_cognito_user_pool_domain.this]
}

resource "aws_sesv2_email_identity_policy" "this" {
  count = var.email.sending_account == "DEVELOPER" ? 1 : 0

  region         = local.ses_identity_region
  email_identity = local.ses_identity
  policy_name    = module.naming.names.ses_policy
  policy         = local.ses_identity_policy
}
