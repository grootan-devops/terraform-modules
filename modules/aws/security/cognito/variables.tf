variable "name" {
  description = "Name of the Cognito User Pool"
  type        = string
}

variable "application" {
  description = "Application name"
  type        = string
}

variable "environment" {
  description = "Deployment environment name (e.g. dev, staging, prod)."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "The environment name must contain only lowercase alphanumeric characters and hyphens."
  }
}

variable "user_pool_tier" {
  description = "The User Pool Tier (e.g., ESSENTIALS, PLUS)"
  type        = string
  default     = "ESSENTIALS"
}

# -----------------------------------------------------------------------------
# ADVANCED SECURITY FEATURES (ASF)
# -----------------------------------------------------------------------------

variable "advanced_security_mode" {
  description = "Set to OFF, AUDIT, or ENFORCED to enable Advanced Security Features"
  type        = string
  default     = "OFF"
}

variable "enable_risk_configuration" {
  description = "Enable Risk Configuration (Account Takeover / Compromised Credentials)"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# EMAIL / SES CONFIGURATION
# -----------------------------------------------------------------------------

variable "email" {
  description = "Email configuration for Cognito"
  type = object({
    sending_account         = optional(string, "COGNITO_DEFAULT")
    ses_arn                 = optional(string, null)
    from_email_address      = optional(string, null)
    reply_to_email_address  = optional(string, null)
    email_configuration_set = optional(string, null)
  })
  default = {}
}

variable "invite_email" {
  description = "Configuration for admin-created user invitation email"
  type = object({
    subject = string
    message = string
  })
  default = {
    subject = "Welcome to the Application"
    message = "Your username is {username} and temporary password is {####}."
  }
}

variable "email_verification" {
  description = "Configuration for standard email verification"
  type = object({
    subject = string
    message = string
  })
  default = {
    subject = "Verify your email address"
    message = "Your verification code is {####}."
  }
}

# -----------------------------------------------------------------------------
# LAMBDA TRIGGERS
# -----------------------------------------------------------------------------

variable "lambda_triggers" {
  description = "A comprehensive object of all possible Lambda triggers for the Cognito user pool"
  type = object({
    create_auth_challenge          = optional(string, null)
    custom_message                 = optional(string, null)
    define_auth_challenge          = optional(string, null)
    post_authentication            = optional(string, null)
    post_confirmation              = optional(string, null)
    pre_authentication             = optional(string, null)
    pre_sign_up                    = optional(string, null)
    pre_token_generation           = optional(string, null)
    user_migration                 = optional(string, null)
    verify_auth_challenge_response = optional(string, null)
    kms_key_id                     = optional(string, null)
    custom_email_sender_arn        = optional(string, null)
    custom_email_sender_version    = optional(string, "V1_0")
    pre_token_generation_config = optional(object({
      lambda_arn     = string
      lambda_version = string
    }), null)
  })
  default = {}
}

# -----------------------------------------------------------------------------
# CLIENTS AND GROUPS
# -----------------------------------------------------------------------------

variable "clients" {
  description = "Map of user pool clients to create"
  type = map(object({
    name                          = string
    generate_secret               = optional(bool, false)
    prevent_user_existence_errors = optional(string, "ENABLED")
    explicit_auth_flows           = list(string)
    read_attributes               = optional(list(string))
    write_attributes              = optional(list(string))
    access_token_validity         = optional(number, 60)
    id_token_validity             = optional(number, 60)
    refresh_token_validity        = optional(number, 30)
    token_validity_units = optional(object({
      access_token  = optional(string, "minutes")
      id_token      = optional(string, "minutes")
      refresh_token = optional(string, "days")
    }), {})
    callback_urls                        = optional(list(string), [])
    logout_urls                          = optional(list(string), [])
    allowed_oauth_flows_user_pool_client = optional(bool, false)
    allowed_oauth_flows                  = optional(list(string), [])
    allowed_oauth_scopes                 = optional(list(string), [])
    supported_identity_providers         = optional(list(string), ["COGNITO"])
  }))
  default = {}
}

variable "groups" {
  description = "List of user groups to create"
  type = list(object({
    name        = string
    description = string
  }))
  default = []
}

# -----------------------------------------------------------------------------
# SCHEMA AND CONFIG
# -----------------------------------------------------------------------------

variable "custom_schema_attributes" {
  description = "List of custom schema attributes to append to the default ones"
  type = list(object({
    name                     = string
    attribute_data_type      = string
    developer_only_attribute = optional(bool, false)
    mutable                  = optional(bool, true)
    required                 = optional(bool, false)
    min_length               = optional(string, null)
    max_length               = optional(string, null)
  }))
  default = []
}

variable "web_authn_relying_party_id" {
  description = "The relying party ID for WebAuthn (e.g. localhost or example.com)"
  type        = string
  default     = "localhost"
}

variable "web_authn_user_verification" {
  description = "WebAuthn user verification requirement: required, preferred, or discouraged."
  type        = string
  default     = "required"
}

variable "allow_admin_create_user_only" {
  description = "Set to true to only allow administrators to create user profiles. When false, self-registration is allowed."
  type        = bool
  default     = true
}

variable "allowed_first_auth_factors" {
  description = "The list of allowed first authentication factors for user pool sign-in policy."
  type        = list(string)
  default     = ["PASSWORD", "EMAIL_OTP", "WEB_AUTHN"]
}

variable "mfa_configuration" {
  description = "Multi-Factor Authentication (MFA) configuration. Valid values: OFF, ON, OPTIONAL."
  type        = string
  default     = "OPTIONAL"
}

variable "password_policy" {
  description = "Password policy configuration for the Cognito User Pool."
  type = object({
    minimum_length                   = optional(number, 6)
    password_history_size            = optional(number, 5)
    require_lowercase                = optional(bool, true)
    require_numbers                  = optional(bool, true)
    require_symbols                  = optional(bool, true)
    require_uppercase                = optional(bool, true)
    temporary_password_validity_days = optional(number, 7)
  })
  default = {}
}

variable "read_attributes" {
  description = "List of standard attributes the user pool app clients can read. Defaults to standard profile attributes if not specified."
  type        = list(string)
  default     = null
}

variable "write_attributes" {
  description = "List of standard attributes the user pool app clients can write. Defaults to standard profile attributes if not specified."
  type        = list(string)
  default     = null
}

# -----------------------------------------------------------------------------
# LOGGING
# -----------------------------------------------------------------------------

variable "cloudwatch_logs" {
  description = "CloudWatch logs configuration"
  type = object({
    log_level         = optional(string, "ERROR")
    retention_in_days = optional(number, 30)
    kms_key_arn       = optional(string, null)
  })
  default = {}
}

# -----------------------------------------------------------------------------
# DOMAIN
# -----------------------------------------------------------------------------

variable "domain" {
  description = "The domain string for the Cognito User Pool (can be a prefix or a custom domain)"
  type        = string
  default     = null
}

variable "certificate_arn" {
  description = "The ARN of an ACM certificate in us-east-1 to be used with a custom domain"
  type        = string
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Additional tags to apply to all resources"
  default     = {}
}

variable "kms_key_arn" {
  description = "KMS Key ARN used for encrypting Cognito user pool CloudWatch logs and custom triggers. Strictly required."
  type        = string
}
