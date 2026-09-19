# AWS Cognito User Pool Module

The `cognito` module provisions Amazon Cognito User Pools, App Clients, risk configuration for adaptive authentication, SES custom email integration, and KMS-encrypted CloudWatch logs.

### Architecture & Managed Resources
- `aws_cognito_user_pool.this`: Primary user directory.
- `aws_cognito_user_pool_client.this`: Configured application clients with OAuth grants.
- `aws_cognito_user_pool_risk_configuration.this`: Advanced Security Features (ASF) risk engine.
- `aws_cloudwatch_log_group.this`: KMS-encrypted user activity log group.

### Security & Compliance Guardrails
- **Mandatory KMS Logging**: CloudWatch logs require `kms_key_arn`.
- **Advanced Security Features**: Configurable risk actions and compromised credential blocking.

---

## Requirements & Providers

| Requirement | Version |
|---|---|
| `terraform` | `>= 1.5.0` |
| `aws` | `>= 6.0.0, < 7.0.0` |

---

## Usage Examples

### Minimal Working Example
```hcl
module "cognito" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/cognito?ref=1.0.0"

  application = "core"
  environment = "prod"
  name        = "users"
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
}
```

### Complete Production Example
```hcl
module "cognito" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/cognito?ref=1.0.0"

  application = "identity"
  environment = "prod"
  name        = "customers"
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"

  password_policy = {
    minimum_length    = 14
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  clients = {
    web_app = {
      name                         = "web-client"
      generate_secret              = false
      allowed_oauth_flows          = ["code"]
      allowed_oauth_scopes         = ["email", "openid", "profile"]
      callback_urls                = ["https://app.company.com/oauth/callback"]
      logout_urls                  = ["https://app.company.com/logout"]
      supported_identity_providers = ["COGNITO"]
    }
  }

  cloudwatch_logs = {
    retention_in_days = 90
    log_level         = "ERROR"
    kms_key_arn       = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
  }

  tags = {
    SecurityBoundary = "CustomerAuth"
  }
}
```

---

## Inputs Specification

| Name | Description | Type | Default | Required |
|---|---|---|---|:---:|
| `name` | Name of the Cognito User Pool | `string` | **Required** | Yes |
| `application` | Application name | `string` | **Required** | Yes |
| `environment` | Deployment environment name (e.g. dev, staging, prod). | `string` | **Required** | Yes |
| `user_pool_tier` | The User Pool Tier (e.g., ESSENTIALS, PLUS) | `string` | `"ESSENTIALS"` | No |
| `advanced_security_mode` | Set to OFF, AUDIT, or ENFORCED to enable Advanced Security Features | `string` | `"OFF"` | No |
| `enable_risk_configuration` | Enable Risk Configuration (Account Takeover / Compromised Credentials) | `bool` | `false` | No |
| `email` | Email configuration for Cognito | `object({...})` | `{}` | No |
| `invite_email` | Configuration for admin-created user invitation email | `object({...})` | `{...}` | No |
| `email_verification` | Configuration for standard email verification | `object({...})` | `{...}` | No |
| `lambda_triggers` | A comprehensive object of all possible Lambda triggers for the Cognito user pool | `object({...})` | `{}` | No |
| `clients` | Map of user pool clients to create | `map(object({...}))` | `{}` | No |
| `groups` | List of user groups to create | `list(object({...}))` | `[]` | No |
| `custom_schema_attributes` | List of custom schema attributes to append to the default ones | `list(object({...}))` | `[]` | No |
| `web_authn_relying_party_id` | The relying party ID for WebAuthn (e.g. localhost or contoso.com) | `string` | `"localhost"` | No |
| `web_authn_user_verification` | WebAuthn user verification requirement: required, preferred, or discouraged. | `string` | `"required"` | No |
| `allow_admin_create_user_only` | Set to true to only allow administrators to create user profiles. When false, self-registration is allowed. | `bool` | `true` | No |
| `allowed_first_auth_factors` | The list of allowed first authentication factors for user pool sign-in policy. | `list(string)` | `["PASSWORD", "EMAIL_OTP", "WEB_AUTHN"]` | No |
| `mfa_configuration` | Multi-Factor Authentication (MFA) configuration. Valid values: OFF, ON, OPTIONAL. | `string` | `"OPTIONAL"` | No |
| `password_policy` | Password policy configuration for the Cognito User Pool. | `object({...})` | `{}` | No |
| `read_attributes` | List of standard attributes the user pool app clients can read. Defaults to standard profile attributes if not specified. | `list(string)` | `null` | No |
| `write_attributes` | List of standard attributes the user pool app clients can write. Defaults to standard profile attributes if not specified. | `list(string)` | `null` | No |
| `cloudwatch_logs` | CloudWatch logs configuration | `object({...})` | `{}` | No |
| `domain` | The domain string for the Cognito User Pool (can be a prefix or a custom domain) | `string` | `null` | No |
| `certificate_arn` | The ARN of an ACM certificate in us-east-1 to be used with a custom domain | `string` | `null` | No |
| `tags` | Additional tags to apply to all resources | `map(string)` | `{}` | No |
| `kms_key_arn` | KMS Key ARN used for encrypting Cognito user pool CloudWatch logs and custom triggers. Strictly required. | `string` | **Required** | Yes |


---

## Outputs Specification

| Name | Description | Sensitive |
|---|---|:---:|
| `user_pool_id` | Cognito user pool identifier. | No |
| `user_pool_arn` | Cognito user pool ARN. | No |
| `client_ids` | Map of client key (from var.clients) -> Cognito app client id. | No |
| `user_pool_endpoint` | The endpoint name of the user pool. | No |

