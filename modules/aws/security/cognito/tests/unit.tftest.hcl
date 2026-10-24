mock_provider "aws" {
  mock_resource "aws_cognito_user_pool" {
    defaults = {
      id  = "us-west-2_AbCdEfGhI"
      arn = "arn:aws:cognito-idp:us-west-2:123456789012:userpool/us-west-2_AbCdEfGhI"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-west-2:123456789012:log-group:/aws/cognito/core-prod-users"
    }
  }
}

variables {
  application = "core"
  environment = "prod"
  name        = "users"
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
}

# ------------------------------------------------------------------------------
# Naming
# ------------------------------------------------------------------------------

run "naming_renders_application_environment_name" {
  command = plan

  assert {
    condition     = aws_cognito_user_pool.this.name == "core-prod-users"
    error_message = "User pool name must be <application>-<environment>-<name>."
  }

  assert {
    condition     = aws_cognito_user_pool.this.tags["Name"] == "core-prod-users"
    error_message = "User pool Name tag must be the rendered name."
  }
}

run "naming_falls_back_when_name_is_empty" {
  command = plan

  variables {
    name = ""
  }

  assert {
    condition     = aws_cognito_user_pool.this.name == "core-prod"
    error_message = "With an empty name the user pool name must fall back to <application>-<environment>."
  }

  assert {
    condition     = aws_cognito_user_pool.this.tags["Name"] == "core-prod"
    error_message = "With an empty name the Name tag must fall back to <application>-<environment>."
  }
}

run "naming_falls_back_when_name_is_null" {
  command = plan

  variables {
    name = null
  }

  assert {
    condition     = aws_cognito_user_pool.this.name == "core-prod"
    error_message = "With a null name the user pool name must fall back to <application>-<environment>."
  }
}

# ------------------------------------------------------------------------------
# Tags
# ------------------------------------------------------------------------------

run "tags_include_governance_and_caller_tags" {
  command = plan

  variables {
    user_pool_tier = "PLUS"
    tags = {
      CostCenter = "1234"
      Team       = "identity"
    }
  }

  assert {
    condition     = aws_cognito_user_pool.this.tags["Application"] == "core" && aws_cognito_user_pool.this.tags["Environment"] == "prod" && aws_cognito_user_pool.this.tags["Name"] == "core-prod-users"
    error_message = "User pool must carry the Application, Environment and Name governance tags."
  }

  assert {
    condition     = aws_cognito_user_pool.this.tags["CostCenter"] == "1234" && aws_cognito_user_pool.this.tags["Team"] == "identity"
    error_message = "Caller tags from var.tags must be preserved on the user pool."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].tags["Application"] == "core" && aws_cloudwatch_log_group.this[0].tags["Environment"] == "prod"
    error_message = "Log group must carry the Application and Environment governance tags."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].tags["Name"] == "/aws/cognito/core-prod-users"
    error_message = "Log group Name tag must be its log group name."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].tags["CostCenter"] == "1234"
    error_message = "Caller tags must be preserved on the log group."
  }
}

# ------------------------------------------------------------------------------
# Security defaults and shipped parameter defaults
# ------------------------------------------------------------------------------

