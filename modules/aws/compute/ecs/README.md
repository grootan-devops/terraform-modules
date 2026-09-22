# AWS ECS Fargate Module

The `ecs` module provisions Amazon Elastic Container Service (ECS) clusters with Fargate launch types, multi-service task definitions, Cloud Map service discovery, and KMS-encrypted CloudWatch log groups.

## Architecture & Managed Resources

- `aws_ecs_cluster.this`: Fargate cluster.
- `aws_ecs_task_definition.this`: Task definitions.
- `aws_ecs_service.this`: ECS services.
- `aws_cloudwatch_log_group.this`: KMS-encrypted per-service log groups.
- `aws_service_discovery_private_dns_namespace.this`: Cloud Map internal DNS namespace.

### Security & Compliance Guardrails

- **Mandatory KMS Logging**: CloudWatch logs encrypted with `kms_key_arn`.
- **Encrypted Secrets Resolution**: Automatically generates IAM execution roles with `kms:Decrypt` permissions.

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
module "ecs" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/compute/ecs?ref=1.0.0"

  application = "core"
  environment = "prod"
  name        = "services"

  vpc_id      = "vpc-0a1b2c3d4e5f67890"
  subnet_ids  = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"

  services = {
    api = {
      image  = "123456789012.dkr.ecr.us-west-2.amazonaws.com/api:v1.0.0"
      port   = 8000
      cpu    = 512
      memory = 1024
    }
  }
}
```

### Complete Production Example

```hcl
module "ecs" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/compute/ecs?ref=1.0.0"

  application = "ecommerce"
  environment = "prod"
  name        = "microservices"

  vpc_id      = "vpc-0a1b2c3d4e5f67890"
  subnet_ids  = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/bc4465aa-1234-5678-abcd-0123456789ab"

  service_discovery_namespace_override = "internal.company.local"

  services = {
    checkout = {
      image         = "123456789012.dkr.ecr.us-west-2.amazonaws.com/checkout:v2.1.0"
      port          = 8080
      cpu           = 1024
      memory        = 2048
      desired_count = 3
      environment = {
        ENVIRONMENT = "production"
        LOG_LEVEL   = "info"
      }
    },
    inventory = {
      image         = "123456789012.dkr.ecr.us-west-2.amazonaws.com/inventory:v1.5.0"
      port          = 8081
      cpu           = 512
      memory        = 1024
      desired_count = 2
    }
  }

  tags = {
    Tier = "AppContainerMesh"
  }
}
```

---

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | :---: |
| `name` | Name prefix for the ECS Cluster. If not provided, will be derived from application and environment. | `string` | `null` | No |
| `application` | Logical application or product name used for resource naming and tagging | `string` | `""` | No |
| `environment` | Deployment environment name (e.g. dev, staging, prod). | `string` | **Required** | Yes |
| `tags` | Additional tags to apply to all resources | `map(string)` | `{}` | No |
| `vpc_id` | VPC ID where services are deployed | `string` | **Required** | Yes |
| `subnet_ids` | List of subnet IDs for ECS services tasks | `list(string)` | **Required** | Yes |
| `security_group_ids` | List of security group IDs to assign to ECS services. If empty, a default service security group with intra-mesh and ALB access rules will be created. | `list(string)` | `[]` | No |
| `alb_security_group_id` | The security group ID of the ALB (required if default service security group is created) | `string` | `null` | No |
| `service_discovery_namespace` | The name of the private DNS namespace for service discovery. If null, a default namespace using the name will be auto-generated. If empty string '', service discovery is disabled. | `string` | `null` | No |
| `image_tag` | Default container image tag to reference if not specified in service | `string` | `"latest"` | No |
| `task_execution_role_arn` | The ARN of the task execution role. If not provided, a default role will be created. | `string` | `null` | No |
| `task_role_arn` | The ARN of the task role. If not provided, a default role will be created. | `string` | `null` | No |
| `enable_autoscaling` | Whether to enable CPU target-tracking autoscaling for services | `bool` | `false` | No |
| `autoscaling_max_capacity` | Max task count per service when autoscaling is enabled | `number` | `6` | No |
| `autoscaling_cpu_target` | Target average CPU utilization (%) for autoscaling | `number` | `60` | No |
| `create_alb_ingress_rule` | Whether to create the ingress rule from the ALB to the ECS services | `bool` | `true` | No |
| `secret_arns` | Secrets Manager secret ARNs the task execution role is allowed to read | `list(string)` | `[]` | No |
| `kms_key_arn` | KMS Key ARN used to decrypt secrets and encrypt CloudWatch log groups. Strictly required. | `string` | **Required** | Yes |
| `services` | A map of services to deploy in the ECS cluster | `map(object({...}))` | **Required** | Yes |

---

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | :---: |
| `cluster_id` | ID of the ECS cluster. | No |
| `cluster_arn` | ARN that identifies the cluster. | No |
| `service_names` | Map of service names. | No |
| `service_ids` | Map of service IDs. | No |
| `task_definition_arns` | Map of Task Definition ARNs. | No |
| `task_execution_role_arn` | ARN of the task execution role. | No |
| `service_task_role_arns` | Map of service task role ARNs. | No |
| `security_group_id` | Security group ID attached to the ECS service. | No |
