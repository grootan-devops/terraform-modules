# AWS Step Functions Module

The `step-functions` module manages AWS Step Functions state machines with Customer Managed KMS Key encryption for execution data, CloudWatch execution logs, and automated least-privilege IAM execution roles.

### Architecture & Managed Resources
- `aws_sfn_state_machine.this`: Core state machine definition.
- `aws_cloudwatch_log_group.this`: KMS-encrypted execution log group.
- `aws_iam_role.this`: IAM execution role with CloudWatch and KMS permissions.

### Security & Compliance Guardrails
- **Mandatory KMS CMK**: Execution history encrypted via Customer Managed KMS Key (`kms_key_id = var.kms_key_arn`).
- **Encrypted Logging**: CloudWatch log group requires `kms_key_arn` and customizable retention.

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
module "state_machine" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/integration/step-functions?ref=1.0.0"

  application = "core"
  environment = "prod"
  name        = "order-pipeline"
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"

  definition = jsonencode({
    Comment = "Order processing state machine"
    StartAt = "Validate"
    States = {
      Validate = {
        Type = "Pass"
        End  = true
      }
    }
  })
}
```

### Complete Production Example
```hcl
module "state_machine" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/integration/step-functions?ref=1.0.0"

  application = "fulfillment"
  environment = "prod"
  name        = "order-workflow"
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"

  definition = jsonencode({
    Comment = "Production order fulfillment pipeline"
    StartAt = "ProcessPayment"
    States = {
      ProcessPayment = {
        Type     = "Task"
        Resource = "arn:aws:lambda:us-west-2:123456789012:function:process-payment"
        End      = true
      }
    }
  })

  cloudwatch_logs = {
    retention_in_days           = 90
    level                       = "ALL"
    include_execution_data      = true
    deletion_protection_enabled = true
    kms_key_arn                 = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
  }

  tags = {
    WorkflowTier = "OrderOrchestration"
  }
}
```

---

## Inputs Specification

| Name | Description | Type | Default | Required |
|---|---|---|---|:---:|
| `application` | The name of the application. | `string` | **Required** | Yes |
| `environment` | Deployment environment name (e.g. dev, staging, prod). | `string` | **Required** | Yes |
| `name` | Name suffix for the state machine (e.g. document-pipeline). | `string` | **Required** | Yes |
| `definition` | Amazon States Language definition (JSON string). | `string` | **Required** | Yes |
| `type` | State machine type: STANDARD or EXPRESS. | `string` | `"STANDARD"` | No |
| `lambda_function_arns` | Lambda function ARNs the state machine may invoke (lambda task targets). | `list(string)` | `[]` | No |
| `tracing_enabled` | Enable AWS X-Ray tracing for the state machine. | `bool` | `true` | No |
| `cloudwatch_logs` | CloudWatch logging configuration for the state machine. | `object({...})` | **Required** | Yes |
| `tags` | Common tags to apply to all resources. | `map(string)` | `{}` | No |
| `kms_key_arn` | KMS Key ARN used for encrypting State Machine execution history and CloudWatch logs. Strictly required. | `string` | **Required** | Yes |


---

## Outputs Specification

| Name | Description | Sensitive |
|---|---|:---:|
| `state_machine_arn` | ARN of the created state machine. | No |
| `state_machine_name` | Name of the created state machine. | No |
| `role_arn` | ARN of the state machine execution role. | No |