run "user_pool_security_defaults_enforced" {
  command = plan

  assert {
    condition     = aws_cognito_user_pool.this.deletion_protection == "ACTIVE"
    error_message = "Deletion protection must be ACTIVE."
  }

  assert {
    condition     = aws_cognito_user_pool.this.mfa_configuration == "OPTIONAL"
    error_message = "MFA must default to OPTIONAL."
  }

  assert {
    condition     = aws_cognito_user_pool.this.software_token_mfa_configuration[0].enabled == true
    error_message = "Software token (TOTP) MFA must be enabled."
  }

  assert {
    condition = (
      aws_cognito_user_pool.this.password_policy[0].require_lowercase == true &&
      aws_cognito_user_pool.this.password_policy[0].require_uppercase == true &&
      aws_cognito_user_pool.this.password_policy[0].require_numbers == true &&
      aws_cognito_user_pool.this.password_policy[0].require_symbols == true
    )
    error_message = "Password policy must require lowercase, uppercase, numbers and symbols by default."
  }

  assert {
    condition     = aws_cognito_user_pool.this.password_policy[0].password_history_size == 5
    error_message = "Password history size must default to 5."
  }

  assert {
    condition     = aws_cognito_user_pool.this.password_policy[0].temporary_password_validity_days == 7
    error_message = "Temporary passwords must default to 7 days validity."
  }

  assert {
    condition     = aws_cognito_user_pool.this.admin_create_user_config[0].allow_admin_create_user_only == true
    error_message = "Self sign-up must be disabled by default (admin-create-user only)."
  }

  assert {
    condition     = aws_cognito_user_pool.this.username_configuration[0].case_sensitive == false
    error_message = "Usernames must be case-insensitive."
  }

  assert {
    condition     = aws_cognito_user_pool.this.device_configuration[0].challenge_required_on_new_device == true && aws_cognito_user_pool.this.device_configuration[0].device_only_remembered_on_user_prompt == true
    error_message = "New devices must be challenged and only remembered on user prompt."
  }

  assert {
    condition     = one(aws_cognito_user_pool.this.account_recovery_setting[0].recovery_mechanism).name == "verified_email"
    error_message = "Account recovery must use the verified email only."
  }

  assert {
    condition     = aws_cognito_user_pool.this.username_attributes == toset(["email"]) && aws_cognito_user_pool.this.auto_verified_attributes == toset(["email"])
    error_message = "Email must be the username attribute and be auto-verified."
  }

  assert {
    condition     = aws_cognito_user_pool.this.user_attribute_update_settings[0].attributes_require_verification_before_update == toset(["email"])
    error_message = "Email changes must require verification before the update applies."
  }

  assert {
    condition     = anytrue([for s in aws_cognito_user_pool.this.schema : s.name == "email" && s.required == true && s.mutable == true])
    error_message = "The email schema attribute must be required and mutable."
  }

  assert {
    condition     = aws_cognito_user_pool.this.verification_message_template[0].default_email_option == "CONFIRM_WITH_LINK"
    error_message = "Email verification must default to CONFIRM_WITH_LINK."
  }

  assert {
    condition     = aws_cognito_user_pool.this.sign_in_policy[0].allowed_first_auth_factors == toset(["PASSWORD", "EMAIL_OTP", "WEB_AUTHN"])
    error_message = "Sign-in policy must default to PASSWORD, EMAIL_OTP and WEB_AUTHN first factors."
  }

  assert {
    condition     = aws_cognito_user_pool.this.web_authn_configuration[0].relying_party_id == "localhost" && aws_cognito_user_pool.this.web_authn_configuration[0].user_verification == "required"
    error_message = "WebAuthn must default to relying party localhost with user verification required."
  }

  assert {
    condition     = aws_cognito_user_pool.this.user_pool_tier == "ESSENTIALS"
    error_message = "User pool tier must default to ESSENTIALS."
  }

  assert {
    condition     = aws_cognito_user_pool.this.email_configuration[0].email_sending_account == "COGNITO_DEFAULT"
    error_message = "Email sending account must default to COGNITO_DEFAULT."
  }

  assert {
    condition     = aws_cognito_user_pool.this.email_verification_subject == "Verify your email address" && aws_cognito_user_pool.this.email_verification_message == "Your verification code is {####}."
    error_message = "Email verification subject and message must use the shipped defaults."
  }

  assert {
    condition     = aws_cognito_user_pool.this.admin_create_user_config[0].invite_message_template[0].email_subject == "Welcome to the Application"
    error_message = "Invite email subject must use the shipped default."
  }
}

