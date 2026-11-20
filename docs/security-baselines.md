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

Every module that stores data takes the same `kms` input ([Module contract](module-contract.md#encryption)):

1. **Encrypted by default, never plaintext.** With no input the service's AWS managed key or service-owned encryption
   is used (`aws/s3`, `aws/rds`, SSE-SQS, CloudWatch Logs service encryption). This passes the encryption-at-rest
   controls; controls that require a customer managed key report `PARTIAL` until one is set.
2. **One switch for a dedicated key.** `kms = { create = true }` creates a customer managed key owned by the module
   (rotation on, deletion window 30 days) whose key policy grants only the service principals the module uses, scoped
   with `aws:SourceArn`, `aws:SourceAccount` or an encryption-context condition.
3. **Bring your own key.** `kms = { key_id = ... }` takes a key ARN or key ID. The module README lists the
   principals its key policy must grant.
4. **Bucket keys.** S3 sets `bucket_key_enabled = true` whenever a KMS key is used.
5. **Logs follow the module key.** A log group's `kms_key_arn` falls back to the module key, so a module with a
   customer managed key encrypts its logs with it.

## Transport, exposure, and durability

- TLS 1.2 or higher on every endpoint and bucket policy.
- IMDSv2 required (`http_tokens = "required"`) on every launch template.
- Databases and compute land in private or intra subnets by default.
- Deletion protection on by default for stateful databases and storage.

## Organization guardrails and detective controls

Module defaults protect each resource; the organization layer stops an account from turning those protections
off and reports drift:

- **Preventive:** SCPs, RCPs and declarative policies from
  [`modules/aws/governance/organizations`](../modules/aws/governance/organizations). They are created without
  attachments and rolled out from a sandbox OU ([AWS Organizations governance](compliance/aws-organizations-governance.md)).
- **Detective:** AWS Config recording and rules, Security Hub CSPM standards, Inspector and IAM Access Analyzer from
  the modules under `modules/aws/security/`.
- **Evidence:** the [compliance documentation](compliance/README.md) maps every enforced control to its code.

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

IAM and resource policies are built as `jsonencode` locals or through
[`core/policy-document`](../modules/aws/core/policy-document), so the tests can read every statement offline (a mocked
`aws_iam_policy_document` returns no real JSON). They avoid `Action = ["*"]`, service-wide prefixes (`s3:*`) and
`Resource = ["*"]` wherever the action can be scoped.

## Network defaults

- Security groups are created through [`network/security-group`](../modules/aws/network/security-group) with one
  `aws_vpc_security_group_ingress_rule` or `egress_rule` per source, never inline rules. The group's rules are
  exclusive (`aws_vpc_security_group_rules_exclusive`): a rule added outside Terraform is removed on the next apply, so
  extra sources go through the module inputs.
- A module opens only its own port, only to the security groups, CIDRs and prefix lists the caller lists. Ingress
  from `0.0.0.0/0` or `::/0` is rejected except on internet-facing load balancers.
- Egress is empty unless the service starts connections itself (functions, tasks, proxies).

## IAM roles

Every role comes from [`security/iam-role`](../modules/aws/security/iam-role): the trust policy names one service, with
`aws:SourceAccount`/`aws:SourceArn` where the service supports them; the module grants only what the service needs; an
optional permissions boundary applies to every role; role names include the Region so a second Region never collides.
Inline policies and managed policy attachments are exclusive (`aws_iam_role_policies_exclusive`,
`aws_iam_role_policy_attachments_exclusive`): a policy attached outside Terraform is removed on the next apply, so
callers extend a role only through `iam_role.policy_statements` and `iam_role.managed_policy_arns`. Identity Center
permission sets do the same for their managed and customer managed policy attachments.

[Documentation index](../README.md#documentation)
