# Security baselines

## Capability-aware controls

Security is matched to what the cloud API actually supports, rather than applied as a
blanket mandate. Every control on every resource resolves to one of six statuses:

| Status | Meaning | What a module does |
| --- | --- | --- |
| `required` | Natively supported and non-negotiable. | Enforce it, with a production default. |
| `recommended` | Best practice with a real cost or operational trade-off. | Secure default, caller may override. |
| `optional` | Advanced or niche. | Opt-in sub-block, disabled by default. |
| `provider_managed` | The cloud already does it by default. | Add nothing; a redundant block is noise. |
| `not_supported` | Absent from the provider schema. | Never invent a synthetic argument for it. |
| `not_applicable` | Semantically meaningless here (KMS on an IAM role). | Omit entirely. |

The resolved AWS matrix — which control applies to which service — is in
**[AWS catalog](AWS.md)**. For a resource the matrix does not cover, derive the status
from `terraform providers schema -json`:

1. Absent from the schema → `not_supported`. A variable that maps to nothing reads as a
   control that is switched on.
2. Present, and the cloud applies it with no configuration → `provider_managed`.
3. Present, on a resource holding customer data at rest or in transit → `required`.
4. Present, with a material cost or operational trade-off (NAT gateways, long log retention,
   Multi-AZ) → `recommended`.
5. Present and niche (BYO-IP, cross-region replication, object lock) → `optional`.
6. Present but meaningless here (KMS on an IAM role) → `not_applicable`.

`not_supported` is a provider gap that may close in a later release and is worth a comment in
the module; `not_applicable` never closes. Starting tables for Azure and GCP are in
[Other providers](other-providers.md).

## Cryptographic key governance

1. **Explicit customer-managed keys only.** Every module encrypting data at rest takes a
   mandatory `kms_key_arn` / `kms_key_id` with no default. Silent fallback to an AWS managed
   key (`aws/s3`, `aws/rds`, `aws/sqs`) is prohibited.
2. **Annual rotation.** Keys from `modules/aws/security/kms` set `enable_key_rotation = true`.
3. **No key evasion.** SQS sets `kms_master_key_id` and `sqs_managed_sse_enabled = false`.
4. **Bucket keys.** S3 sets `bucket_key_enabled = true` to cut KMS request cost.
5. **Encrypted logs.** Every CloudWatch log group a module creates sets `kms_key_id`.

## Transport, exposure, and durability

- TLS 1.2 or higher on every endpoint and bucket policy.
- IMDSv2 required (`http_tokens = "required"`) on every launch template.
- Databases and compute land in private or intra subnets by default.
- Deletion protection on by default for stateful databases and storage.

## Credential handling

No module ever declares a default password, token, or key. `sensitive = true` masks a value
in CLI output and plan diffs — **it does not encrypt it in `terraform.tfstate`**, so a secret
passed as an ordinary input is stored in cleartext in state. In order of preference:

1. **Write-only arguments** (`password_wo`, `secret_string_wo`) where the provider offers
   them; the value never reaches state. Requires Terraform `>= 1.11.0`.
2. **External secret management** — reference an existing Secrets Manager secret, or let the
   service generate the credential.
3. **IAM authentication** (`iam_database_authentication_enabled = true`) in place of a static
   username and password.

IAM policies are composed with `data "aws_iam_policy_document"`, and avoid `Action = ["*"]`,
service-wide prefixes (`s3:*`), and `Resource = ["*"]` wherever the action can be scoped.

[Documentation index](../README.md#documentation)