run "optional_features_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_cognito_user_pool.this.user_pool_add_ons) == 0
    error_message = "Advanced security add-ons must be off by default."
  }

  assert {
    condition     = length(aws_cognito_risk_configuration.this) == 0
    error_message = "Risk configuration must be off by default."
  }

  assert {
    condition     = length(aws_cognito_user_pool.this.lambda_config) == 0
    error_message = "No Lambda triggers must be configured by default."
  }

  assert {
    condition     = length(aws_cognito_user_pool_client.this) == 0 && length(aws_cognito_user_group.this) == 0
    error_message = "No clients or groups must be created by default."
  }

  assert {
    condition     = length(aws_cognito_user_pool_domain.this) == 0
    error_message = "No user pool domain must be created by default."
  }

  assert {
    condition     = length(aws_ses_identity_policy.cognito_ses) == 0
    error_message = "No SES identity policy must be created without email.ses_arn."
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.this) == 0 && length(aws_cognito_log_delivery_configuration.this) == 0
    error_message = "No log group or log delivery must be created on the ESSENTIALS tier."
  }
}

run "client_defaults_are_secure" {
  command = apply

  variables {
    clients = {
      web = {
        name                = "web"
        explicit_auth_flows = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
      }
    }
  }

  assert {
    condition     = aws_cognito_user_pool_client.this["web"].user_pool_id == aws_cognito_user_pool.this.id
    error_message = "Clients must belong to the module's user pool."
  }

  assert {
    condition     = aws_cognito_user_pool_client.this["web"].prevent_user_existence_errors == "ENABLED"
    error_message = "Clients must prevent user existence errors by default."
  }

  assert {
    condition     = aws_cognito_user_pool_client.this["web"].generate_secret == false
    error_message = "Clients must not generate a secret by default."
  }

  assert {
    condition     = aws_cognito_user_pool_client.this["web"].access_token_validity == 60 && aws_cognito_user_pool_client.this["web"].id_token_validity == 60 && aws_cognito_user_pool_client.this["web"].refresh_token_validity == 30
    error_message = "Token validity must default to 60 (access), 60 (id) and 30 (refresh)."
  }

  assert {
    condition = (
      aws_cognito_user_pool_client.this["web"].token_validity_units[0].access_token == "minutes" &&
      aws_cognito_user_pool_client.this["web"].token_validity_units[0].id_token == "minutes" &&
      aws_cognito_user_pool_client.this["web"].token_validity_units[0].refresh_token == "days"
    )
    error_message = "Token validity units must default to minutes, minutes and days."
  }

  assert {
    condition     = aws_cognito_user_pool_client.this["web"].explicit_auth_flows == toset(["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"])
    error_message = "explicit_auth_flows must flow through to the client."
  }

  assert {
    condition     = aws_cognito_user_pool_client.this["web"].allowed_oauth_flows_user_pool_client == false
    error_message = "OAuth flows must be off by default."
  }

  assert {
    condition     = aws_cognito_user_pool_client.this["web"].supported_identity_providers == toset(["COGNITO"])
    error_message = "Clients must default to the COGNITO identity provider."
  }

  assert {
    condition     = contains(aws_cognito_user_pool_client.this["web"].read_attributes, "email") && contains(aws_cognito_user_pool_client.this["web"].read_attributes, "email_verified")
    error_message = "Clients must be able to read email and email_verified by default."
  }

  assert {
    condition     = !contains(aws_cognito_user_pool_client.this["web"].write_attributes, "email_verified") && !contains(aws_cognito_user_pool_client.this["web"].write_attributes, "phone_number_verified")
    error_message = "Clients must not be able to write the verified flags by default."
  }

  assert {
    condition     = output.client_ids["web"] == aws_cognito_user_pool_client.this["web"].id
    error_message = "client_ids output must map client keys to client ids."
  }

  assert {
    condition     = output.user_pool_id == "us-west-2_AbCdEfGhI" && output.user_pool_arn == aws_cognito_user_pool.this.arn
    error_message = "user_pool_id and user_pool_arn outputs must expose the user pool."
  }
}

