# AWS Amplify Hosting Module

Scope: `workload`

An Amplify Hosting web app with its branches, custom domains, security response headers and optional app-wide basic
auth for previews. Builds and deployments come from CI; branches never build on their own.

## Architecture & Managed Resources

- `aws_amplify_app.this`: `<application>-<environment>[-<name>]`, platform `WEB`.
- `aws_amplify_branch.this`: one per `branches` key, `enable_auto_build` off unless `auto_build`.
- `aws_amplify_domain_association.this`: one per `domain_associations` key, only the listed sub-domains, an Amplify
  managed certificate or `certificate_arn`.

## Security & Compliance Guardrails

- **Security headers:** `Strict-Transport-Security` (one year, sub-domains), `X-Content-Type-Options: nosniff`,
  `X-Frame-Options: SAMEORIGIN` and `Referrer-Policy: strict-origin-when-cross-origin` on every path.
  `custom_headers.yaml` replaces them (add `Content-Security-Policy` there; it depends on the app's origins);
  `custom_headers.enabled = false` leaves headers unmanaged. A `customHttp.yml` in the repository overrides both, and
  changes apply on the next deployment.
- **Basic auth:** username and an 8+ character password when enabled. The provider has no write-only argument, so the
  base64 pair is stored in state; prefer branch access control in the console for anything beyond short-lived previews.
- **Tags (Amplify.1, Amplify.2):** caller tags first, governance tags last on the app and every branch.
- **Custom domains:** with `wait_for_verification` (default) apply waits for DNS; set it to `false` when the records
  from `domain_dns_records` are created by the same apply. Each record is `{ name, type, value }`, ready for a Route 53
  record.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "web" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/storage/amplify?ref=<version>"

  application = "portal"
  environment = "prod"
  branches    = { main = {} }
}
```

### Complete Production Example

```hcl
module "web" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/storage/amplify?ref=<version>"

  application = "portal"
  environment = "prod"
  name        = "web"
  branches = {
    main    = { framework = "React" }
    staging = { stage = "BETA" }
  }

  domain_associations = {
    "example.com" = {
      certificate_arn       = module.certificate.arn
      wait_for_verification = false
      sub_domains = {
        app     = { branch_name = "main", prefix = "app" }
        staging = { branch_name = "staging", prefix = "staging" }
      }
    }
  }

  custom_rules = [{ source = "/<*>", target = "/index.html", status = "404-200" }]
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | **Required** | Yes |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `name` | App name suffix. | `string` | `null` | No |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `description` | App description. | `string` | `null` | No |
| `branches` | Branches by name; builds come from CI. | `map(object({...}))` | **Required** | Yes |
| `domain_associations` | Custom domains by name. | `map(object({...}))` | `{}` | No |
| `custom_rules` | Rewrite and redirect rules. | `list(object({...}))` | `[]` | No |
| `custom_headers` | Response headers: module security headers or your customHttp YAML. | `object({...})` | `{}` | No |
| `basic_auth` | App-wide basic auth; stored in state. | `object({...})` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `id` | App ID. | No |
| `arn` | App ARN. | No |
| `name` | App name. | No |
| `default_domain` | Default amplifyapp.com domain. | No |
| `branch_names` | Branch names. | No |
| `domain_dns_records` | DNS records by domain: certificate verification and sub-domains as name, type, value. | No |
