variable "application" {
  description = "Application name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,23}$", var.application))
    error_message = "application: 2-24 chars, a-z 0-9 -, starts with a letter."
  }
}

variable "environment" {
  description = "Environment name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,11}$", var.environment))
    error_message = "environment: 2-12 chars, a-z 0-9 -, starts with a letter."
  }
}

variable "name" {
  description = "User pool name suffix."
  type        = string
  default     = null

  validation {
    condition     = var.name == null || can(regex("^[a-z0-9][a-z0-9-]{0,31}$", coalesce(var.name, "-")))
    error_message = "name: 1-32 chars, a-z 0-9 -."
  }
}

variable "tags" {
  description = "Extra tags; governance tags win."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "kms" {
  description = "Encryption: {} service encryption, create = true module key, key_id your key (ARN or ID)."
  type = object({
    key_id                  = optional(string)
    create                  = optional(bool, false)
    deletion_window_in_days = optional(number, 30)
    policy_statements = optional(list(object({
      sid        = optional(string)
      effect     = optional(string, "Allow")
      actions    = list(string)
      resources  = optional(list(string))
      principals = optional(map(list(string)), {})
      conditions = optional(list(object({
        test     = string
        variable = string
        values   = list(string)
      })), [])
    })), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = !(var.kms.create && var.kms.key_id != null)
    error_message = "kms: set create or key_id, not both."
  }

  validation {
    condition     = var.kms.key_id == null || can(regex("^(arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/)?(mrk-[a-f0-9]{32}|[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})$", var.kms.key_id))
    error_message = "kms.key_id: a KMS key ARN or key ID."
  }
}

variable "user_pool_tier" {
  description = "Feature plan: LITE, ESSENTIALS or PLUS."
  type        = string
  default     = "ESSENTIALS"
  nullable    = false

  validation {
    condition     = contains(["LITE", "ESSENTIALS", "PLUS"], var.user_pool_tier)
    error_message = "user_pool_tier: LITE, ESSENTIALS or PLUS."
  }
}

variable "deletion_protection" {
  description = "Block deletion of the user pool."
  type        = bool
  default     = true
  nullable    = false
}

variable "threat_protection" {
  description = "Threat protection and risk actions (PLUS only)."
  type = object({
    enabled          = optional(bool, false)
    mode             = optional(string, "ENFORCED")
    custom_auth_mode = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["AUDIT", "ENFORCED"], var.threat_protection.mode) && contains(["AUDIT", "ENFORCED", "none"], coalesce(var.threat_protection.custom_auth_mode, "none"))
    error_message = "threat_protection: mode and custom_auth_mode AUDIT or ENFORCED."
  }

  validation {
    condition     = !var.threat_protection.enabled || var.user_pool_tier == "PLUS"
    error_message = "threat_protection: needs user_pool_tier PLUS."
  }
}

variable "password_policy" {
  description = "Password policy (Cognito.3)."
  type = object({
    minimum_length                   = optional(number, 14)
    password_history_size            = optional(number, 5)
    require_lowercase                = optional(bool, true)
    require_numbers                  = optional(bool, true)
    require_symbols                  = optional(bool, true)
    require_uppercase                = optional(bool, true)
    temporary_password_validity_days = optional(number, 7)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.password_policy.minimum_length >= 14 && var.password_policy.minimum_length <= 99
    error_message = "password_policy.minimum_length: 14-99."
  }

  validation {
    condition     = var.password_policy.password_history_size >= 0 && var.password_policy.password_history_size <= 24 && var.password_policy.temporary_password_validity_days >= 1 && var.password_policy.temporary_password_validity_days <= 365
    error_message = "password_policy: history 0-24, temporary validity 1-365 days."
  }
}

variable "mfa_configuration" {
  description = "MFA: ON, OPTIONAL or OFF (Cognito.5)."
  type        = string
  default     = "ON"
  nullable    = false

  validation {
    condition     = contains(["OFF", "OPTIONAL", "ON"], var.mfa_configuration)
    error_message = "mfa_configuration: OFF, OPTIONAL or ON."
  }

  validation {
    condition     = var.mfa_configuration != "ON" || length(setintersection(toset(var.allowed_first_auth_factors), toset(["EMAIL_OTP", "SMS_OTP"]))) == 0
    error_message = "mfa_configuration: ON excludes EMAIL_OTP and SMS_OTP first factors."
  }
}

variable "allowed_first_auth_factors" {
  description = "Sign-in first factors: PASSWORD, EMAIL_OTP, SMS_OTP, WEB_AUTHN."
  type        = list(string)
  default     = ["PASSWORD"]
  nullable    = false

  validation {
    condition     = contains(var.allowed_first_auth_factors, "PASSWORD") && alltrue([for f in var.allowed_first_auth_factors : contains(["PASSWORD", "EMAIL_OTP", "SMS_OTP", "WEB_AUTHN"], f)])
    error_message = "allowed_first_auth_factors: PASSWORD plus EMAIL_OTP, SMS_OTP or WEB_AUTHN."
  }

  validation {
    condition     = var.user_pool_tier != "LITE" || alltrue([for f in var.allowed_first_auth_factors : f == "PASSWORD"])
    error_message = "allowed_first_auth_factors: only PASSWORD on LITE."
  }
}

variable "web_authn" {
  description = "Passkeys: relying party domain and user verification."
  type = object({
    relying_party_id  = optional(string)
    user_verification = optional(string, "required")
  })
  default  = {}
  nullable = false

  validation {
    condition     = !contains(var.allowed_first_auth_factors, "WEB_AUTHN") || var.web_authn.relying_party_id != null
    error_message = "web_authn.relying_party_id: required with WEB_AUTHN."
  }

  validation {
    condition     = contains(["required", "preferred"], var.web_authn.user_verification)
    error_message = "web_authn.user_verification: required or preferred."
  }
}

variable "self_sign_up" {
  description = "Let users sign themselves up."
  type = object({
    enabled = optional(bool, false)
  })
  default  = {}
  nullable = false
}

variable "invite_message" {
  description = "Invitation email for admin-created users."
  type = object({
    email_subject = optional(string, "Your temporary password")
    email_message = optional(string, "Your username is {username} and temporary password is {####}.")
  })
  default  = {}
  nullable = false

  validation {
    condition     = strcontains(var.invite_message.email_message, "{username}") && strcontains(var.invite_message.email_message, "{####}")
    error_message = "invite_message.email_message: needs {username} and {####}."
  }
}

variable "verification_message" {
  description = "Verification email: code or link."
  type = object({
    default_email_option  = optional(string, "CONFIRM_WITH_LINK")
    email_subject         = optional(string, "Your verification code")
    email_message         = optional(string, "Your verification code is {####}.")
    email_subject_by_link = optional(string, "Verify your email address")
    email_message_by_link = optional(string, "Please click the link below to verify your email address. {##Verify Email##}")
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["CONFIRM_WITH_CODE", "CONFIRM_WITH_LINK"], var.verification_message.default_email_option)
    error_message = "verification_message.default_email_option: CONFIRM_WITH_CODE or CONFIRM_WITH_LINK."
  }

  validation {
    condition     = strcontains(var.verification_message.email_message, "{####}") && can(regex("\\{##.+##\\}", var.verification_message.email_message_by_link))
    error_message = "verification_message: {####} in email_message, {##text##} in email_message_by_link."
  }
}

variable "email" {
  description = "Email sending: COGNITO_DEFAULT or DEVELOPER with an SES identity."
  type = object({
    sending_account        = optional(string, "COGNITO_DEFAULT")
    ses_identity_arn       = optional(string)
    from_email_address     = optional(string)
    reply_to_email_address = optional(string)
    configuration_set      = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["COGNITO_DEFAULT", "DEVELOPER"], var.email.sending_account)
    error_message = "email.sending_account: COGNITO_DEFAULT or DEVELOPER."
  }

  validation {
    condition     = var.email.sending_account == "COGNITO_DEFAULT" || var.email.ses_identity_arn != null
    error_message = "email.ses_identity_arn: required with DEVELOPER."
  }

  validation {
    condition     = var.email.ses_identity_arn == null || can(regex("^arn:aws[a-z-]*:ses:[a-z0-9-]+:[0-9]{12}:identity/.+$", var.email.ses_identity_arn))
    error_message = "email.ses_identity_arn: an SES identity ARN."
  }
}

variable "lambda_triggers" {
  description = "Lambda triggers by name: ARN and version."
  type = map(object({
    arn     = string
    version = optional(string, "V1_0")
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k in keys(var.lambda_triggers) : contains(["create_auth_challenge", "custom_message", "define_auth_challenge", "post_authentication", "post_confirmation", "pre_authentication", "pre_sign_up", "pre_token_generation", "user_migration", "verify_auth_challenge_response", "custom_email_sender", "custom_sms_sender"], k)])
    error_message = "lambda_triggers: unknown trigger name."
  }

  validation {
    condition     = alltrue([for t in values(var.lambda_triggers) : contains(["V1_0", "V2_0", "V3_0"], t.version)])
    error_message = "lambda_triggers[*].version: V1_0, V2_0 or V3_0."
  }

  validation {
    condition     = length(setintersection(toset(keys(var.lambda_triggers)), toset(["custom_email_sender", "custom_sms_sender"]))) == 0 || var.kms.create || var.kms.key_id != null
    error_message = "lambda_triggers: custom senders need kms.create or kms.key_id."
  }
}

variable "custom_attributes" {
  description = "Custom attributes by name: String or Number with limits."
  type = map(object({
    type           = optional(string, "String")
    mutable        = optional(bool, true)
    developer_only = optional(bool, false)
    min_length     = optional(number)
    max_length     = optional(number)
    min_value      = optional(number)
    max_value      = optional(number)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k, a in var.custom_attributes : can(regex("^[a-zA-Z0-9_]{1,20}$", k)) && contains(["String", "Number"], a.type)])
    error_message = "custom_attributes: 1-20 chars of a-z A-Z 0-9 _, type String or Number."
  }
}

variable "read_attributes" {
  description = "Standard attributes clients may read."
  type        = list(string)
  default     = ["address", "birthdate", "email", "email_verified", "family_name", "gender", "given_name", "locale", "middle_name", "name", "nickname", "phone_number", "phone_number_verified", "picture", "preferred_username", "profile", "updated_at", "website", "zoneinfo"]
  nullable    = false
}

variable "write_attributes" {
  description = "Standard attributes clients may write."
  type        = list(string)
  default     = ["address", "birthdate", "email", "family_name", "gender", "given_name", "locale", "middle_name", "name", "nickname", "phone_number", "picture", "preferred_username", "profile", "updated_at", "website", "zoneinfo"]
  nullable    = false
}

variable "clients" {
  description = "App clients by name."
  type = map(object({
    generate_secret               = optional(bool, false)
    explicit_auth_flows           = optional(list(string), ["ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"])
    read_attributes               = optional(list(string))
    write_attributes              = optional(list(string))
    access_token_validity_minutes = optional(number, 60)
    id_token_validity_minutes     = optional(number, 60)
    refresh_token_validity_days   = optional(number, 30)
    callback_urls                 = optional(list(string), [])
    logout_urls                   = optional(list(string), [])
    allowed_oauth_flows           = optional(list(string), [])
    allowed_oauth_scopes          = optional(list(string), [])
    supported_identity_providers  = optional(list(string), ["COGNITO"])
    refresh_token_rotation = optional(object({
      enabled                    = optional(bool, false)
      retry_grace_period_seconds = optional(number, 0)
    }), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue(flatten([for c in values(var.clients) : [for f in c.explicit_auth_flows : contains(["ALLOW_USER_AUTH", "ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH", "ALLOW_CUSTOM_AUTH", "ALLOW_USER_PASSWORD_AUTH", "ALLOW_ADMIN_USER_PASSWORD_AUTH"], f)]]))
    error_message = "clients[*].explicit_auth_flows: ALLOW_* flows only."
  }

  validation {
    condition     = alltrue(flatten([for c in values(var.clients) : [for f in c.allowed_oauth_flows : contains(["code", "client_credentials"], f)]]))
    error_message = "clients[*].allowed_oauth_flows: code or client_credentials."
  }

  validation {
    condition     = alltrue([for c in values(var.clients) : c.access_token_validity_minutes >= 5 && c.access_token_validity_minutes <= 1440 && c.id_token_validity_minutes >= 5 && c.id_token_validity_minutes <= 1440 && c.refresh_token_validity_days >= 1 && c.refresh_token_validity_days <= 3650])
    error_message = "clients: access and ID tokens 5-1440 minutes, refresh 1-3650 days."
  }

  validation {
    condition     = alltrue([for c in values(var.clients) : c.refresh_token_rotation.retry_grace_period_seconds >= 0 && c.refresh_token_rotation.retry_grace_period_seconds <= 60])
    error_message = "clients[*].refresh_token_rotation.retry_grace_period_seconds: 0-60."
  }

  validation {
    condition     = var.user_pool_tier != "LITE" || alltrue([for c in values(var.clients) : !c.refresh_token_rotation.enabled])
    error_message = "clients[*].refresh_token_rotation: needs ESSENTIALS or PLUS."
  }

  validation {
    condition     = alltrue([for c in values(var.clients) : !(c.refresh_token_rotation.enabled && contains(c.explicit_auth_flows, "ALLOW_REFRESH_TOKEN_AUTH"))])
    error_message = "clients[*].refresh_token_rotation: drop ALLOW_REFRESH_TOKEN_AUTH."
  }
}

variable "groups" {
  description = "User groups by name."
  type = map(object({
    description = optional(string)
    precedence  = optional(number)
    role_arn    = optional(string)
  }))
  default  = {}
  nullable = false
}

variable "domain" {
  description = "Hosted domain: prefix or custom_domain; managed login 2 except on LITE."
  type = object({
    enabled               = optional(bool, false)
    custom_domain         = optional(string)
    certificate_arn       = optional(string)
    managed_login_version = optional(number)
  })
  default  = {}
  nullable = false

  validation {
    condition     = (var.domain.custom_domain == null) == (var.domain.certificate_arn == null)
    error_message = "domain: set custom_domain with certificate_arn."
  }

  validation {
    condition     = var.domain.managed_login_version == null || contains([1, 2], coalesce(var.domain.managed_login_version, 0))
    error_message = "domain.managed_login_version: 1 or 2."
  }

  validation {
    condition     = var.user_pool_tier != "LITE" || var.domain.managed_login_version != 2
    error_message = "domain.managed_login_version: 2 needs ESSENTIALS or PLUS."
  }
}

variable "cloudwatch_logs" {
  description = "CloudWatch log group."
  type = object({
    enabled                     = optional(bool, true)
    retention_in_days           = optional(number, 365)
    log_group_class             = optional(string, "STANDARD")
    deletion_protection_enabled = optional(bool, true)
    kms_key_arn                 = optional(string)
  })
  default  = {}
  nullable = false
}