run "advanced_security_and_risk_configuration_enabled" {
  command = apply

  variables {
    user_pool_tier            = "PLUS"
    advanced_security_mode    = "ENFORCED"
    enable_risk_configuration = true
  }

  assert {
    condition     = aws_cognito_user_pool.this.user_pool_add_ons[0].advanced_security_mode == "ENFORCED"
    error_message = "advanced_security_mode must flow through to user_pool_add_ons."
  }

  assert {
    condition     = length(aws_cognito_risk_configuration.this) == 1 && aws_cognito_risk_configuration.this[0].user_pool_id == aws_cognito_user_pool.this.id
    error_message = "Risk configuration must be created for the module's user pool when enabled."
  }

  assert {
    condition     = aws_cognito_risk_configuration.this[0].compromised_credentials_risk_configuration[0].actions[0].event_action == "BLOCK"
    error_message = "Compromised credentials must be blocked."
  }

  assert {
    condition     = aws_cognito_risk_configuration.this[0].compromised_credentials_risk_configuration[0].event_filter == toset(["SIGN_IN", "PASSWORD_CHANGE", "SIGN_UP"])
    error_message = "Compromised credential checks must cover sign-in, password change and sign-up."
  }

  assert {
    condition = (
      aws_cognito_risk_configuration.this[0].account_takeover_risk_configuration[0].actions[0].high_action[0].event_action == "BLOCK" &&
      aws_cognito_risk_configuration.this[0].account_takeover_risk_configuration[0].actions[0].medium_action[0].event_action == "MFA_IF_CONFIGURED" &&
      aws_cognito_risk_configuration.this[0].account_takeover_risk_configuration[0].actions[0].low_action[0].event_action == "NO_ACTION"
    )
    error_message = "Account takeover risk must block high, require MFA on medium and allow low."
  }
}

run "plus_tier_enables_kms_encrypted_logging" {
  command = apply

  variables {
    user_pool_tier = "PLUS"
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.this) == 1 && length(aws_cognito_log_delivery_configuration.this) == 1
    error_message = "A log group and log delivery must be created on tiers above ESSENTIALS."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].name == "/aws/cognito/core-prod-users"
    error_message = "Log group must be named /aws/cognito/<application>-<environment>-<name>."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].kms_key_id == var.kms_key_arn
    error_message = "Log group must be encrypted with kms_key_arn by default."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].retention_in_days == 30 && aws_cloudwatch_log_group.this[0].log_group_class == "STANDARD"
    error_message = "Log group must default to 30-day retention in the STANDARD class."
  }

  assert {
    condition     = toset([for c in aws_cognito_log_delivery_configuration.this[0].log_configurations : c.event_source]) == toset(["userNotification", "userAuthEvents"])
    error_message = "Log delivery must cover userNotification and userAuthEvents."
  }

  assert {
    condition     = alltrue([for c in aws_cognito_log_delivery_configuration.this[0].log_configurations : c.log_level == "ERROR" && c.cloud_watch_logs_configuration[0].log_group_arn == aws_cloudwatch_log_group.this[0].arn])
    error_message = "Log delivery must send ERROR level logs to the module's log group."
  }

  assert {
    condition     = aws_cognito_log_delivery_configuration.this[0].user_pool_id == aws_cognito_user_pool.this.id
    error_message = "Log delivery must be attached to the module's user pool."
  }
}

# ------------------------------------------------------------------------------
# Parameter overrides
# ------------------------------------------------------------------------------

