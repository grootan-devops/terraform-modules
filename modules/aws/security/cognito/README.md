# AWS Cognito User Pool Module

Scope: `workload`

A Cognito user pool with required MFA, a 14-character password policy, app clients, groups, an optional hosted
domain with managed login, Lambda triggers, notification-error logs and, on the Plus plan, threat protection with user
activity logs.

## Architecture & Managed Resources

- `aws_cognito_user_pool.this`: `<application>-<environment>[-<name>]`, email as username, verified-email recovery.
- `aws_cognito_user_pool_client.this`, `aws_cognito_user_group.this`: one per `clients` and `groups` key.
- `module.log_group` ([`observability/log-group`](../../observability/log-group)):
  `/aws/vendedlogs/cognito/<pool>` and `aws_cognito_log_delivery_configuration.this`.
- `aws_cognito_risk_configuration.this`: with threat protection on PLUS.
- `aws_cognito_user_pool_domain.this`: prefix `<application>-<environment>[-<name>]-<account>-<region>` or
  `custom_domain`; managed login (version 2) on ESSENTIALS and PLUS, the classic hosted UI (version 1) on LITE, unless
  `domain.managed_login_version` says otherwise.
- `aws_cognito_managed_login_branding.this`: one Cognito default style per `clients` key while the domain serves
  managed login. Clients created through the API have no style, and managed login shows an error page without one.
- `aws_sesv2_email_identity_policy.this`: with `email.sending_account = "DEVELOPER"`, on the identity named in
  `email.ses_identity_arn`, in that ARN's Region.
- `module.encryption` ([`core/encryption`](../../core/encryption)): no key, module key or your key.

## Security & Compliance Guardrails

- **Passwords (Cognito.3):** at least 14 characters (validated), all character classes, history of 5 (not on LITE),
  7-day temporary passwords.
- **MFA (Cognito.5):** `ON` with TOTP by default; `ON` cannot be combined with `EMAIL_OTP` or `SMS_OTP` first factors.
  Passkeys need `web_authn.relying_party_id`.
- **Threat protection (Cognito.1, Cognito.4):** `threat_protection.enabled` needs `user_pool_tier = "PLUS"` (billed per
  monthly active user, so off by default); it sets `ENFORCED` mode, blocks compromised credentials and high-risk
  sign-ins, and exports `userAuthEvents` at `INFO`.
- **Logs:** `userNotification` errors are exported on every tier to a 365-day log group with deletion protection;
  the `/aws/vendedlogs/` prefix keeps the CloudWatch Logs resource policy small.
- **Encryption:** the user pool itself uses AWS owned keys. The module key (`kms.create`) or `kms.key_id` encrypts the
  log group and the codes sent to custom email and SMS sender triggers, which require a key.
- **Clients:** user-existence errors hidden, token revocation on, SRP and refresh-token flows by default; OAuth `code`
  or `client_credentials` only (no implicit grant).
- **Refresh token rotation:** opt-in per client (`refresh_token_rotation.enabled`, grace period 0-60 seconds), because
  the client must store the new refresh token from every refresh. It needs ESSENTIALS or PLUS and cannot be combined
  with `ALLOW_REFRESH_TOKEN_AUTH`; such clients refresh with `GetTokensFromRefreshToken` or the token endpoint.
- **Managed login:** version 2 is rejected on LITE, which offers only the classic hosted UI.
- **SES:** the identity policy allows only Cognito, only for this pool (`aws:SourceArn`) and account.
- **Deletion protection (Cognito.6):** on by default; only admins create users unless `self_sign_up.enabled`.

