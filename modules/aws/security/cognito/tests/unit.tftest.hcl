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

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_resource "aws_cognito_user_pool" {
    defaults = {
      id       = "eu-west-1_AbCdEfGhI"
      arn      = "arn:aws:cognito-idp:eu-west-1:123456789012:userpool/eu-west-1_AbCdEfGhI"
      endpoint = "cognito-idp.eu-west-1.amazonaws.com/eu-west-1_AbCdEfGhI"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-west-1:123456789012:log-group:/aws/vendedlogs/cognito/core-prod"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    }
  }

  mock_resource "aws_cognito_user_pool_domain" {
    defaults = {
      cloudfront_distribution         = "d111111abcdef8.cloudfront.net"
      cloudfront_distribution_zone_id = "Z2FDTNDATAQYW2"
    }
  }
}

variables {
  application = "core"
  environment = "prod"
  tags        = { Team = "identity" }
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = aws_cognito_user_pool.this.name == "core-prod" && aws_cognito_user_pool.this.user_pool_tier == "ESSENTIALS" && aws_cognito_user_pool.this.deletion_protection == "ACTIVE"
    error_message = "The pool is <application>-<environment>, ESSENTIALS, with deletion protection (Cognito.6)."
  }

  assert {
    condition     = aws_cognito_user_pool.this.mfa_configuration == "ON" && aws_cognito_user_pool.this.software_token_mfa_configuration[0].enabled && aws_cognito_user_pool.this.sign_in_policy[0].allowed_first_auth_factors == toset(["PASSWORD"])
    error_message = "MFA is required with TOTP and passwords are the only first factor (Cognito.5)."
  }

  assert {
    condition     = aws_cognito_user_pool.this.password_policy[0].minimum_length == 14 && aws_cognito_user_pool.this.password_policy[0].password_history_size == 5 && aws_cognito_user_pool.this.password_policy[0].require_symbols && aws_cognito_user_pool.this.password_policy[0].temporary_password_validity_days == 7
    error_message = "Passwords: 14 characters, all classes, history 5, 7-day temporary passwords (Cognito.3)."
  }

  assert {
    condition     = aws_cognito_user_pool.this.admin_create_user_config[0].allow_admin_create_user_only && aws_cognito_user_pool.this.admin_create_user_config[0].invite_message_template[0].sms_message == null
    error_message = "Only admins create users; no hard-coded SMS invite."
  }

  assert {
    condition     = aws_cognito_user_pool.this.verification_message_template[0].default_email_option == "CONFIRM_WITH_LINK" && aws_cognito_user_pool.this.verification_message_template[0].email_message == "Your verification code is {####}."
    error_message = "The verification template carries every email verification field."
  }

  assert {
    condition     = length(aws_cognito_user_pool.this.user_pool_add_ons) == 0 && length(aws_cognito_risk_configuration.this) == 0 && length(aws_cognito_user_pool.this.web_authn_configuration) == 0 && length(aws_cognito_user_pool.this.lambda_config) == 0
    error_message = "No threat protection, passkeys or triggers by default."
  }

  assert {
    condition     = module.log_group[0].name == "/aws/vendedlogs/cognito/core-prod" && module.log_group[0].retention_in_days == 365 && module.log_group[0].kms_key_arn == null && output.kms_key_arn == null
    error_message = "Logs go to /aws/vendedlogs/cognito/<pool> for 365 days with service encryption."
  }

  assert {
    condition     = [for c in aws_cognito_log_delivery_configuration.this[0].log_configurations : "${c.event_source}:${c.log_level}"] == ["userNotification:ERROR"]
    error_message = "Notification errors are exported on every tier."
  }

  assert {
    condition     = length(aws_cognito_user_pool_domain.this) + length(aws_cognito_managed_login_branding.this) + length(aws_sesv2_email_identity_policy.this) + length(aws_cognito_user_pool_client.this) + length(aws_cognito_user_group.this) == 0 && output.domain == null
    error_message = "No domain, branding, SES policy, clients or groups by default."
  }

  assert {
    condition     = aws_cognito_user_pool.this.tags["Name"] == "core-prod" && aws_cognito_user_pool.this.tags["Team"] == "identity" && aws_cognito_user_pool.this.tags["ManagedBy"] == "Terraform"
    error_message = "Caller and governance tags must be applied."
  }
}