run "user_pool_parameter_overrides_flow_through" {
  command = plan

  variables {
    mfa_configuration = "ON"
    password_policy = {
      minimum_length                   = 14
      password_history_size            = 10
      temporary_password_validity_days = 3
    }
    allow_admin_create_user_only = false
    allowed_first_auth_factors   = ["PASSWORD"]
    web_authn_relying_party_id   = "auth.example.com"
    web_authn_user_verification  = "preferred"
    invite_email = {
      subject = "Your core account"
      message = "Sign in as {username} with {####}."
    }
    email_verification = {
      subject = "Confirm your email"
      message = "Your code is {####}."
    }
    cloudwatch_logs = {
      log_level         = "INFO"
      retention_in_days = 90
      kms_key_arn       = "arn:aws:kms:us-west-2:123456789012:key/abcdefab-1234-1234-1234-abcdefabcdef"
    }
    user_pool_tier = "PLUS"
  }

  assert {
    condition     = aws_cognito_user_pool.this.mfa_configuration == "ON"
    error_message = "mfa_configuration must flow through to the user pool."
  }

  assert {
    condition = (
      aws_cognito_user_pool.this.password_policy[0].minimum_length == 14 &&
      aws_cognito_user_pool.this.password_policy[0].password_history_size == 10 &&
      aws_cognito_user_pool.this.password_policy[0].temporary_password_validity_days == 3
    )
    error_message = "password_policy overrides must flow through to the user pool."
  }

  assert {
    condition     = aws_cognito_user_pool.this.password_policy[0].require_symbols == true
    error_message = "Unset password_policy fields must keep their secure defaults."
  }

  assert {
    condition     = aws_cognito_user_pool.this.admin_create_user_config[0].allow_admin_create_user_only == false
    error_message = "allow_admin_create_user_only must flow through to the user pool."
  }

  assert {
    condition     = aws_cognito_user_pool.this.sign_in_policy[0].allowed_first_auth_factors == toset(["PASSWORD"])
    error_message = "allowed_first_auth_factors must flow through to the sign-in policy."
  }

  assert {
    condition     = aws_cognito_user_pool.this.web_authn_configuration[0].relying_party_id == "auth.example.com" && aws_cognito_user_pool.this.web_authn_configuration[0].user_verification == "preferred"
    error_message = "WebAuthn overrides must flow through to the user pool."
  }

  assert {
    condition     = aws_cognito_user_pool.this.admin_create_user_config[0].invite_message_template[0].email_subject == "Your core account" && aws_cognito_user_pool.this.admin_create_user_config[0].invite_message_template[0].email_message == "Sign in as {username} with {####}."
    error_message = "invite_email must flow through to the invite message template."
  }

  assert {
    condition     = aws_cognito_user_pool.this.email_verification_subject == "Confirm your email" && aws_cognito_user_pool.this.email_verification_message == "Your code is {####}."
    error_message = "email_verification must flow through to the user pool."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].kms_key_id == "arn:aws:kms:us-west-2:123456789012:key/abcdefab-1234-1234-1234-abcdefabcdef"
    error_message = "cloudwatch_logs.kms_key_arn must take precedence over kms_key_arn on the log group."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].retention_in_days == 90
    error_message = "cloudwatch_logs.retention_in_days must flow through to the log group."
  }

  assert {
    condition     = alltrue([for c in aws_cognito_log_delivery_configuration.this[0].log_configurations : c.log_level == "INFO"])
    error_message = "cloudwatch_logs.log_level must flow through to log delivery."
  }
}

run "sign_in_policy_and_webauthn_omitted_when_unset" {
  command = plan

  variables {
    allowed_first_auth_factors = []
    web_authn_relying_party_id = null
  }

  assert {
    condition     = length(aws_cognito_user_pool.this.sign_in_policy) == 0
    error_message = "No sign-in policy must be set when allowed_first_auth_factors is empty."
  }

  assert {
    condition     = length(aws_cognito_user_pool.this.web_authn_configuration) == 0
    error_message = "No WebAuthn configuration must be set when web_authn_relying_party_id is null."
  }
}

