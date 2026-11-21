# AWS Lambda Module

Scope: `workload`

A Lambda function with everything it needs to run: execution role, log group, alias, optional customer managed key,
optional VPC security group, event source mappings, invoke permissions, function URL and async invocation settings.
Queues, streams, topics and buses are other modules; pass their ARNs in.

## Architecture & Managed Resources

- `aws_lambda_function.this`: `<application>-<environment>-<name>`, published versions; a placeholder package when no
  code is given (CI deploys code later; code fields are ignored after creation).
- `aws_lambda_alias.this` (`live`): every trigger, URL and provisioned concurrency targets the alias.
- `module.role` ([`security/iam-role`](../../security/iam-role)): execution role `<...>-lambda-<region>`, trusted by
  Lambda in this account only.
- `module.log_group` ([`observability/log-group`](../../observability/log-group)): `/aws/lambda/<function>`.
- `module.encryption` ([`core/encryption`](../../core/encryption)): AWS managed key, module key or your key.
- `module.security_group` ([`network/security-group`](../../network/security-group)): when `subnet_ids` is set.
- `aws_lambda_event_source_mapping.this`, `aws_lambda_permission.this`, `aws_lambda_function_url.this`,
  `aws_lambda_function_event_invoke_config.this`, `aws_lambda_provisioned_concurrency_config.this`,
  `aws_lambda_function_recursion_config.this`, `aws_lambda_runtime_management_config.this`.

## Security & Compliance Guardrails

- **Supported runtimes (Lambda.2):** `package.runtime` must be a generally available runtime on Amazon Linux 2023
  (AL2-based and preview runtimes are rejected); the default is `python3.14`.
- **Lambda Insights:** `lambda_insights.layer_arn` is the `LambdaInsightsExtension` layer version for the function's
  Region and architecture (AWS publishes different versions and accounts per Region).
- **No public access (Lambda.1):** triggers need `source_arn` or `source_account`; function URLs use IAM auth only.
- **Tracing (Lambda.7):** X-Ray `Active` by default.
- **Least privilege:** the role writes only to its own log group; triggers, secrets and destinations add only the
  actions they need. `kms:Decrypt` for queues and secrets is limited with `kms:ViaService`.
- **No credentials in environment variables:** names like `PASSWORD`, `SECRET`, `TOKEN` are rejected; use
  `secret_arns`.
- **Logs:** JSON, 365 days, deletion protection, encrypted with the module key when one is set.
- **Code signing (Lambda.6):** `code_signing_config_arn`.

A key passed in `kms.key_id` must allow `logs.<region>.amazonaws.com` (encryption context
`aws:logs:arn = <log group ARN>`); the deploying principal needs `kms:CreateGrant` and `kms:Encrypt` for environment
variables.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `archive` | `>= 2.8.1` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "lambda" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/compute/lambda?ref=<version>"

  application = "core"
  environment = "prod"
  name        = "orders"
}
```

### Complete Production Example

```hcl
module "lambda" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/compute/lambda?ref=<version>"

  application  = "core"
  environment  = "prod"
  name         = "orders"
  package      = { runtime = "python3.14", s3_bucket = "core-prod-artifacts", s3_key = "orders/1.4.0.zip" }
  architecture = "arm64"
  memory_size  = 512
  timeout      = 60
  kms          = { create = true }
  secret_arns  = [module.db_secret.arn]

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids

  event_sources = {
    orders = { type = "sqs", arn = module.orders_queue.arn, batch_size = 10, maximum_concurrency = 20 }
  }
  allowed_triggers = {
    nightly = { principal = "events.amazonaws.com", source_arn = module.events.rule_arns["nightly"] }
  }
  iam_role = {
    policy_statements = [{ sid = "ReadOrders", actions = ["dynamodb:GetItem", "dynamodb:Query"], resources = [module.orders_table.arn] }]
  }
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | **Required** | Yes |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `name` | Function name. | `string` | **Required** | Yes |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `description` | Function description. | `string` | `null` | No |
| `package` | Code: Zip (runtime, handler, s3_bucket/s3_key or filename; none deploys a placeholder) or Image (image_uri). | `object({...})` | `{}` | No |
| `architecture` | x86_64 or arm64. | `string` | `"x86_64"` | No |
| `memory_size` | Memory in MB (128-10240). | `number` | `128` | No |
| `timeout` | Timeout in seconds (1-900). | `number` | `30` | No |
| `ephemeral_storage_size` | /tmp size in MB (512-10240). | `number` | `512` | No |
| `concurrency` | Reserved concurrency (null: unreserved) and provisioned concurrency on the alias (0: none). | `object({...})` | `{}` | No |
| `alias_name` | Alias that triggers, URLs and provisioned concurrency use. | `string` | `"live"` | No |
| `environment_variables` | Environment variables. No credentials: use secret_arns. | `map(string)` | `{}` | No |
| `secret_arns` | Secrets Manager secrets the function may read. | `list(string)` | `[]` | No |
| `kms` | Encryption: {} AWS managed key, create = true module key, key_id your key (ARN or ID). | `object({...})` | `{}` | No |
| `iam_role` | Execution role: extend it or bring your own. | `object({...})` | `{}` | No |
| `cloudwatch_logs` | CloudWatch log group and log levels. | `object({...})` | `{}` | No |
| `tracing` | X-Ray tracing mode: Active or PassThrough. | `string` | `"Active"` | No |
| `lambda_insights` | Lambda Insights extension: layer ARN for this Region and architecture. | `object({...})` | `{}` | No |
| `layers` | Layer ARNs. | `list(string)` | `[]` | No |
| `vpc_id` | VPC ID; with subnet_ids the function runs in the VPC. | `string` | `null` | No |
| `subnet_ids` | Private subnet IDs. Empty: no VPC. | `list(string)` | `[]` | No |
| `security_group` | Security group in the VPC: egress and extra groups. | `object({...})` | `{}` | No |
| `event_sources` | Event source mappings by key: SQS, Kinesis or DynamoDB stream ARNs. | `map(object({...}))` | `{}` | No |
| `allowed_triggers` | Services allowed to invoke the alias, by key: principal and source ARN or account. | `map(object({...}))` | `{}` | No |
| `function_url` | Function URL on the alias; IAM auth only. | `object({...})` | `{}` | No |
| `async_invoke` | Asynchronous invocation: retries, max event age and destinations. | `object({...})` | `{}` | No |
| `dead_letter_target_arn` | SQS queue or SNS topic for failed async events. | `string` | `null` | No |
| `code_signing_config_arn` | Code signing config ARN (Lambda.6). | `string` | `null` | No |
| `runtime_update_mode` | Runtime updates: Auto, FunctionUpdate or Manual. | `string` | `"Auto"` | No |
| `durable_execution` | Durable execution: execution timeout and retention in seconds. | `object({...})` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `arn` | Function ARN. | No |
| `name` | Function name. | No |
| `invoke_arn` | Alias invoke ARN for API Gateway. | No |
| `alias_arn` | Alias ARN for triggers. | No |
| `alias_name` | Alias name. | No |
| `role_arn` | Execution role ARN. | No |
| `role_name` | Execution role name; null for a role brought by the caller. | No |
| `log_group_name` | Log group name. | No |
| `log_group_arn` | Log group ARN. | No |
| `security_group_id` | Function security group ID; null outside a VPC. | No |
| `kms_key_arn` | Key ARN in use; null for the AWS managed key. | No |
| `function_url` | Function URL; null when disabled. | No |