run "lite_tier" {
  command = plan

  variables {
    name           = "partners"
    user_pool_tier = "LITE"
    clients        = { web = {} }
    domain         = { enabled = true }
  }

  assert {
    condition     = aws_cognito_user_pool.this.name == "core-prod-partners" && length(aws_cognito_user_pool.this.sign_in_policy) == 0 && aws_cognito_user_pool.this.password_policy[0].password_history_size == null
    error_message = "LITE pools set no sign-in policy or password history."
  }

  assert {
    condition     = aws_cognito_user_pool_domain.this[0].managed_login_version == 1 && length(aws_cognito_managed_login_branding.this) == 0
    error_message = "LITE domains serve the classic hosted UI without branding styles."
  }

  assert {
    condition     = length(aws_cognito_user_pool_client.this["web"].refresh_token_rotation) == 0
    error_message = "LITE clients set no refresh token rotation."
  }

  assert {
    condition     = [for c in aws_cognito_log_delivery_configuration.this[0].log_configurations : c.event_source] == ["userNotification"]
    error_message = "LITE pools still export notification errors."
  }
}

run "plus_without_threat_protection" {
  command = plan

  variables {
    user_pool_tier = "PLUS"
  }

  assert {
    condition     = [for c in aws_cognito_log_delivery_configuration.this[0].log_configurations : c.event_source] == ["userNotification"] && length(aws_cognito_risk_configuration.this) == 0
    error_message = "User activity logs and risk actions need threat protection."
  }
}

run "plus_with_threat_protection" {
  command = plan

  variables {
    user_pool_tier    = "PLUS"
    threat_protection = { enabled = true, custom_auth_mode = "AUDIT" }
  }

  assert {
    condition     = aws_cognito_user_pool.this.user_pool_add_ons[0].advanced_security_mode == "ENFORCED" && aws_cognito_user_pool.this.user_pool_add_ons[0].advanced_security_additional_flows[0].custom_auth_mode == "AUDIT"
    error_message = "Threat protection runs in full-function mode (Cognito.1)."
  }

  assert {
    condition     = [for c in aws_cognito_log_delivery_configuration.this[0].log_configurations : "${c.event_source}:${c.log_level}"] == ["userNotification:ERROR", "userAuthEvents:INFO"]
    error_message = "PLUS with threat protection also exports user activity at INFO."
  }

  assert {
    condition     = aws_cognito_risk_configuration.this[0].compromised_credentials_risk_configuration[0].actions[0].event_action == "BLOCK" && aws_cognito_risk_configuration.this[0].account_takeover_risk_configuration[0].actions[0].high_action[0].event_action == "BLOCK"
    error_message = "Compromised credentials and high-risk sign-ins are blocked."
  }
}

run "module_key_is_planned_safely" {
  command = plan

  variables {
    kms             = { create = true }
    lambda_triggers = { custom_email_sender = { arn = "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-mailer:live" } }
    clients         = { web = {} }
    domain          = { enabled = true }
  }

  assert {
    condition     = module.encryption.created && length(aws_cognito_user_pool.this.lambda_config) == 1
    error_message = "kms.create must plan without knowing the key ARN."
  }

  assert {
    condition     = length(aws_cognito_managed_login_branding.this) == 1
    error_message = "Branding styles plan before the client IDs are known."
  }
}