run "client_overrides_flow_through" {
  command = plan

  variables {
    clients = {
      spa = {
        name                                 = "spa"
        generate_secret                      = true
        explicit_auth_flows                  = ["ALLOW_REFRESH_TOKEN_AUTH"]
        read_attributes                      = ["email", "name"]
        write_attributes                     = ["name"]
        access_token_validity                = 15
        id_token_validity                    = 15
        refresh_token_validity               = 7
        token_validity_units                 = { access_token = "minutes", id_token = "minutes", refresh_token = "days" }
        callback_urls                        = ["https://app.example.com/oauth/callback"]
        logout_urls                          = ["https://app.example.com/logout"]
        allowed_oauth_flows_user_pool_client = true
        allowed_oauth_flows                  = ["code"]
        allowed_oauth_scopes                 = ["email", "openid", "profile"]
      }
    }
  }

  assert {
    condition     = aws_cognito_user_pool_client.this["spa"].generate_secret == true
    error_message = "generate_secret must flow through to the client."
  }

  assert {
    condition     = aws_cognito_user_pool_client.this["spa"].read_attributes == toset(["email", "name"]) && aws_cognito_user_pool_client.this["spa"].write_attributes == toset(["name"])
    error_message = "Per-client read and write attributes must replace the module defaults."
  }

  assert {
    condition     = aws_cognito_user_pool_client.this["spa"].access_token_validity == 15 && aws_cognito_user_pool_client.this["spa"].id_token_validity == 15 && aws_cognito_user_pool_client.this["spa"].refresh_token_validity == 7
    error_message = "Token validity overrides must flow through to the client."
  }

  assert {
    condition     = aws_cognito_user_pool_client.this["spa"].callback_urls == toset(["https://app.example.com/oauth/callback"]) && aws_cognito_user_pool_client.this["spa"].logout_urls == toset(["https://app.example.com/logout"])
    error_message = "Callback and logout URLs must flow through to the client."
  }

  assert {
    condition     = aws_cognito_user_pool_client.this["spa"].allowed_oauth_flows_user_pool_client == true && aws_cognito_user_pool_client.this["spa"].allowed_oauth_flows == toset(["code"])
    error_message = "OAuth flow settings must flow through to the client."
  }

  assert {
    condition     = aws_cognito_user_pool_client.this["spa"].allowed_oauth_scopes == toset(["email", "openid", "profile"])
    error_message = "OAuth scopes must flow through to the client."
  }
}

run "custom_schema_and_module_attributes_reach_clients" {
  command = plan

  variables {
    read_attributes  = ["email", "name"]
    write_attributes = ["name"]
    custom_schema_attributes = [
      {
        name                = "tenant_id"
        attribute_data_type = "String"
        min_length          = "1"
        max_length          = "64"
      }
    ]
    clients = {
      web = {
        name                = "web"
        explicit_auth_flows = ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
      }
    }
  }

  assert {
    condition     = anytrue([for s in aws_cognito_user_pool.this.schema : s.name == "tenant_id" && s.attribute_data_type == "String" && s.mutable == true && s.required == false && s.string_attribute_constraints[0].max_length == "64"])
    error_message = "Custom schema attributes must be added to the user pool with their constraints."
  }

  assert {
    condition     = aws_cognito_user_pool_client.this["web"].read_attributes == toset(["email", "name", "custom:tenant_id"])
    error_message = "Module read_attributes plus custom attributes must be the client's read attributes."
  }

  assert {
    condition     = aws_cognito_user_pool_client.this["web"].write_attributes == toset(["name", "custom:tenant_id"])
    error_message = "Module write_attributes plus custom attributes must be the client's write attributes."
  }
}

