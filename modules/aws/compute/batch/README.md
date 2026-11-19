# AWS Batch Module

Scope: `workload`

AWS Batch compute environments (Fargate, Fargate Spot, EC2, Spot), job queues with an optional fair-share scheduling
policy, and container job definitions with their job, execution and instance roles, log group and security group.
Schedules and event rules are not here: [`integration/eventbridge`](../../integration/eventbridge) targets the job
queues this module outputs.

## Architecture & Managed Resources

- `aws_batch_compute_environment.this`: managed, `<base>-<key>-<suffix>` (create before destroy), in `subnet_ids`
  with the module security group.
- `aws_launch_template.this`: EC2 and Spot environments only: IMDSv2, encrypted gp3 root volume, tagged instances
  and volumes, ECS-optimized Amazon Linux 2023.
- `aws_batch_job_queue.this`, `aws_batch_scheduling_policy.this` (when `scheduling_policy.enabled`).
- `aws_batch_job_definition.this`: container jobs with the module roles, log configuration and secure defaults.
- `module.job_role`, `module.execution_role` ([`security/iam-role`](../../security/iam-role)): only with job
  definitions. `module.instance_role` (with instance profile): only with EC2 or Spot environments.
- `module.log_group` ([`observability/log-group`](../../observability/log-group)): `/aws/batch/<base>`, only with job
  definitions.
- `module.security_group` ([`network/security-group`](../../network/security-group)): only with compute environments;
  egress only.
- `module.encryption` ([`core/encryption`](../../core/encryption)): log group and EC2 root volumes.

## Security & Compliance Guardrails

- **Tags (Batch.1-4):** queues, scheduling policy, compute environments and EC2 compute resources carry the governance
  tags; job definitions propagate tags to their tasks.
- **Containers:** `readonly_root_filesystem` is required (per-job override); `writable_paths` mounts scratch volumes.
  `user` rejects root and UID 0; EC2 jobs are `privileged = false`; Fargate jobs get no public IP and run on `LATEST`.
- **No credentials in environment variables:** names like `PASSWORD`, `SECRET`, `TOKEN` are rejected; pass
  Secrets Manager ARNs or SSM parameter names/ARNs in `secrets`.
- **Least privilege:** the execution role writes only to the module log group, pulls only from the ECR repositories
  in the job images, reads only the referenced secrets and parameters, and decrypts only through Secrets Manager or
  SSM. The job role has no permissions until you add them and trusts ECS tasks in this account only.
- **Instances:** IMDSv2 with hop limit 1, so containers cannot reach the instance role; root volumes encrypted with the
  module key or the AWS managed key.
- **Logs:** 365 days, deletion protection, encrypted with the module key when one is set.
- **Network:** egress defaults to `0.0.0.0/0` because jobs pull images and call AWS APIs; narrow it to VPC endpoint
  and proxy ranges where they exist. No ingress.

A key passed in `kms.key_id` must allow `logs.<region>.amazonaws.com` (encryption context
`aws:logs:arn = <log group ARN>`) and, for EC2 environments, EBS use through `ec2.<region>.amazonaws.com` by the
account's principals (the Auto Scaling service-linked role launches the instances).

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "batch" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/compute/batch?ref=<version>"

  application              = "core"
  environment              = "prod"
  name                     = "etl"
  readonly_root_filesystem = true
  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnet_ids

  compute_environments = { fargate = { max_vcpus = 16 } }
  job_queues           = { default = { priority = 1, compute_environments = ["fargate"] } }
  job_definitions      = { nightly = { image = "${module.ecr.repository_url}:1.0.0" } }
}
```

### Complete Production Example

```hcl
module "batch" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/compute/batch?ref=<version>"

  application              = "core"
  environment              = "prod"
  name                     = "etl"
  readonly_root_filesystem = true
  kms                      = { create = true }
  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnet_ids
  security_group           = { egress_cidr_blocks = [module.vpc.cidr_block] }

  compute_environments = {
    fargate = { max_vcpus = 16 }
    spot    = { type = "SPOT", max_vcpus = 256, instance_types = ["c7i", "m7i"] }
  }
  scheduling_policy = { enabled = true, share_decay_seconds = 3600 }
  job_queues = {
    default = { priority = 10, compute_environments = ["fargate"] }
    bulk    = { priority = 1, compute_environments = ["spot"] }
  }
  job_definitions = {
    nightly = {
      image           = "${module.ecr.repository_url}:1.0.0"
      vcpu            = 2
      memory          = 4096
      user            = "1000:1000"
      writable_paths  = ["/tmp"]
      secrets         = { DB_URL = module.db_secret.arn }
      timeout_seconds = 3600
      attempts        = 3
    }
  }
  iam_role = {
    policy_statements = [{ sid = "ReadInput", actions = ["s3:GetObject"], resources = ["${module.input_bucket.arn}/*"] }]
  }
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | **Required** | Yes |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `name` | Instance name. | `string` | `null` | No |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `vpc_id` | VPC ID for the compute environments. | `string` | `null` | No |
| `subnet_ids` | Private subnet IDs for the compute environments. | `list(string)` | `[]` | No |
| `security_group` | Compute environment security group: egress and extra groups. | `object({...})` | `{}` | No |
| `kms` | Encryption: {} AWS managed key, create = true module key, key_id your key (ARN or ID). | `object({...})` | `{}` | No |
| `compute_environments` | Managed compute environments by key: FARGATE, FARGATE_SPOT, EC2 or SPOT. | `map(object({...}))` | `{}` | No |
| `job_queues` | Job queues by key: priority and compute environment keys or ARNs in order. | `map(object({...}))` | `{}` | No |
| `scheduling_policy` | Fair-share scheduling policy for every module queue. | `object({...})` | `{}` | No |
| `readonly_root_filesystem` | Read-only root filesystem for job containers. | `bool` | **Required** | Yes |
| `job_definitions` | Container job definitions by key. | `map(object({...}))` | `{}` | No |
| `iam_role` | Job role: extend it or bring your own. | `object({...})` | `{}` | No |
| `cloudwatch_logs` | CloudWatch log group for job output. | `object({...})` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `compute_environment_arns` | Compute environment ARNs by key. | No |
| `compute_environment_names` | Compute environment names by key. | No |
| `job_queue_arns` | Job queue ARNs by key. | No |
| `job_queue_names` | Job queue names by key (JobQueue dimension). | No |
| `job_definition_arns` | Job definition ARNs (latest revision) by key. | No |
| `job_definition_arn_prefixes` | Job definition ARNs without revision by key. | No |
| `scheduling_policy_arn` | Scheduling policy ARN; null when disabled. | No |
| `security_group_id` | Compute environment security group ID; null without one. | No |
| `role_arn` | Job role ARN; null without job definitions. | No |
| `role_name` | Job role name; null for a role brought by the caller. | No |
| `execution_role_arn` | Execution role ARN; null without job definitions. | No |
| `log_group_name` | Log group name; null when disabled. | No |
| `log_group_arn` | Log group ARN; null when disabled. | No |
| `kms_key_arn` | Key ARN in use; null for the AWS managed key. | No |
