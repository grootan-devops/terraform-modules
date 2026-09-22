# AWS Batch Module

The `batch` module manages AWS Batch compute environments (Fargate), job queues with fair-share scheduling, containerized job definitions, and scheduled EventBridge triggers.

## Architecture & Managed Resources

- `aws_batch_compute_environment.this`: Managed Fargate batch compute.
- `aws_batch_job_queue.this`: Priority and fair-share job queues.
- `aws_batch_job_definition.this`: Containerized task execution specs.
- `aws_cloudwatch_log_group.this`: KMS-encrypted batch execution log group.

### Security & Compliance Guardrails

- **Mandatory KMS Logging**: CloudWatch logs encrypted with `kms_key_arn`.
- **Private Subnet Placement**: Tasks run exclusively across private subnets.

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
module "batch" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/compute/batch?ref=1.0.0"

  application = "core"
  environment = "prod"
  name        = "etl"

  vpc_id      = "vpc-0a1b2c3d4e5f67890"
  subnet_ids  = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"
}
```

### Complete Production Example

```hcl
module "batch" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/compute/batch?ref=1.0.0"

  application = "analytics"
  environment = "prod"
  name        = "nightly-etl"

  vpc_id      = "vpc-0a1b2c3d4e5f67890"
  subnet_ids  = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"

  compute_environments = {
    fargate_pool = {
      type             = "MANAGED"
      state            = "ENABLED"
      compute_type     = "FARGATE"
      max_vcpus        = 128
      security_subnets = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
    }
  }

  job_queues = {
    high_priority = {
      priority             = 10
      state                = "ENABLED"
      compute_environments = ["fargate_pool"]
    }
  }

  job_definitions = {
    data_sync = {
      type       = "container"
      image      = "123456789012.dkr.ecr.us-west-2.amazonaws.com/etl-sync:v1.0"
      vcpus      = 2.0
      memory     = 4096
      fargate    = true
    }
  }

  tags = {
    Workload = "DataPipeline"
  }
}
```

---

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | :---: |
| `application` | The name of the application. | `string` | **Required** | Yes |
| `environment` | Deployment environment name (e.g. dev, staging, prod). | `string` | **Required** | Yes |
| `name` | The name suffix for AWS Batch resources. | `string` | `""` | No |
| `tags` | Common tags to apply to all resources. | `map(string)` | `{}` | No |
| `create_scheduling_policy` | Whether to create an AWS Batch scheduling policy. | `bool` | `false` | No |
| `scheduling_policy_name` | Custom name for the scheduling policy. If not provided, a rendered name will be used. | `string` | `null` | No |
| `scheduling_policy_fair_share_policy` | The fair share policy block for the scheduling policy. | `object({...})` | `null` | No |
| `compute_environments` | Map of compute environments to create. | `map(object({...}))` | `{}` | No |
| `job_queues` | Map of job queues to create. | `map(object({...}))` | `{}` | No |
| `custom_ecs_execution_policies` | List of additional IAM policy ARNs to attach to the ECS Task Execution Role. | `list(string)` | `[]` | No |
| `custom_ecs_job_role_policies` | List of IAM policy ARNs to attach to the ECS Task Job Role. | `list(string)` | `[]` | No |
| `job_definitions` | Map of job definitions to create. | `map(object({...}))` | `{}` | No |
| `custom_eventbridge_policies` | List of additional IAM policy ARNs to attach to the automatically created EventBridge execution role. | `list(string)` | `[]` | No |
| `eventbridge_rules` | Map of EventBridge rules for scheduling or triggering jobs. | `map(object({...}))` | `{}` | No |
| `eventbridge_targets` | Map of EventBridge targets pointing to the AWS Batch queues and job definitions. | `map(object({...}))` | `{}` | No |
| `cloudwatch_logs` | CloudWatch logs configuration for AWS Batch containers. | `object({...})` | `null` | No |
| `kms_key_arn` | KMS Key ARN used for encrypting AWS Batch CloudWatch logs and compute storage. Strictly required. | `string` | **Required** | Yes |

---

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | :---: |
| `job_queue_arns` | Map of Job Queue ARNs to be used with EventBridge targets. | No |
| `job_definition_arns` | Map of Job Definition ARNs to be used with EventBridge targets. | No |
| `eventbridge_role_arn` | The IAM Role ARN required by EventBridge / Scheduler to trigger these Batch jobs. | No |