run "module_key_encrypts_logs_and_sender_codes" {
  command = apply

  variables {
    kms = { create = true }
    lambda_triggers = {
      custom_email_sender = { arn = "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-mailer:live" }
      custom_sms_sender   = { arn = "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-sms:live" }
    }
  }

  assert {
    condition     = aws_cognito_user_pool.this.lambda_config[0].kms_key_id == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && aws_cognito_user_pool.this.lambda_config[0].custom_email_sender[0].lambda_version == "V1_0" && aws_cognito_user_pool.this.lambda_config[0].custom_sms_sender[0].lambda_arn == "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-sms:live"
    error_message = "Custom senders use the module key."
  }

  assert {
    condition     = module.log_group[0].kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && output.kms_key_arn == module.log_group[0].kms_key_arn
    error_message = "The module key encrypts the log group."
  }
}

run "caller_key_id_and_log_override" {
  command = plan

  variables {
    kms             = { key_id = "11111111-2222-3333-4444-555555555555" }
    cloudwatch_logs = { kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/99999999-2222-3333-4444-555555555555", retention_in_days = 731 }
  }

  assert {
    condition     = output.kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && module.log_group[0].kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/99999999-2222-3333-4444-555555555555" && module.log_group[0].retention_in_days == 731
    error_message = "A key ID becomes the key ARN; cloudwatch_logs overrides key and retention."
  }
}

run "logs_disabled" {
  command = plan

  variables {
    cloudwatch_logs = { enabled = false }
  }

  assert {
    condition     = length(module.log_group) == 0 && length(aws_cognito_log_delivery_configuration.this) == 0 && output.log_group_name == null
    error_message = "cloudwatch_logs.enabled = false creates no log group or delivery."
  }
}

run "triggers" {
  command = plan

  variables {
    lambda_triggers = {
      pre_sign_up          = { arn = "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-signup:live" }
      pre_token_generation = { arn = "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-claims:live", version = "V2_0" }
    }
  }

  assert {
    condition     = aws_cognito_user_pool.this.lambda_config[0].pre_sign_up == "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-signup:live" && aws_cognito_user_pool.this.lambda_config[0].pre_token_generation_config[0].lambda_version == "V2_0" && aws_cognito_user_pool.this.lambda_config[0].kms_key_id == null
    error_message = "Triggers are wired; no key without custom senders."
  }
}

run "clients_groups_and_prefix_domain" {
  command = apply

  variables {
    custom_attributes = { tenant = { max_length = 64 } }
    clients = {
      web = { callback_urls = ["https://app.example.com/callback"], allowed_oauth_flows = ["code"], allowed_oauth_scopes = ["openid", "email"] }
      api = { generate_secret = true, explicit_auth_flows = ["ALLOW_REFRESH_TOKEN_AUTH"], allowed_oauth_flows = ["client_credentials"], allowed_oauth_scopes = ["orders/read"] }
    }
    groups = { admins = { description = "Administrators", precedence = 1 } }
    domain = { enabled = true }
  }

  assert {
    condition     = aws_cognito_user_pool_client.this["web"].name == "web" && aws_cognito_user_pool_client.this["web"].explicit_auth_flows == toset(["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]) && aws_cognito_user_pool_client.this["web"].allowed_oauth_flows_user_pool_client
    error_message = "Clients default to SRP and refresh tokens."
  }

  assert {
    condition     = aws_cognito_user_pool_client.this["web"].prevent_user_existence_errors == "ENABLED" && aws_cognito_user_pool_client.this["web"].enable_token_revocation && contains(aws_cognito_user_pool_client.this["web"].read_attributes, "custom:tenant")
    error_message = "Clients hide user existence, revoke tokens and read custom attributes."
  }

  assert {
    condition     = keys(output.client_ids) == ["api", "web"] && aws_cognito_user_group.this["admins"].precedence == 1
    error_message = "Client IDs are exported by name; groups are created."
  }

  assert {
    condition     = output.domain == "core-prod-123456789012-eu-west-1" && aws_cognito_user_pool_domain.this[0].managed_login_version == 2 && output.endpoint == "cognito-idp.eu-west-1.amazonaws.com/eu-west-1_AbCdEfGhI"
    error_message = "The prefix domain is <application>-<environment>-<account>-<region>."
  }

  assert {
    condition     = aws_cognito_user_pool_domain.this[0].managed_login_version == 2 && keys(aws_cognito_managed_login_branding.this) == ["api", "web"] && aws_cognito_managed_login_branding.this["web"].use_cognito_provided_values && aws_cognito_managed_login_branding.this["web"].client_id == aws_cognito_user_pool_client.this["web"].id
    error_message = "ESSENTIALS domains default to managed login with a Cognito style per client."
  }

  assert {
    condition     = length(aws_cognito_user_pool_client.this["web"].refresh_token_rotation) == 0
    error_message = "Refresh token rotation is off by default."
  }

  assert {
    condition     = output.id == "eu-west-1_AbCdEfGhI" && output.arn == "arn:aws:cognito-idp:eu-west-1:123456789012:userpool/eu-west-1_AbCdEfGhI"
    error_message = "Outputs expose the pool."
  }
}

run "refresh_token_rotation" {
  command = plan

  variables {
    user_pool_tier = "PLUS"
    clients = {
      spa = { explicit_auth_flows = ["ALLOW_USER_SRP_AUTH"], refresh_token_rotation = { enabled = true, retry_grace_period_seconds = 10 } }
    }
  }

  assert {
    condition     = aws_cognito_user_pool_client.this["spa"].refresh_token_rotation[0].feature == "ENABLED" && aws_cognito_user_pool_client.this["spa"].refresh_token_rotation[0].retry_grace_period_seconds == 10
    error_message = "Rotation is set per client with its grace period."
  }

  assert {
    condition     = length(aws_cognito_managed_login_branding.this) == 0
    error_message = "No branding styles without a domain."
  }
}

run "custom_domain" {
  command = apply

  variables {
    clients = { web = {} }
    domain  = { enabled = true, custom_domain = "auth.example.com", certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/11111111-2222-3333-4444-555555555555", managed_login_version = 1 }
  }

  assert {
    condition     = output.domain == "auth.example.com" && output.domain_dns_name == "d111111abcdef8.cloudfront.net" && output.domain_zone_id == "Z2FDTNDATAQYW2"
    error_message = "A custom domain exports its alias target."
  }

  assert {
    condition     = aws_cognito_user_pool_domain.this[0].managed_login_version == 1 && length(aws_cognito_managed_login_branding.this) == 0
    error_message = "An explicit version 1 keeps the classic hosted UI without branding styles."
  }
}

run "ses_sending" {
  command = apply

  variables {
    email = { sending_account = "DEVELOPER", ses_identity_arn = "arn:aws:ses:eu-west-1:123456789012:identity/mail.example.com", from_email_address = "no-reply@mail.example.com" }
  }

  assert {
    condition     = aws_sesv2_email_identity_policy.this[0].email_identity == "mail.example.com" && aws_sesv2_email_identity_policy.this[0].region == "eu-west-1" && aws_sesv2_email_identity_policy.this[0].policy_name == "core-prod-cognito"
    error_message = "The SES v2 policy targets the identity name from the ARN, in its Region."
  }

  assert {
    condition     = jsondecode(aws_sesv2_email_identity_policy.this[0].policy).Statement[0].Resource == "arn:aws:ses:eu-west-1:123456789012:identity/mail.example.com" && jsondecode(aws_sesv2_email_identity_policy.this[0].policy).Statement[0].Action == ["ses:SendEmail", "ses:SendRawEmail"] && jsondecode(aws_sesv2_email_identity_policy.this[0].policy).Statement[0].Condition.ArnLike["aws:SourceArn"] == "arn:aws:cognito-idp:eu-west-1:123456789012:userpool/eu-west-1_AbCdEfGhI" && jsondecode(aws_sesv2_email_identity_policy.this[0].policy).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "123456789012"
    error_message = "Only this pool may send through the SES identity."
  }

  assert {
    condition     = aws_cognito_user_pool.this.email_configuration[0].email_sending_account == "DEVELOPER" && aws_cognito_user_pool.this.email_configuration[0].source_arn == "arn:aws:ses:eu-west-1:123456789012:identity/mail.example.com"
    error_message = "The pool sends through SES."
  }
}

run "passkeys_and_self_sign_up" {
  command = plan

  variables {
    mfa_configuration          = "OPTIONAL"
    allowed_first_auth_factors = ["PASSWORD", "WEB_AUTHN", "EMAIL_OTP"]
    web_authn                  = { relying_party_id = "auth.example.com" }
    self_sign_up               = { enabled = true }
  }

  assert {
    condition     = aws_cognito_user_pool.this.web_authn_configuration[0].relying_party_id == "auth.example.com" && aws_cognito_user_pool.this.web_authn_configuration[0].user_verification == "required" && !aws_cognito_user_pool.this.admin_create_user_config[0].allow_admin_create_user_only
    error_message = "Passkeys are bound to the relying party; self sign-up is opt-in."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Users_Pool"
  }

  expect_failures = [var.name]
}

run "rejects_invalid_application" {
  command = plan

  variables {
    application = "Core"
  }

  expect_failures = [var.application]
}

run "rejects_invalid_environment" {
  command = plan

  variables {
    environment = "PROD"
  }

  expect_failures = [var.environment]
}

run "rejects_create_and_key_id" {
  command = plan

  variables {
    kms = { create = true, key_id = "11111111-2222-3333-4444-555555555555" }
  }

  expect_failures = [var.kms]
}

run "rejects_invalid_key_id" {
  command = plan

  variables {
    kms = { key_id = "alias/cognito" }
  }

  expect_failures = [var.kms]
}

run "rejects_invalid_tier" {
  command = plan

  variables {
    user_pool_tier = "PRO"
  }

  expect_failures = [var.user_pool_tier]
}

run "rejects_threat_protection_without_plus" {
  command = plan

  variables {
    threat_protection = { enabled = true }
  }

  expect_failures = [var.threat_protection]
}

run "rejects_invalid_threat_mode" {
  command = plan

  variables {
    user_pool_tier    = "PLUS"
    threat_protection = { enabled = true, mode = "OFF" }
  }

  expect_failures = [var.threat_protection]
}

run "rejects_short_passwords" {
  command = plan

  variables {
    password_policy = { minimum_length = 12 }
  }

  expect_failures = [var.password_policy]
}

run "rejects_invalid_password_history" {
  command = plan

  variables {
    password_policy = { password_history_size = 30 }
  }

  expect_failures = [var.password_policy]
}

run "rejects_invalid_mfa" {
  command = plan

  variables {
    mfa_configuration = "REQUIRED"
  }

  expect_failures = [var.mfa_configuration]
}

run "rejects_required_mfa_with_otp_factor" {
  command = plan

  variables {
    allowed_first_auth_factors = ["PASSWORD", "EMAIL_OTP"]
  }

  expect_failures = [var.mfa_configuration]
}

run "rejects_factors_without_password" {
  command = plan

  variables {
    mfa_configuration          = "OPTIONAL"
    allowed_first_auth_factors = ["EMAIL_OTP"]
  }

  expect_failures = [var.allowed_first_auth_factors]
}

run "rejects_passwordless_on_lite" {
  command = plan

  variables {
    user_pool_tier             = "LITE"
    allowed_first_auth_factors = ["PASSWORD", "WEB_AUTHN"]
    web_authn                  = { relying_party_id = "auth.example.com" }
  }

  expect_failures = [var.allowed_first_auth_factors]
}

run "rejects_passkeys_without_relying_party" {
  command = plan

  variables {
    allowed_first_auth_factors = ["PASSWORD", "WEB_AUTHN"]
  }

  expect_failures = [var.web_authn]
}

run "rejects_invalid_user_verification" {
  command = plan

  variables {
    web_authn = { user_verification = "discouraged" }
  }

  expect_failures = [var.web_authn]
}

run "rejects_invite_without_placeholders" {
  command = plan

  variables {
    invite_message = { email_message = "Welcome!" }
  }

  expect_failures = [var.invite_message]
}

run "rejects_invalid_verification_option" {
  command = plan

  variables {
    verification_message = { default_email_option = "CONFIRM_WITH_SMS" }
  }

  expect_failures = [var.verification_message]
}

run "rejects_verification_without_code" {
  command = plan

  variables {
    verification_message = { email_message = "Verify your email." }
  }

  expect_failures = [var.verification_message]
}

run "rejects_invalid_sending_account" {
  command = plan

  variables {
    email = { sending_account = "SES" }
  }

  expect_failures = [var.email]
}

run "rejects_developer_email_without_identity" {
  command = plan

  variables {
    email = { sending_account = "DEVELOPER" }
  }

  expect_failures = [var.email]
}

run "rejects_invalid_ses_identity_arn" {
  command = plan

  variables {
    email = { sending_account = "DEVELOPER", ses_identity_arn = "example.com" }
  }

  expect_failures = [var.email]
}

run "rejects_unknown_trigger" {
  command = plan

  variables {
    lambda_triggers = { post_login = { arn = "arn:aws:lambda:eu-west-1:123456789012:function:x" } }
  }

  expect_failures = [var.lambda_triggers]
}

run "rejects_invalid_trigger_version" {
  command = plan

  variables {
    lambda_triggers = { pre_token_generation = { arn = "arn:aws:lambda:eu-west-1:123456789012:function:x", version = "V4_0" } }
  }

  expect_failures = [var.lambda_triggers]
}

run "rejects_custom_sender_without_key" {
  command = plan

  variables {
    lambda_triggers = { custom_email_sender = { arn = "arn:aws:lambda:eu-west-1:123456789012:function:x" } }
  }

  expect_failures = [var.lambda_triggers]
}

run "rejects_invalid_custom_attribute" {
  command = plan

  variables {
    custom_attributes = { "tenant-id" = {} }
  }

  expect_failures = [var.custom_attributes]
}

run "rejects_invalid_auth_flow" {
  command = plan

  variables {
    clients = { web = { explicit_auth_flows = ["USER_PASSWORD_AUTH"] } }
  }

  expect_failures = [var.clients]
}

run "rejects_implicit_grant" {
  command = plan

  variables {
    clients = { web = { allowed_oauth_flows = ["implicit"] } }
  }

  expect_failures = [var.clients]
}

run "rejects_invalid_token_validity" {
  command = plan

  variables {
    clients = { web = { access_token_validity_minutes = 2 } }
  }

  expect_failures = [var.clients]
}

run "rejects_invalid_grace_period" {
  command = plan

  variables {
    clients = { spa = { explicit_auth_flows = ["ALLOW_USER_SRP_AUTH"], refresh_token_rotation = { enabled = true, retry_grace_period_seconds = 90 } } }
  }

  expect_failures = [var.clients]
}

run "rejects_rotation_on_lite" {
  command = plan

  variables {
    user_pool_tier = "LITE"
    clients        = { spa = { explicit_auth_flows = ["ALLOW_USER_SRP_AUTH"], refresh_token_rotation = { enabled = true } } }
  }

  expect_failures = [var.clients]
}

run "rejects_rotation_with_refresh_token_auth" {
  command = plan

  variables {
    clients = { spa = { refresh_token_rotation = { enabled = true } } }
  }

  expect_failures = [var.clients]
}

run "rejects_custom_domain_without_certificate" {
  command = plan

  variables {
    domain = { enabled = true, custom_domain = "auth.example.com" }
  }

  expect_failures = [var.domain]
}

run "rejects_invalid_managed_login_version" {
  command = plan

  variables {
    domain = { enabled = true, managed_login_version = 3 }
  }

  expect_failures = [var.domain]
}

run "rejects_managed_login_on_lite" {
  command = plan

  variables {
    user_pool_tier = "LITE"
    domain         = { enabled = true, managed_login_version = 2 }
  }

  expect_failures = [var.domain]
}
