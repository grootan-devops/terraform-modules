# AWS ECR Repository Module

Scope: `workload`

A private ECR repository with immutable tags, scan on push, encryption, an image lifecycle policy and an optional
repository policy for cross-account pulls. Registry-wide settings (enhanced scanning, replication, pull-through cache)
belong to the account baseline, not here.

## Architecture & Managed Resources

- `aws_ecr_repository.this`: `<application>-<environment>-<name>`, `IMMUTABLE` tags, scan on push, never force-deleted.
- `aws_ecr_lifecycle_policy.this`: expires untagged images after 14 days and keeps the last 30 tagged images.
- `aws_ecr_repository_policy.this`: only when `pull_principal_arns` or `policy_statements` is set.
- `module.encryption` ([`core/encryption`](../../core/encryption)): AES256, module key or your key.
- `module.policy` ([`core/policy-document`](../../core/policy-document)): statements without `resources` apply to the
  repository.

## Security & Compliance Guardrails

- **Immutable tags (ECR.2):** `IMMUTABLE` by default; `*_WITH_EXCLUSION` modes take up to 5 wildcard filters.
- **Scan on push (ECR.1):** on by default. A registry scanning configuration (enhanced scanning) overrides it.
- **Lifecycle policy (ECR.3):** on by default.
- **Encryption:** AES256 (ECR's default encryption) with no `kms` input; `kms.create` or `kms.key_id` switches to
  SSE-KMS. ECR uses KMS grants created by the deploying principal, which needs `kms:CreateGrant`, `kms:DescribeKey`
  and `kms:Decrypt` on the key.
- **No public access:** `pull_principal_arns` rejects `*`; caller statements need principals, and an `Allow` to `*`
  needs a condition. Cross-account principals get `BatchGetImage`, `GetDownloadUrlForLayer` and
  `BatchCheckLayerAvailability` only.
- **Retention:** `force_delete = false`: a repository that still holds images is not deleted.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "ecr" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/compute/ecr?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "orders"
}
```

### Complete Production Example

```hcl
module "ecr" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/compute/ecr?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "orders"
  kms         = { create = true }

  image_tag_mutability                   = "IMMUTABLE_WITH_EXCLUSION"
  image_tag_mutability_exclusion_filters = ["latest"]
  lifecycle_policy                       = { keep_tagged_images = 50, untagged_expiry_days = 7 }

  pull_principal_arns = ["arn:aws:iam::210987654321:root"]
  policy_statements = [{
    sid        = "LambdaPull"
    actions    = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer"]
    principals = { Service = ["lambda.amazonaws.com"] }
    conditions = [{ test = "StringLike", variable = "aws:sourceArn", values = ["${module.lambda.arn}*"] }]
  }]
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | **Required** | Yes |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `name` | Repository name. | `string` | **Required** | Yes |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `image_tag_mutability` | IMMUTABLE, MUTABLE, IMMUTABLE_WITH_EXCLUSION or MUTABLE_WITH_EXCLUSION. | `string` | `"IMMUTABLE"` | No |
| `image_tag_mutability_exclusion_filters` | Tag wildcards exempt from the mutability setting. | `list(string)` | `[]` | No |
| `scan_on_push` | Scan images on push. | `bool` | `true` | No |
| `kms` | Encryption: {} AES256, create = true module key, key_id your key (ARN or ID). | `object({...})` | `{}` | No |
| `lifecycle_policy` | Image expiry: last tagged images kept, untagged images expired after days. | `object({...})` | `{}` | No |
| `pull_principal_arns` | AWS principals (account root or role ARNs) allowed to pull. | `list(string)` | `[]` | No |
| `policy_statements` | Repository policy statements; resources default to the repository. | `list(object({...}))` | `[]` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `arn` | Repository ARN. | No |
| `name` | Repository name. | No |
| `repository_url` | Repository URL for docker push and pull. | No |
| `registry_id` | Registry (account) ID. | No |
| `kms_key_arn` | Key ARN in use; null for AES256. | No |
