# AWS ECS Fargate Module

Scope: `workload`

An ECS cluster with Fargate services: one task definition, service, log group and task role per service, a shared
execution role, a task security group, optional Cloud Map discovery or Service Connect, target tracking autoscaling
and ECS Exec. Load balancers, target groups and repositories are other modules; pass their IDs and ARNs in.

## Architecture & Managed Resources

- `aws_ecs_cluster.this`: `<application>-<environment>[-<name>]`, Container Insights `enhanced`; ECS Exec and Fargate
  ephemeral storage use the module key when one is set.
- `aws_ecs_task_definition.this`, `aws_ecs_service.this`: one per `services` key. Services ignore later
  `task_definition` and `desired_count` changes: CI deploys new revisions and autoscaling owns the count.
- `module.execution_role` ([`security/iam-role`](../../security/iam-role)): shared; pulls images, writes logs,
  resolves secrets. `module.task_role`: one per service, `<base>-<service>-task-<region>`.
- `module.log_group` ([`observability/log-group`](../../observability/log-group)): `/ecs/<cluster>/<service>`;
  `module.exec_log_group`: `/aws/ecs/exec/<cluster>`, only with ECS Exec.
- `module.security_group` ([`network/security-group`](../../network/security-group)): service ports from the given
  sources, plus self-referencing rules for the ports of discoverable services.
- `aws_service_discovery_private_dns_namespace.this` (`<base>.local`), `aws_service_discovery_service.this`: only for
  services with `service_discovery` or `service_connect`; Cloud Map services only for `service_discovery`.
- `aws_appautoscaling_target.this`, `aws_appautoscaling_policy.cpu` / `.memory`: per service, when enabled.
- `module.encryption` ([`core/encryption`](../../core/encryption)): AWS managed key, module key or your key.

## Security & Compliance Guardrails

- **Containers (ECS.4, ECS.5, ECS.20):** `readonly_root_filesystem` is a required choice (per-service override,
  `writable_paths` for scratch volumes); `user` rejects root and UID 0; Fargate rejects privileged containers.
- **No credentials in environment variables (ECS.8):** names like `PASSWORD`, `SECRET`, `TOKEN` are rejected; pass
  Secrets Manager ARNs or SSM parameter names/ARNs in `secrets`.
- **Network (ECS.2, ECS.17):** private subnets, no public IP, `awsvpc`. Ingress only on the service container ports
  from `ingress_security_group_ids`, `ingress_cidr_blocks` and `ingress_prefix_list_ids`; `0.0.0.0/0` is rejected.
  Egress defaults to `0.0.0.0/0` so tasks reach ECR, Secrets Manager and CloudWatch Logs without VPC endpoints;
  narrow it where endpoints exist (registered Trivy suppression `AVD-AWS-0104`).
- **Platform (ECS.10) and logs (ECS.9, ECS.12):** `LATEST` Fargate platform, `awslogs` on every container, logs kept
  365 days with deletion protection, Container Insights `enhanced`.
- **Least privilege:** the execution role writes only to the service log groups, pulls only from the ECR repositories
  in the images, reads only the referenced secrets (`secretsmanager:GetSecretValue`) and parameters
  (`ssm:GetParameters`), and decrypts only through Secrets Manager and SSM. Task roles have no permissions until ECS
  Exec (`ssmmessages`, exec log group, session key), tracing (X-Ray) or your statements add them, and trust ECS tasks
  in this account only.
- **Tags (ECS.13-15):** cluster, services and task definitions carry the governance tags; services propagate them to
  tasks.

A key passed in `kms.key_id` must allow `logs.<region>.amazonaws.com` (encryption context `aws:logs:arn`), and
`fargate.amazonaws.com` `kms:GenerateDataKeyWithoutPlaintext` and `kms:CreateGrant` with the
`aws:ecs:clusterAccount`/`aws:ecs:clusterName` encryption context. Operators running `execute-command` need
`kms:GenerateDataKey` on it.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "ecs" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/compute/ecs?ref=<version>"

  application              = "core"
  environment              = "prod"
  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnet_ids
  readonly_root_filesystem = true

  services = {
    api = { image = "${module.ecr.repository_url}:1.0.0", container_port = 8080, user = "1000:1000" }
  }
}
```

### Complete Production Example

```hcl
module "ecs" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/compute/ecs?ref=<version>"

  application              = "core"
  environment              = "prod"
  name                     = "web"
  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnet_ids
  readonly_root_filesystem = true
  kms                      = { create = true }
  tracing                  = { enabled = true }

  security_group = {
    ingress_security_group_ids = [module.alb.security_group_id]
    egress_cidr_blocks         = [module.vpc.cidr_block]
  }

  services = {
    api = {
      image             = "${module.ecr.repository_url}:1.0.0"
      container_port    = 8080
      cpu               = 512
      memory            = 1024
      desired_count     = 2
      user              = "1000:1000"
      writable_paths    = ["/tmp"]
      target_group_arns = [module.alb.target_group_arns["api"]]
      secrets           = { DATABASE_URL = module.db_secret.arn }
      service_connect   = { enabled = true }
      autoscaling       = { enabled = true, max_capacity = 10 }
      task_role = {
        policy_statements = [{ sid = "ReadOrders", actions = ["dynamodb:GetItem"], resources = [module.orders_table.arn] }]
      }
    }
    worker = {
      image           = "${module.ecr.repository_url}:1.0.0"
      container_port  = 9090
      user            = "1000:1000"
      execute_command = true
    }
  }
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | **Required** | Yes |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `name` | Cluster name. | `string` | `null` | No |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `vpc_id` | VPC ID. | `string` | **Required** | Yes |
| `subnet_ids` | Private subnet IDs for the tasks. | `list(string)` | **Required** | Yes |
| `security_group` | Task security group: ingress sources on the service ports, egress and extra groups. | `object({...})` | `{}` | No |
| `kms` | Encryption: {} AWS managed key, create = true module key, key_id your key (ARN or ID). | `object({...})` | `{}` | No |
| `iam_role` | Task roles: extend every service role or bring one shared role. | `object({...})` | `{}` | No |
| `cloudwatch_logs` | Service and ECS Exec log groups. | `object({...})` | `{}` | No |
| `container_insights` | Container Insights: enhanced, enabled or disabled. | `string` | `"enhanced"` | No |
| `tracing` | X-Ray permissions on the task roles. | `object({...})` | `{}` | No |
| `service_discovery_namespace` | Private DNS namespace name. Null: `<application>-<environment>.local.` | `string` | `null` | No |
| `readonly_root_filesystem` | Read-only root filesystem for containers. | `bool` | **Required** | Yes |
| `services` | Fargate services by key. | `map(object({...}))` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `arn` | Cluster ARN. | No |
| `name` | Cluster name (ClusterName dimension). | No |
| `service_names` | Service names by key (ServiceName dimension). | No |
| `service_arns` | Service ARNs by key. | No |
| `task_definition_arns` | Task definition ARNs by key. | No |
| `execution_role_arn` | Execution role ARN; null without services. | No |
| `task_role_arns` | Task role ARNs by service key. | No |
| `task_role_names` | Module task role names by service key. | No |
| `security_group_id` | Task security group ID; null without one. | No |
| `log_group_names` | Service log group names by key. | No |
| `log_group_arns` | Service log group ARNs by key. | No |
| `exec_log_group_name` | ECS Exec log group name; null without ECS Exec. | No |
| `service_discovery_namespace_arn` | Cloud Map namespace ARN; null without discovery. | No |
| `kms_key_arn` | Key ARN in use; null for the AWS managed key. | No |
