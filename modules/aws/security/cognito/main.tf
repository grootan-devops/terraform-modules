resource "aws_cognito_user_pool" "this" {
  name           = local.rendered_name
  user_pool_tier = var.user_pool_tier

  # Optional: Advanced Security Features
  dynamic "user_pool_add_ons" {
    for_each = var.advanced_security_mode != "OFF" ? [1] : []
    content {
      advanced_security_mode = var.advanced_security_mode
    }
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  admin_create_user_config {
    allow_admin_create_user_only = var.allow_admin_create_user_only
    invite_message_template {
      email_subject = var.invite_email.subject
      email_message = var.invite_email.message
      sms_message   = "Your username is {username} and temporary password is {####}."
    }
  }

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  deletion_protection      = "ACTIVE"

  device_configuration {
    challenge_required_on_new_device      = true
    device_only_remembered_on_user_prompt = true
  }

  email_configuration {
    email_sending_account  = var.email.sending_account
    configuration_set      = var.email.email_configuration_set
    from_email_address     = var.email.from_email_address
    reply_to_email_address = var.email.reply_to_email_address
    source_arn             = var.email.ses_arn
  }

  email_verification_message = var.email_verification.message
  email_verification_subject = var.email_verification.subject

  mfa_configuration = var.mfa_configuration

  password_policy {
    minimum_length                   = var.password_policy.minimum_length
    password_history_size            = var.password_policy.password_history_size
    require_lowercase                = var.password_policy.require_lowercase
    require_numbers                  = var.password_policy.require_numbers
    require_symbols                  = var.password_policy.require_symbols
    require_uppercase                = var.password_policy.require_uppercase
    temporary_password_validity_days = var.password_policy.temporary_password_validity_days
  }

  dynamic "sign_in_policy" {
    for_each = length(var.allowed_first_auth_factors) > 0 ? [1] : []
    content {
      allowed_first_auth_factors = var.allowed_first_auth_factors
    }
  }

  software_token_mfa_configuration {
    enabled = true
  }

  username_configuration {
    case_sensitive = false
  }

  dynamic "web_authn_configuration" {
    for_each = var.web_authn_relying_party_id != null && var.web_authn_relying_party_id != "" ? [1] : []
    content {
      relying_party_id  = var.web_authn_relying_party_id
      user_verification = var.web_authn_user_verification
    }
  }

  user_attribute_update_settings {
    attributes_require_verification_before_update = ["email"]
  }

  verification_message_template {
    default_email_option  = "CONFIRM_WITH_LINK"
    email_message_by_link = "Please click the link below to verify your email address. {##Click Here##}"
    email_subject_by_link = "Verify your email address"
  }

  # Default Schema Attribute (email)
  schema {
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                  = true
    name                     = "email"
    required                 = true
    string_attribute_constraints {
      min_length = "5"
      max_length = "2048"
    }
  }

  # Custom Schema Attributes via dynamic block
  dynamic "schema" {
    for_each = var.custom_schema_attributes
    content {
      name                     = schema.value.name
      attribute_data_type      = schema.value.attribute_data_type
      developer_only_attribute = schema.value.developer_only_attribute
      mutable                  = schema.value.mutable
      required                 = schema.value.required

      dynamic "string_attribute_constraints" {
        for_each = schema.value.min_length != null || schema.value.max_length != null ? [1] : []
        content {
          min_length = schema.value.min_length
          max_length = schema.value.max_length
        }
      }
    }
  }

  # Optional Lambda Triggers
  dynamic "lambda_config" {
    for_each = anytrue([
      var.lambda_triggers.create_auth_challenge != null,
      var.lambda_triggers.custom_message != null,
      var.lambda_triggers.define_auth_challenge != null,
      var.lambda_triggers.post_authentication != null,
      var.lambda_triggers.post_confirmation != null,
      var.lambda_triggers.pre_authentication != null,
      var.lambda_triggers.pre_sign_up != null,
      var.lambda_triggers.pre_token_generation != null,
      var.lambda_triggers.user_migration != null,
      var.lambda_triggers.verify_auth_challenge_response != null,
      var.lambda_triggers.custom_email_sender_arn != null,
      var.lambda_triggers.pre_token_generation_config != null
    ]) ? [1] : []
    content {
      create_auth_challenge          = var.lambda_triggers.create_auth_challenge
      custom_message                 = var.lambda_triggers.custom_message
      define_auth_challenge          = var.lambda_triggers.define_auth_challenge
      post_authentication            = var.lambda_triggers.post_authentication
      post_confirmation              = var.lambda_triggers.post_confirmation
      pre_authentication             = var.lambda_triggers.pre_authentication
      pre_sign_up                    = var.lambda_triggers.pre_sign_up
      pre_token_generation           = var.lambda_triggers.pre_token_generation
      user_migration                 = var.lambda_triggers.user_migration
      verify_auth_challenge_response = var.lambda_triggers.verify_auth_challenge_response
      kms_key_id                     = var.lambda_triggers.kms_key_id

      dynamic "custom_email_sender" {
        for_each = var.lambda_triggers.custom_email_sender_arn != null ? [1] : []
        content {
          lambda_arn     = var.lambda_triggers.custom_email_sender_arn
          lambda_version = var.lambda_triggers.custom_email_sender_version
        }
      }

      dynamic "pre_token_generation_config" {
        for_each = var.lambda_triggers.pre_token_generation_config != null ? [1] : []
        content {
          lambda_arn     = var.lambda_triggers.pre_token_generation_config.lambda_arn
          lambda_version = var.lambda_triggers.pre_token_generation_config.lambda_version
        }
      }
    }
  }

  tags = local.tags
}

# -----------------------------------------------------------------------------
# CLIENTS
# -----------------------------------------------------------------------------

resource "aws_cognito_user_pool_client" "this" {
  for_each = var.clients

  name         = each.value.name
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret               = each.value.generate_secret
  prevent_user_existence_errors = each.value.prevent_user_existence_errors
  explicit_auth_flows           = each.value.explicit_auth_flows
  read_attributes               = each.value.read_attributes != null ? each.value.read_attributes : local.final_read_attributes
  write_attributes              = each.value.write_attributes != null ? each.value.write_attributes : local.final_write_attributes

  access_token_validity  = each.value.access_token_validity
  id_token_validity      = each.value.id_token_validity
  refresh_token_validity = each.value.refresh_token_validity

  token_validity_units {
    access_token  = each.value.token_validity_units.access_token
    id_token      = each.value.token_validity_units.id_token
    refresh_token = each.value.token_validity_units.refresh_token
  }

  callback_urls                        = length(each.value.callback_urls) > 0 ? each.value.callback_urls : null
  logout_urls                          = length(each.value.logout_urls) > 0 ? each.value.logout_urls : null
  allowed_oauth_flows_user_pool_client = each.value.allowed_oauth_flows_user_pool_client
  allowed_oauth_flows                  = length(each.value.allowed_oauth_flows) > 0 ? each.value.allowed_oauth_flows : null
  allowed_oauth_scopes                 = length(each.value.allowed_oauth_scopes) > 0 ? each.value.allowed_oauth_scopes : null
  supported_identity_providers         = each.value.supported_identity_providers
}

# -----------------------------------------------------------------------------
# GROUPS
# -----------------------------------------------------------------------------

resource "aws_cognito_user_group" "this" {
  for_each = { for g in var.groups : g.name => g }

  name         = each.value.name
  description  = each.value.description
  user_pool_id = aws_cognito_user_pool.this.id
}

# -----------------------------------------------------------------------------
# ADVANCED SECURITY FEATURES (ASF) RISK CONFIGURATION
# -----------------------------------------------------------------------------



resource "aws_cognito_risk_configuration" "this" {
  count = var.enable_risk_configuration ? 1 : 0

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

# -----------------------------------------------------------------------------
# USER POOL DOMAIN
# -----------------------------------------------------------------------------

resource "aws_cognito_user_pool_domain" "this" {
  count           = var.domain != null ? 1 : 0
  domain          = var.domain
  user_pool_id    = aws_cognito_user_pool.this.id
  certificate_arn = var.certificate_arn
}

# -----------------------------------------------------------------------------
# SES IDENTITY POLICY FOR COGNITO EMAIL SENDING
# -----------------------------------------------------------------------------

resource "aws_ses_identity_policy" "cognito_ses" {
  count    = var.email.ses_arn != null ? 1 : 0
  identity = var.email.ses_arn
  name     = "${var.application}-${var.environment}-${var.name}-cognito-ses"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCognitoToSendMessage"
        Effect = "Allow"
        Principal = {
          Service = "cognito-idp.amazonaws.com"
        }
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = var.email.ses_arn
      }
    ]
  })
}