run "optional_resources_created_when_enabled" {
  command = apply

  variables {
    domain          = "auth.example.com"
    certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    email = {
      sending_account        = "DEVELOPER"
      ses_arn                = "arn:aws:ses:us-west-2:123456789012:identity/example.com"
      from_email_address     = "no-reply@example.com"
      reply_to_email_address = "support@example.com"
    }
    groups = [
      {
        name        = "admins"
        description = "Administrators"
      }
    ]
    lambda_triggers = {
      pre_sign_up             = "arn:aws:lambda:us-west-2:123456789012:function:core-prod-pre-sign-up"
      custom_email_sender_arn = "arn:aws:lambda:us-west-2:123456789012:function:core-prod-email-sender"
      kms_key_id              = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
    }
  }

  assert {
    condition     = length(aws_cognito_user_pool_domain.this) == 1 && aws_cognito_user_pool_domain.this[0].domain == "auth.example.com"
    error_message = "A user pool domain must be created when domain is set."
  }

  assert {
    condition     = aws_cognito_user_pool_domain.this[0].certificate_arn == var.certificate_arn && aws_cognito_user_pool_domain.this[0].user_pool_id == aws_cognito_user_pool.this.id
    error_message = "The domain must use certificate_arn and belong to the module's user pool."
  }

  assert {
    condition     = length(aws_ses_identity_policy.cognito_ses) == 1 && aws_ses_identity_policy.cognito_ses[0].identity == "arn:aws:ses:us-west-2:123456789012:identity/example.com"
    error_message = "An SES identity policy must be created when email.ses_arn is set."
  }

  assert {
    condition     = aws_ses_identity_policy.cognito_ses[0].name == "core-prod-users-cognito-ses"
    error_message = "SES identity policy must be named <application>-<environment>-<name>-cognito-ses."
  }

  assert {
    condition     = jsondecode(aws_ses_identity_policy.cognito_ses[0].policy).Statement[0].Principal.Service == "cognito-idp.amazonaws.com" && jsondecode(aws_ses_identity_policy.cognito_ses[0].policy).Statement[0].Resource == "arn:aws:ses:us-west-2:123456789012:identity/example.com"
    error_message = "SES identity policy must only allow Cognito to send from the configured identity."
  }

  assert {
    condition = (
      aws_cognito_user_pool.this.email_configuration[0].email_sending_account == "DEVELOPER" &&
      aws_cognito_user_pool.this.email_configuration[0].source_arn == "arn:aws:ses:us-west-2:123456789012:identity/example.com" &&
      aws_cognito_user_pool.this.email_configuration[0].from_email_address == "no-reply@example.com" &&
      aws_cognito_user_pool.this.email_configuration[0].reply_to_email_address == "support@example.com"
    )
    error_message = "Email configuration must flow through to the user pool."
  }

  assert {
    condition     = aws_cognito_user_group.this["admins"].description == "Administrators" && aws_cognito_user_group.this["admins"].user_pool_id == aws_cognito_user_pool.this.id
    error_message = "Groups must be created in the module's user pool."
  }

  assert {
    condition     = length(aws_cognito_user_pool.this.lambda_config) == 1 && aws_cognito_user_pool.this.lambda_config[0].pre_sign_up == "arn:aws:lambda:us-west-2:123456789012:function:core-prod-pre-sign-up"
    error_message = "Lambda triggers must be configured when any trigger is set."
  }

  assert {
    condition     = aws_cognito_user_pool.this.lambda_config[0].custom_email_sender[0].lambda_arn == "arn:aws:lambda:us-west-2:123456789012:function:core-prod-email-sender" && aws_cognito_user_pool.this.lambda_config[0].custom_email_sender[0].lambda_version == "V1_0"
    error_message = "The custom email sender must be configured with the default V1_0 version."
  }

  assert {
    condition     = aws_cognito_user_pool.this.lambda_config[0].kms_key_id == "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
    error_message = "lambda_triggers.kms_key_id must flow through to lambda_config."
  }
}

# ------------------------------------------------------------------------------
# Validation
# ------------------------------------------------------------------------------

run "rejects_invalid_environment" {
  command = plan

  variables {
    environment = "Prod_Env"
  }

  expect_failures = [var.environment]
}
