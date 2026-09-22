# AWS Lambda Module

The `lambda` module manages AWS Lambda serverless functions supporting container and zip packaging, stable release aliases, CloudWatch logging with KMS encryption, and secure VPC integration.

## Architecture & Managed Resources

- `aws_lambda_function.this`: Serverless execution function.
- `aws_lambda_alias.this`: Release alias for safe traffic shifting.
- `aws_cloudwatch_log_group.this`: KMS-encrypted function execution log group.
- `aws_iam_role.this`: Execution role with least-privilege KMS Decrypt and VPC policies.

### Security & Compliance Guardrails

- **Mandatory KMS CMK**: Environment variables encrypted at rest with `kms_key_arn`.
- **Encrypted Logging**: CloudWatch logs encrypted with `kms_key_arn`.
- **Private Subnet Attachments**: Executes securely within private subnets when VPC configured.

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
module "lambda" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/compute/lambda?ref=1.0.0"

  application = "core"
  environment = "prod"
  name        = "event-handler"

  handler     = "index.handler"
  runtime     = "nodejs20.x"
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
}
```

### Complete Production Example

```hcl
module "lambda" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/compute/lambda?ref=1.0.0"

  application = "billing"
  environment = "prod"
  name        = "invoice-generator"

  handler     = "app.main.handler"
  runtime     = "python3.11"
  memory_size = 1024
  timeout     = 30
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"

  environment_variables = {
    ENVIRONMENT = "prod"
    LOG_LEVEL   = "INFO"
  }

  vpc_config = {
    subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
    security_group_ids = ["sg-0123456789abcdef0"]
  }

  cloudwatch_logs = {
    retention_in_days = 90
    kms_key_id        = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
  }

  tags = {
    FunctionTier = "AsyncProcessor"
  }
}
```

---

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | :---: |
| `name` | Name of the Lambda function | `string` | `null` | No |
| `application` | Name of the product | `string` | **Required** | Yes |
| `environment` | Deployment environment name (e.g. dev, staging, prod). | `string` | **Required** | Yes |
| `durable_config` | Configuration for durable execution (if applicable in this provider). | `object({...})` | `null` | No |
| `architectures` | Instruction set architecture for your Lambda function. Valid values are [\ | `list(string)` | `["x86_64"]` | No |
| `package_type` | Lambda deployment package type. Valid values are Zip and Image. | `string` | `"Zip"` | No |
| `image_uri` | URI of a container image in the ECR registry when package_type is Image. | `string` | `null` | No |
| `runtime` | Identifier of the function runtime (Node.js 22.x or Python 3.12 LTS). | `string` | `null` | No |
| `handler` | Function entrypoint in your code. Defaults to the generated bootstrap handler for the selected runtime. | `string` | `null` | No |
| `bootstrap_message` | Message returned by the generated bootstrap package when filename and S3 package inputs are omitted. | `string` | `"Code not deployed"` | No |
| `memory_size` | Amount of memory in MB your Lambda Function can use at runtime. | `number` | `128` | No |
| `timeout` | Amount of time your Lambda Function has to run in seconds. | `number` | `60` | No |
| `reserved_concurrent_executions` | Amount of reserved concurrent executions for this lambda function. A value of 0 disables lambda from being triggered and -1 removes any concurrency limitations. | `number` | `-1` | No |
| `provisioned_concurrency` | Provisioned concurrency allocated to the stable Lambda alias. Null disables provisioned concurrency. | `number` | `null` | No |
| `alias_name` | Stable alias used by API Gateway and other synchronous consumers. | `string` | `"live"` | No |
| `environment_variables` | A map that defines environment variables for the Lambda function. | `map(string)` | `{}` | No |
| `tags` | A map of tags to assign to resources. | `map(string)` | `{}` | No |
| `vpc_config` | VPC configuration for the Lambda function | `object({...})` | `null` | No |
| `tracing_config_mode` | Tracing mode for X-Ray. Valid values are Active and PassThrough. | `string` | `"PassThrough"` | No |
| `kms_key_arn` | KMS Key ARN used to encrypt environment variables at rest and CloudWatch logs. Strictly required. | `string` | **Required** | Yes |
| `secret_arns` | Secrets Manager secret ARNs the function execution role is allowed to read | `list(string)` | `[]` | No |
| `source_kms_key_arn` | KMS key ARN used for Lambda snap start, filtering, etc. | `string` | `null` | No |
| `s3_bucket` | S3 bucket location containing the function's deployment package. | `string` | `null` | No |
| `s3_key` | S3 key of an object containing the function's deployment package. | `string` | `null` | No |
| `filename` | Path to the function's deployment package within the local filesystem. Overridden by s3_bucket/s3_key if provided. | `string` | `null` | No |
| `dead_letter_config_target_arn` | ARN of an SNS topic or SQS queue to notify when an invocation fails. | `string` | `null` | No |
| `sqs_event_sources` | Map of SQS ARNs to their respective mapping configurations (e.g., batch_size, filter_criteria_pattern) | `map(object({...}))` | `{}` | No |
| `async_invoke_config` | Configuration for async invocation behavior and destinations. | `object({...})` | `null` | No |
| `cloudwatch_logs` | CloudWatch Logs configuration for the Lambda log group. | `object({...})` | `{}` | No |
| `additional_layers` | Lambda layer version ARNs to attach to the function. | `list(string)` | `[]` | No |
| `custom_iam_policies` | List of IAM policy ARNs to attach to the Lambda Execution Role. | `list(string)` | `[]` | No |
| `create_deployer_role` | Whether to create a least-privilege role for external Lambda code deployments. | `bool` | `false` | No |
| `deployer_role_name` | Optional name for the Lambda deployer role and policy. | `string` | `null` | No |
| `deployer_principal_arn_patterns` | IAM principal ARN patterns allowed to assume the Lambda deployer role. | `list(string)` | `[]` | No |
| `artifact_bucket_arn` | ARN of the S3 bucket used by external Lambda deployments. | `string` | `null` | No |
| `artifact_prefix` | S3 object prefix used by external Lambda deployments. Defaults to the Lambda service name. | `string` | `null` | No |
| `runtime_management_config` | Runtime management configuration for the Lambda function. Valid values are Auto and FunctionUpdate. | `string` | `"Auto"` | No |
| `enable_application_signals` | Enable CloudWatch Application Signals. | `bool` | `false` | No |
| `enable_lambda_insights` | Enable CloudWatch Lambda Insights. | `bool` | `false` | No |
| `bootstrap_status_code` | HTTP status code returned by the bootstrap placeholder handler before actual application code is deployed. | `number` | `200` | No |

---

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | :---: |
| `function_arn` | The Amazon Resource Name (ARN) identifying your Lambda Function. | No |
| `alias_arn` | The ARN of the stable Lambda release alias. | No |
| `function_name` | The unique name of the Lambda Function. | No |
| `role_arn` | The ARN of the IAM role attached to the Lambda Function. | No |
| `role_name` | The name of the IAM role attached to the Lambda Function. | No |
