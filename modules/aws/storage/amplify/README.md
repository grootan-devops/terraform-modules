# AWS Amplify Web Hosting Module

The `amplify` module provisions AWS Amplify Web Hosting apps with multi-branch deployment pipelines, custom domain associations, and staging basic authentication.

## Architecture & Managed Resources

- `aws_amplify_app.this`: Amplify hosting application container.
- `aws_amplify_branch.this`: Managed deployment branches (`main`, `preview`).
- `aws_amplify_domain_association.this`: Custom domain and sub-domain SSL associations.

### Security & Compliance Guardrails

- **Managed S3 Isolation**: Assets are deployed to dedicated AWS Amplify hosting infrastructure.
- **Custom SSL Integration**: Supports custom ACM certificates or automated Amplify-managed certificates.

---

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.5.0` |
| `aws` | `>= 6.0.0, < 7.0.0` |

---

## Usage Examples

### Minimal Working Example

```hcl
module "amplify" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/storage/amplify?ref=1.0.0"

  application = "core"
  environment = "prod"
  name        = "frontend"
  branches    = ["main"]
}
```

### Complete Production Example

```hcl
module "amplify" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/storage/amplify?ref=1.0.0"

  application = "portal"
  environment = "prod"
  name        = "web-app"
  branches    = ["main", "staging"]

  basic_auth = {
    enable   = false
    username = "admin"
    password = var.staging_password
  }

  domain_associations = {
    "company.com" = {
      sub_domains = [
        { branch_name = "main", prefix = "app" },
        { branch_name = "staging", prefix = "staging-app" }
      ]
    }
  }

  custom_rules = [
    {
      source = "/<*>"
      target = "/index.html"
      status = "200"
    }
  ]

  tags = {
    FrontEndTier = "SinglePageApp"
  }
}
```

---

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | :---: |
| `application` | Application name | `string` | **Required** | Yes |
| `environment` | Deployment environment name (e.g. dev, staging, prod). | `string` | **Required** | Yes |
| `branches` | List of branch names to create in Amplify | `list(string)` | **Required** | Yes |
| `domain_associations` | Map of domain names to their subdomains and branch associations | `map(object({...}))` | `{}` | No |
| `custom_rules` | List of custom rewrite/redirect rules | `list(object({...}))` | `[]` | No |
| `custom_headers` | Optional custom headers YAML configuration | `string` | `null` | No |
| `basic_auth` | Basic auth configuration for the Amplify app | `object({...})` | `{}` | No |
| `name` | Name for the resource. If not provided, will be derived from application and environment. | `string` | `null` | No |
| `tags` | Additional tags to apply to all resources | `map(string)` | `{}` | No |

---

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | :---: |
| `app_id` | Unique ID of the Amplify App. | No |
| `app_arn` | ARN of the Amplify App. | No |
| `default_domain` | Default domain for the Amplify App. | No |
| `branch_arns` | Map of branch names to branch ARNs. | No |