The Lambda functions behind triggers need an invoke permission for `cognito-idp.amazonaws.com` with this pool's ARN
([`compute/lambda`](../../compute/lambda) `allowed_triggers`), and custom sender functions need `kms:Decrypt` on the key.
A key passed in `kms.key_id` must allow `logs.<region>.amazonaws.com` (encryption context `aws:logs:arn`) and
`kms:CreateGrant` for the principal that deploys the pool.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "cognito" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/cognito?ref=<version>"

  application = "core"
  environment = "prod"
}
```

### Complete Production Example

```hcl
module "cognito" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/security/cognito?ref=<version>"

  application       = "core"
  environment       = "prod"
  user_pool_tier    = "PLUS"
  threat_protection = { enabled = true }
  kms               = { create = true }

  email = {
    sending_account    = "DEVELOPER"
    ses_identity_arn   = "arn:aws:ses:eu-west-1:123456789012:identity/example.com"
    from_email_address = "no-reply@example.com"
  }

  lambda_triggers = {
    pre_sign_up         = { arn = module.signup_fn.alias_arn }
    custom_email_sender = { arn = module.mailer_fn.alias_arn }
  }

  clients = {
    web = {
      callback_urls          = ["https://app.example.com/callback"]
      logout_urls            = ["https://app.example.com/"]
      allowed_oauth_flows    = ["code"]
      allowed_oauth_scopes   = ["openid", "email", "profile"]
      explicit_auth_flows    = ["ALLOW_USER_SRP_AUTH"]
      refresh_token_rotation = { enabled = true, retry_grace_period_seconds = 10 }
    }
  }

  groups = { admins = { description = "Administrators", precedence = 1 } }
  domain = { enabled = true, custom_domain = "auth.example.com", certificate_arn = module.certificate_us_east_1.arn }
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | **Required** | Yes |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `name` | User pool name suffix. | `string` | `null` | No |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `kms` | Encryption: {} service encryption, create = true module key, key_id your key (ARN or ID). | `object({...})` | `{}` | No |
| `user_pool_tier` | Feature plan: LITE, ESSENTIALS or PLUS. | `string` | `"ESSENTIALS"` | No |
| `deletion_protection` | Block deletion of the user pool. | `bool` | `true` | No |
| `threat_protection` | Threat protection and risk actions (PLUS only). | `object({...})` | `{}` | No |
| `password_policy` | Password policy (Cognito.3). | `object({...})` | `{}` | No |
| `mfa_configuration` | MFA: ON, OPTIONAL or OFF (Cognito.5). | `string` | `"ON"` | No |
| `allowed_first_auth_factors` | Sign-in first factors: PASSWORD, EMAIL_OTP, SMS_OTP, WEB_AUTHN. | `list(string)` | `["PASSWORD"]` | No |
| `web_authn` | Passkeys: relying party domain and user verification. | `object({...})` | `{}` | No |
| `self_sign_up` | Let users sign themselves up. | `object({...})` | `{}` | No |
| `invite_message` | Invitation email for admin-created users. | `object({...})` | `{}` | No |
| `verification_message` | Verification email: code or link. | `object({...})` | `{}` | No |
| `email` | Email sending: COGNITO_DEFAULT or DEVELOPER with an SES identity. | `object({...})` | `{}` | No |
| `lambda_triggers` | Lambda triggers by name: ARN and version. | `map(object({...}))` | `{}` | No |
| `custom_attributes` | Custom attributes by name: String or Number with limits. | `map(object({...}))` | `{}` | No |
| `read_attributes` | Standard attributes clients may read. | `list(string)` | `["address", "birthdate", "email", "email_verified", "family_name", "gender", "given_name", "locale", "middle_name", "name", "nickname", "phone_number", "phone_number_verified", "picture", "preferred_username", "profile", "updated_at", "website", "zoneinfo"]` | No |
| `write_attributes` | Standard attributes clients may write. | `list(string)` | `["address", "birthdate", "email", "family_name", "gender", "given_name", "locale", "middle_name", "name", "nickname", "phone_number", "picture", "preferred_username", "profile", "updated_at", "website", "zoneinfo"]` | No |
| `clients` | App clients by name. | `map(object({...}))` | `{}` | No |
| `groups` | User groups by name. | `map(object({...}))` | `{}` | No |
| `domain` | Hosted domain: prefix or custom_domain; managed login 2 except on LITE. | `object({...})` | `{}` | No |
| `cloudwatch_logs` | CloudWatch log group. | `object({...})` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `id` | User pool ID. | No |
| `arn` | User pool ARN. | No |
| `name` | User pool name. | No |
| `endpoint` | User pool endpoint (issuer host). | No |
| `client_ids` | App client IDs by name. | No |
| `domain` | Hosted domain; null when disabled. | No |
| `domain_dns_name` | CloudFront alias target of a custom domain. | No |
| `domain_zone_id` | Hosted zone ID of the alias target. | No |
| `log_group_name` | Log group name; null when disabled. | No |
| `log_group_arn` | Log group ARN; null when disabled. | No |
| `kms_key_arn` | Key ARN in use; null without a key. | No |
