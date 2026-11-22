mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "eu-west-1"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/core-prod-api-task-eu-west-1"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-west-1:123456789012:log-group:/ecs/core-prod/api"
    }
  }

  mock_resource "aws_security_group" {
    defaults = {
      id = "sg-0bbbbbbbbbbbbbbbb"
    }
  }

  mock_resource "aws_ecs_cluster" {
    defaults = {
      arn = "arn:aws:ecs:eu-west-1:123456789012:cluster/core-prod"
    }
  }

  mock_resource "aws_ecs_task_definition" {
    defaults = {
      arn = "arn:aws:ecs:eu-west-1:123456789012:task-definition/core-prod-api:1"
    }
  }

  mock_resource "aws_ecs_service" {
    defaults = {
      arn = "arn:aws:ecs:eu-west-1:123456789012:service/core-prod/api"
    }
  }

  mock_resource "aws_service_discovery_private_dns_namespace" {
    defaults = {
      id  = "ns-0123456789abcdef"
      arn = "arn:aws:servicediscovery:eu-west-1:123456789012:namespace/ns-0123456789abcdef"
    }
  }

  mock_resource "aws_service_discovery_service" {
    defaults = {
      arn = "arn:aws:servicediscovery:eu-west-1:123456789012:service/srv-0123456789abcdef"
    }
  }
}

variables {
  application              = "core"
  environment              = "prod"
  tags                     = { Team = "payments" }
  vpc_id                   = "vpc-0a1b2c3d4e5f67890"
  subnet_ids               = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  readonly_root_filesystem = true
  services = {
    api = {
      image          = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/core-prod-api:1.0.0"
      container_port = 8080
      user           = "1000:1000"
    }
  }
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = aws_ecs_cluster.this.name == "core-prod" && [for s in aws_ecs_cluster.this.setting : s.value if s.name == "containerInsights"] == ["enhanced"] && length(aws_ecs_cluster.this.configuration) == 0
    error_message = "Cluster <application>-<environment> with enhanced Container Insights (ECS.12)."
  }

  assert {
    condition     = aws_ecs_cluster.this.tags["Name"] == "core-prod" && aws_ecs_cluster.this.tags["Team"] == "payments" && aws_ecs_cluster.this.tags["ManagedBy"] == "Terraform" && aws_ecs_service.this["api"].tags["ManagedBy"] == "Terraform" && aws_ecs_task_definition.this["api"].tags["Application"] == "core"
    error_message = "Cluster, services and task definitions carry governance tags (ECS.13-15)."
  }

  assert {
    condition     = aws_ecs_service.this["api"].launch_type == "FARGATE" && aws_ecs_service.this["api"].platform_version == "LATEST" && !aws_ecs_service.this["api"].network_configuration[0].assign_public_ip && aws_ecs_service.this["api"].propagate_tags == "SERVICE"
    error_message = "Services run on the latest Fargate platform without public IPs (ECS.2, ECS.10)."
  }

  assert {
    condition     = aws_ecs_service.this["api"].deployment_circuit_breaker[0].enable && aws_ecs_service.this["api"].deployment_circuit_breaker[0].rollback && !aws_ecs_service.this["api"].enable_execute_command
    error_message = "Circuit breaker with rollback on, ECS Exec off."
  }

  assert {
    condition     = aws_ecs_task_definition.this["api"].family == "core-prod-api" && aws_ecs_task_definition.this["api"].network_mode == "awsvpc" && aws_ecs_task_definition.this["api"].requires_compatibilities == toset(["FARGATE"]) && aws_ecs_task_definition.this["api"].runtime_platform[0].cpu_architecture == "X86_64"
    error_message = "Task definitions are Fargate awsvpc (ECS.17)."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this["api"].container_definitions)[0].readonlyRootFilesystem && jsondecode(aws_ecs_task_definition.this["api"].container_definitions)[0].user == "1000:1000" && !can(jsondecode(aws_ecs_task_definition.this["api"].container_definitions)[0].privileged)
    error_message = "Containers run read-only and non-root (ECS.4, ECS.5, ECS.20)."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this["api"].container_definitions)[0].logConfiguration == { logDriver = "awslogs", options = { "awslogs-group" = "/ecs/core-prod/api", "awslogs-region" = "eu-west-1", "awslogs-stream-prefix" = "ecs" } }
    error_message = "Every container logs to its service log group (ECS.9)."
  }

  assert {
    condition     = module.log_group["api"].retention_in_days == 365 && module.log_group["api"].kms_key_arn == null && output.kms_key_arn == null
    error_message = "Logs keep 365 days with service encryption by default."
  }

  assert {
    condition     = length(module.exec_log_group) + length(aws_service_discovery_private_dns_namespace.this) + length(aws_service_discovery_service.this) + length(aws_appautoscaling_target.this) + length([for k in keys(module.security_group[0].ingress_rule_ids) : k if startswith(k, "self-")]) == 0
    error_message = "No ECS Exec, discovery, autoscaling or internal rules by default."
  }
}

run "named_cluster" {
  command = plan

  variables {
    name = "web"
  }

  assert {
    condition     = aws_ecs_cluster.this.name == "core-prod-web" && aws_ecs_task_definition.this["api"].family == "core-prod-web-api" && module.log_group["api"].name == "/ecs/core-prod-web/api"
    error_message = "name is appended to every name."
  }
}

run "security_group_wiring" {
  command = apply

  variables {
    security_group = {
      ingress_security_group_ids    = ["sg-0aaaaaaaaaaaaaaaa"]
      ingress_cidr_blocks           = ["10.0.0.0/16"]
      egress_cidr_blocks            = ["10.0.0.0/8"]
      egress_prefix_list_ids        = ["pl-0123456789abcdef0"]
      additional_security_group_ids = ["sg-0ccccccccccccccccc"]
    }
    services = {
      api    = { image = "nginx:1.27", container_port = 8080 }
      worker = { image = "nginx:1.27", container_port = 9090 }
    }
  }

  assert {
    condition     = keys(module.security_group[0].ingress_rule_ids) == ["cidr-0-8080", "cidr-0-9090", "sg-0-8080", "sg-0-9090"]
    error_message = "Ingress only from the listed sources on each service port."
  }

  assert {
    condition     = keys(module.security_group[0].egress_rule_ids) == ["cidr-0", "pl-0"]
    error_message = "Egress must follow egress_cidr_blocks and egress_prefix_list_ids."
  }

  assert {
    condition     = aws_ecs_service.this["api"].network_configuration[0].security_groups == toset(["sg-0bbbbbbbbbbbbbbbb", "sg-0ccccccccccccccccc"]) && output.security_group_id == "sg-0bbbbbbbbbbbbbbbb"
    error_message = "Services use the module group and the extra groups."
  }
}

run "execution_role" {
  command = plan

  variables {
    services = {
      api = {
        image          = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/core-prod-api:1.0.0"
        container_port = 8080
        secrets        = { DB_URL = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:core-prod-db-AbCdEf:url::", API_KEY = "arn:aws:ssm:eu-west-1:123456789012:parameter/core/prod/api-key" }
      }
      worker = { image = "nginx:1.27", container_port = 9090, secrets = { QUEUE = "core-prod-queue" } }
    }
  }

  assert {
    condition     = [for s in jsondecode(module.execution_role[0].policy_json).Statement : s.Sid] == ["WriteLogs", "GetRegistryToken", "PullImages", "ReadSecrets", "ReadParameters", "DecryptSecrets"]
    error_message = "The execution role gets logs, image pulls and secrets only."
  }

  assert {
    condition     = jsondecode(module.execution_role[0].policy_json).Statement[0].Resource == ["arn:aws:logs:eu-west-1:123456789012:log-group:/ecs/core-prod/api:*", "arn:aws:logs:eu-west-1:123456789012:log-group:/ecs/core-prod/worker:*"] && jsondecode(module.execution_role[0].policy_json).Statement[2].Resource == ["arn:aws:ecr:eu-west-1:123456789012:repository/core-prod-api"]
    error_message = "Logs and pulls are scoped to the service log groups and ECR repositories."
  }

  assert {
    condition     = jsondecode(module.execution_role[0].policy_json).Statement[3].Resource == ["arn:aws:secretsmanager:eu-west-1:123456789012:secret:core-prod-db-AbCdEf"] && jsondecode(module.execution_role[0].policy_json).Statement[4].Resource == ["arn:aws:ssm:eu-west-1:123456789012:parameter/core/prod/api-key", "arn:aws:ssm:eu-west-1:123456789012:parameter/core-prod-queue"]
    error_message = "SSM parameters need ssm:GetParameters on their ARNs."
  }

  assert {
    condition     = jsondecode(module.execution_role[0].policy_json).Statement[5].Condition.StringEquals["kms:ViaService"] == ["secretsmanager.eu-west-1.amazonaws.com", "ssm.eu-west-1.amazonaws.com"]
    error_message = "kms:Decrypt only through Secrets Manager and SSM."
  }

  assert {
    condition     = module.execution_role[0].name == "core-prod-ecs-exec-eu-west-1" && jsondecode(module.execution_role[0].trust_policy_json).Statement[0].Principal.Service == ["ecs-tasks.amazonaws.com"]
    error_message = "Execution role <base>-ecs-exec-<region>, trusted by ECS tasks."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this["api"].container_definitions)[0].secrets == [{ name = "API_KEY", valueFrom = "arn:aws:ssm:eu-west-1:123456789012:parameter/core/prod/api-key" }, { name = "DB_URL", valueFrom = "arn:aws:secretsmanager:eu-west-1:123456789012:secret:core-prod-db-AbCdEf:url::" }]
    error_message = "Secrets are passed by reference."
  }
}

run "task_roles" {
  command = plan

  assert {
    condition     = module.task_role["api"].name == "core-prod-api-task-eu-west-1" && module.task_role["api"].policy_json == null
    error_message = "Each service gets its own task role, without permissions by default."
  }

  assert {
    condition     = jsondecode(module.task_role["api"].trust_policy_json).Statement[0].Condition.StringEquals["aws:SourceAccount"] == ["123456789012"] && jsondecode(module.task_role["api"].trust_policy_json).Statement[0].Condition.ArnLike["aws:SourceArn"] == ["arn:aws:ecs:eu-west-1:123456789012:*"]
    error_message = "Only ECS tasks in this account may assume task roles."
  }
}

run "tracing_and_exec_permissions" {
  command = plan

  variables {
    tracing = { enabled = true }
    services = {
      api    = { image = "nginx:1.27", container_port = 8080, execute_command = true }
      worker = { image = "nginx:1.27", container_port = 9090 }
    }
  }

  assert {
    condition     = [for s in jsondecode(module.task_role["api"].policy_json).Statement : s.Sid] == ["ExecChannels", "ExecFindLogGroup", "ExecWriteLogs", "WriteTraces"]
    error_message = "ECS Exec and tracing add only their permissions."
  }

  assert {
    condition     = [for s in jsondecode(module.task_role["worker"].policy_json).Statement : s.Sid] == ["WriteTraces"]
    error_message = "Services without ECS Exec get tracing only."
  }

  assert {
    condition     = jsondecode(module.task_role["api"].policy_json).Statement[2].Resource == ["arn:aws:logs:eu-west-1:123456789012:log-group:/aws/ecs/exec/core-prod:*"] && module.exec_log_group[0].name == "/aws/ecs/exec/core-prod"
    error_message = "ECS Exec logs go to the exec log group."
  }
}

run "exec_with_module_key" {
  command   = apply
  state_key = "exec"

  variables {
    kms = { create = true }
    services = {
      api = { image = "nginx:1.27", container_port = 8080, execute_command = true }
    }
  }

  assert {
    condition     = aws_ecs_cluster.this.configuration[0].execute_command_configuration[0].kms_key_id == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && aws_ecs_cluster.this.configuration[0].execute_command_configuration[0].logging == "OVERRIDE" && aws_ecs_cluster.this.configuration[0].execute_command_configuration[0].log_configuration[0].cloud_watch_encryption_enabled
    error_message = "ECS Exec sessions and logs are encrypted with the module key."
  }

  assert {
    condition     = aws_ecs_cluster.this.configuration[0].managed_storage_configuration[0].fargate_ephemeral_storage_kms_key_id == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    error_message = "Fargate ephemeral storage uses the module key."
  }

  assert {
    condition     = module.log_group["api"].kms_key_arn == output.kms_key_arn && module.exec_log_group[0].kms_key_arn == output.kms_key_arn
    error_message = "Log groups use the module key."
  }

  assert {
    condition     = jsondecode(module.task_role["api"].policy_json).Statement[3].Sid == "ExecDecryptSession" && jsondecode(module.task_role["api"].policy_json).Statement[3].Resource == ["arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"]
    error_message = "The task role decrypts ECS Exec sessions with the module key only."
  }
}

run "module_key_is_planned_safely" {
  command = plan

  variables {
    kms = { create = true }
    services = {
      api = { image = "nginx:1.27", container_port = 8080, execute_command = true }
    }
  }

  assert {
    condition     = module.encryption.created && length(aws_ecs_cluster.this.configuration) == 1
    error_message = "kms.create must plan without knowing the key ARN."
  }
}

run "caller_key_id_and_log_key_override" {
  command = plan

  variables {
    kms             = { key_id = "11111111-2222-3333-4444-555555555555" }
    cloudwatch_logs = { kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/99999999-2222-3333-4444-555555555555", retention_in_days = 731 }
  }

  assert {
    condition     = aws_ecs_cluster.this.configuration[0].managed_storage_configuration[0].fargate_ephemeral_storage_kms_key_id == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    error_message = "A key ID must be used as the key ARN."
  }

  assert {
    condition     = module.log_group["api"].kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/99999999-2222-3333-4444-555555555555" && module.log_group["api"].retention_in_days == 731
    error_message = "cloudwatch_logs must override the log key and retention."
  }
}

run "discovery_and_service_connect" {
  command   = apply
  state_key = "discovery"

  variables {
    services = {
      api    = { image = "nginx:1.27", container_port = 8080, service_discovery = true }
      worker = { image = "nginx:1.27", container_port = 9090, service_connect = { enabled = true, client_alias_port = 80 } }
      batch  = { image = "nginx:1.27", container_port = 7070 }
    }
  }

  assert {
    condition     = aws_service_discovery_private_dns_namespace.this[0].name == "core-prod.local" && aws_service_discovery_private_dns_namespace.this[0].vpc == "vpc-0a1b2c3d4e5f67890"
    error_message = "The namespace defaults to <base>.local in the VPC."
  }

  assert {
    condition     = keys(aws_service_discovery_service.this) == ["api"] && length(aws_ecs_service.this["api"].service_registries) == 1 && length(aws_ecs_service.this["batch"].service_registries) == 0
    error_message = "Cloud Map services only for services that use discovery."
  }

  assert {
    condition     = aws_ecs_service.this["worker"].service_connect_configuration[0].namespace == "arn:aws:servicediscovery:eu-west-1:123456789012:namespace/ns-0123456789abcdef" && aws_ecs_service.this["worker"].service_connect_configuration[0].service[0].port_name == "worker" && aws_ecs_service.this["worker"].service_connect_configuration[0].service[0].client_alias[0].port == 80
    error_message = "Service Connect uses the module namespace and the service port name."
  }

  assert {
    condition     = [for k in keys(module.security_group[0].ingress_rule_ids) : k if startswith(k, "self-")] == ["self-8080", "self-9090"]
    error_message = "Only discoverable service ports are open between the services."
  }

  assert {
    condition     = output.service_discovery_namespace_arn == "arn:aws:servicediscovery:eu-west-1:123456789012:namespace/ns-0123456789abcdef"
    error_message = "The namespace ARN is exported."
  }
}

run "custom_namespace" {
  command = plan

  variables {
    service_discovery_namespace = "internal.example.local"
    services = {
      api = { image = "nginx:1.27", container_port = 8080, service_discovery = true }
    }
  }

  assert {
    condition     = aws_service_discovery_private_dns_namespace.this[0].name == "internal.example.local"
    error_message = "service_discovery_namespace sets the namespace name."
  }
}

run "autoscaling_and_load_balancer" {
  command = plan

  variables {
    services = {
      api = {
        image             = "nginx:1.27"
        container_port    = 8080
        desired_count     = 2
        target_group_arns = ["arn:aws:elasticloadbalancing:eu-west-1:123456789012:targetgroup/core-prod-api/0123456789abcdef"]
        autoscaling       = { enabled = true, max_capacity = 10, cpu_target = 50, memory_target = 70 }
      }
    }
  }

  assert {
    condition     = aws_appautoscaling_target.this["api"].min_capacity == 2 && aws_appautoscaling_target.this["api"].max_capacity == 10 && aws_appautoscaling_target.this["api"].resource_id == "service/core-prod/api"
    error_message = "Autoscaling starts at desired_count."
  }

  assert {
    condition     = aws_appautoscaling_policy.cpu["api"].target_tracking_scaling_policy_configuration[0].target_value == 50 && aws_appautoscaling_policy.memory["api"].target_tracking_scaling_policy_configuration[0].target_value == 70
    error_message = "CPU and memory target tracking."
  }

  assert {
    condition     = [for lb in aws_ecs_service.this["api"].load_balancer : lb.container_port] == [8080] && aws_ecs_service.this["api"].health_check_grace_period_seconds == 60
    error_message = "Target groups receive the container port."
  }
}

run "container_options" {
  command = plan

  variables {
    readonly_root_filesystem = false
    services = {
      api = {
        image                    = "nginx:1.27"
        container_port           = 8080
        cpu_architecture         = "ARM64"
        command                  = ["serve"]
        environment              = { LOG_LEVEL = "info" }
        readonly_root_filesystem = true
        writable_paths           = ["/tmp", "/var/cache"]
      }
      worker = { image = "nginx:1.27", container_port = 9090 }
    }
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this["api"].container_definitions)[0].readonlyRootFilesystem && !jsondecode(aws_ecs_task_definition.this["worker"].container_definitions)[0].readonlyRootFilesystem
    error_message = "The per-service setting overrides the module-wide one."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this["api"].container_definitions)[0].mountPoints == [{ sourceVolume = "scratch-0", containerPath = "/tmp", readOnly = false }, { sourceVolume = "scratch-1", containerPath = "/var/cache", readOnly = false }] && [for v in aws_ecs_task_definition.this["api"].volume : v.name] == ["scratch-0", "scratch-1"]
    error_message = "writable_paths mounts scratch volumes."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this["api"].container_definitions)[0].environment == [{ name = "LOG_LEVEL", value = "info" }] && jsondecode(aws_ecs_task_definition.this["api"].container_definitions)[0].command == ["serve"] && aws_ecs_task_definition.this["api"].runtime_platform[0].cpu_architecture == "ARM64"
    error_message = "Environment, command and architecture are rendered."
  }
}

run "efs_volumes" {
  command   = apply
  state_key = "efs"

  variables {
    services = {
      api = {
        image          = "nginx:1.27"
        container_port = 8080
        writable_paths = ["/tmp"]
        efs_volumes = {
          shared  = { file_system_id = "fs-0123456789abcdef0", access_point_id = "fsap-00000000000000001", container_path = "/mnt/shared" }
          reports = { file_system_id = "fs-0fedcba9876543210", root_directory = "/reports", container_path = "/mnt/reports", read_only = true }
        }
      }
      worker = { image = "nginx:1.27", container_port = 9090 }
    }
  }

  assert {
    condition     = toset([for v in aws_ecs_task_definition.this["api"].volume : v.name]) == toset(["scratch-0", "shared", "reports"]) && length(aws_ecs_task_definition.this["worker"].volume) == 0
    error_message = "efs_volumes add one volume per key beside the scratch volumes."
  }

  assert {
    condition     = one([for v in aws_ecs_task_definition.this["api"].volume : v.efs_volume_configuration[0] if v.name == "shared"]).file_system_id == "fs-0123456789abcdef0" && one([for v in aws_ecs_task_definition.this["api"].volume : v.efs_volume_configuration[0] if v.name == "shared"]).transit_encryption == "ENABLED" && one([for v in aws_ecs_task_definition.this["api"].volume : v.efs_volume_configuration[0] if v.name == "shared"]).authorization_config[0] == { access_point_id = "fsap-00000000000000001", iam = "ENABLED" } && one([for v in aws_ecs_task_definition.this["api"].volume : v.efs_volume_configuration[0] if v.name == "shared"]).root_directory == null
    error_message = "An access point mounts with TLS and IAM authorization (ECS.18)."
  }

  assert {
    condition     = one([for v in aws_ecs_task_definition.this["api"].volume : v.efs_volume_configuration[0] if v.name == "reports"]).transit_encryption == "ENABLED" && one([for v in aws_ecs_task_definition.this["api"].volume : v.efs_volume_configuration[0] if v.name == "reports"]).authorization_config[0].iam == "DISABLED" && one([for v in aws_ecs_task_definition.this["api"].volume : v.efs_volume_configuration[0] if v.name == "reports"]).authorization_config[0].access_point_id == null && one([for v in aws_ecs_task_definition.this["api"].volume : v.efs_volume_configuration[0] if v.name == "reports"]).root_directory == "/reports"
    error_message = "Without an access point the volume mounts root_directory with TLS, IAM off."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this["api"].container_definitions)[0].mountPoints == [{ sourceVolume = "scratch-0", containerPath = "/tmp", readOnly = false }, { sourceVolume = "reports", containerPath = "/mnt/reports", readOnly = true }, { sourceVolume = "shared", containerPath = "/mnt/shared", readOnly = false }]
    error_message = "Each EFS volume is mounted at container_path, read-only when asked."
  }

  assert {
    condition     = [for s in jsondecode(module.task_role["api"].policy_json).Statement : s.Sid] == ["MountEfs0", "MountEfs1"] && module.task_role["worker"].policy_json == null
    error_message = "Only services with EFS volumes get mount permissions."
  }

  assert {
    condition     = jsondecode(module.task_role["api"].policy_json).Statement[0].Action == ["elasticfilesystem:ClientMount"] && jsondecode(module.task_role["api"].policy_json).Statement[0].Resource == ["arn:aws:elasticfilesystem:eu-west-1:123456789012:file-system/fs-0fedcba9876543210"] && !can(jsondecode(module.task_role["api"].policy_json).Statement[0].Condition)
    error_message = "A read-only mount gets ClientMount only, on the file system."
  }

  assert {
    condition     = jsondecode(module.task_role["api"].policy_json).Statement[1].Action == ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"] && jsondecode(module.task_role["api"].policy_json).Statement[1].Resource == ["arn:aws:elasticfilesystem:eu-west-1:123456789012:file-system/fs-0123456789abcdef0"] && jsondecode(module.task_role["api"].policy_json).Statement[1].Condition.StringEquals["elasticfilesystem:AccessPointArn"] == "arn:aws:elasticfilesystem:eu-west-1:123456789012:access-point/fsap-00000000000000001"
    error_message = "An access point mount is scoped to that access point."
  }

  assert {
    condition     = aws_ecs_task_definition.this["api"].task_role_arn == output.task_role_arns["api"] && output.task_role_arns["api"] == "arn:aws:iam::123456789012:role/core-prod-api-task-eu-west-1"
    error_message = "The task definition uses the role that carries the mount permissions."
  }
}

run "efs_with_module_key_is_planned_safely" {
  command = plan

  variables {
    kms = { create = true }
    services = {
      api = {
        image           = "nginx:1.27"
        container_port  = 8080
        execute_command = true
        efs_volumes     = { shared = { file_system_id = "fs-0123456789abcdef0", access_point_id = "fsap-00000000000000001", container_path = "/mnt/shared" } }
      }
    }
  }

  assert {
    condition     = module.encryption.created && length(module.task_role) == 1 && length(aws_ecs_task_definition.this["api"].volume) == 1
    error_message = "EFS volumes and mount permissions must plan without knowing the key ARN."
  }
}

run "bring_your_own_task_roles" {
  command = plan

  variables {
    iam_role = { create = false, arn = "arn:aws:iam::123456789012:role/shared-task" }
    services = {
      api    = { image = "nginx:1.27", container_port = 8080 }
      worker = { image = "nginx:1.27", container_port = 9090, task_role = { arn = "arn:aws:iam::123456789012:role/worker-task" } }
    }
  }

  assert {
    condition     = length(module.task_role) == 0 && aws_ecs_task_definition.this["api"].task_role_arn == "arn:aws:iam::123456789012:role/shared-task" && aws_ecs_task_definition.this["worker"].task_role_arn == "arn:aws:iam::123456789012:role/worker-task"
    error_message = "Caller roles replace the module task roles."
  }
}

run "extend_task_roles" {
  command = plan

  variables {
    iam_role = {
      permissions_boundary_arn = "arn:aws:iam::123456789012:policy/boundary"
      policy_statements        = [{ sid = "ReadConfig", actions = ["ssm:GetParameter"], resources = ["arn:aws:ssm:eu-west-1:123456789012:parameter/core/*"] }]
    }
    services = {
      api    = { image = "nginx:1.27", container_port = 8080, task_role = { policy_statements = [{ sid = "ReadOrders", actions = ["dynamodb:GetItem"], resources = ["arn:aws:dynamodb:eu-west-1:123456789012:table/orders"] }] } }
      worker = { image = "nginx:1.27", container_port = 9090, task_role = { create = false, arn = "arn:aws:iam::123456789012:role/worker-task" } }
    }
  }

  assert {
    condition     = [for s in jsondecode(module.task_role["api"].policy_json).Statement : s.Sid] == ["ReadConfig", "ReadOrders"] && keys(module.task_role) == ["api"]
    error_message = "Module-wide statements come first, then the service's own."
  }
}

run "cluster_without_services" {
  command = plan

  variables {
    services = {}
  }

  assert {
    condition     = length(module.execution_role) + length(module.task_role) + length(module.log_group) + length(aws_ecs_service.this) == 0 && output.execution_role_arn == null
    error_message = "A cluster without services creates no roles or log groups."
  }
}

run "insights_override" {
  command = plan

  variables {
    container_insights = "disabled"
  }

  assert {
    condition     = [for s in aws_ecs_cluster.this.setting : s.value if s.name == "containerInsights"] == ["disabled"]
    error_message = "container_insights must be configurable."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Web_Cluster"
  }

  expect_failures = [var.name]
}

run "rejects_invalid_application" {
  command = plan

  variables {
    application = "Core"
  }

  expect_failures = [var.application]
}

run "rejects_invalid_environment" {
  command = plan

  variables {
    environment = "PROD"
  }

  expect_failures = [var.environment]
}

run "rejects_single_subnet" {
  command = plan

  variables {
    subnet_ids = ["subnet-0123456789abcdef0"]
  }

  expect_failures = [var.subnet_ids]
}

run "rejects_no_security_group" {
  command = plan

  variables {
    security_group = { create = false }
  }

  expect_failures = [var.security_group]
}

run "rejects_open_ingress" {
  command = plan

  variables {
    security_group = { ingress_cidr_blocks = ["0.0.0.0/0"] }
  }

  expect_failures = [var.security_group]
}

run "rejects_create_and_key_id" {
  command = plan

  variables {
    kms = { create = true, key_id = "11111111-2222-3333-4444-555555555555" }
  }

  expect_failures = [var.kms]
}

run "rejects_invalid_key_id" {
  command = plan

  variables {
    kms = { key_id = "alias/ecs" }
  }

  expect_failures = [var.kms]
}

run "rejects_role_without_arn" {
  command = plan

  variables {
    iam_role = { create = false }
  }

  expect_failures = [var.iam_role]
}

run "rejects_invalid_insights" {
  command = plan

  variables {
    container_insights = "on"
  }

  expect_failures = [var.container_insights]
}

run "rejects_invalid_service_key" {
  command = plan

  variables {
    services = { Api_Service = { image = "nginx:1.27", container_port = 8080 } }
  }

  expect_failures = [var.services]
}

run "rejects_invalid_port" {
  command = plan

  variables {
    services = { api = { image = "nginx:1.27", container_port = 0 } }
  }

  expect_failures = [var.services]
}

run "rejects_invalid_architecture" {
  command = plan

  variables {
    services = { api = { image = "nginx:1.27", container_port = 8080, cpu_architecture = "ARM32" } }
  }

  expect_failures = [var.services]
}

run "rejects_credentials_in_environment" {
  command = plan

  variables {
    services = { api = { image = "nginx:1.27", container_port = 8080, environment = { API_TOKEN = "x" } } }
  }

  expect_failures = [var.services]
}

run "rejects_root_user" {
  command = plan

  variables {
    services = { api = { image = "nginx:1.27", container_port = 8080, user = "root" } }
  }

  expect_failures = [var.services]
}

run "rejects_invalid_autoscaling" {
  command = plan

  variables {
    services = { api = { image = "nginx:1.27", container_port = 8080, desired_count = 8, autoscaling = { enabled = true, max_capacity = 4 } } }
  }

  expect_failures = [var.services]
}

run "rejects_discovery_and_connect" {
  command = plan

  variables {
    services = { api = { image = "nginx:1.27", container_port = 8080, service_discovery = true, service_connect = { enabled = true } } }
  }

  expect_failures = [var.services]
}

run "rejects_task_role_without_arn" {
  command = plan

  variables {
    services = { api = { image = "nginx:1.27", container_port = 8080, task_role = { create = false } } }
  }

  expect_failures = [var.services]
}

run "rejects_efs_volume_named_like_scratch" {
  command = plan

  variables {
    services = { api = { image = "nginx:1.27", container_port = 8080, efs_volumes = { scratch-0 = { file_system_id = "fs-0123456789abcdef0", container_path = "/mnt/data" } } } }
  }

  expect_failures = [var.services]
}

run "rejects_invalid_efs_ids_and_path" {
  command = plan

  variables {
    services = { api = { image = "nginx:1.27", container_port = 8080, efs_volumes = { data = { file_system_id = "efs-123", container_path = "mnt/data" } } } }
  }

  expect_failures = [var.services]
}

run "rejects_root_directory_with_access_point" {
  command = plan

  variables {
    services = { api = { image = "nginx:1.27", container_port = 8080, efs_volumes = { data = { file_system_id = "fs-0123456789abcdef0", access_point_id = "fsap-00000000000000001", root_directory = "/data", container_path = "/mnt/data" } } } }
  }

  expect_failures = [var.services]
}

run "alarms_by_default" {
  command = plan

  assert {
    condition     = sort(keys(output.alarm_names)) == tolist(["ecs-api-cpu", "ecs-api-memory", "ecs-api-running-tasks"])
    error_message = "Default alarms: CPU, memory and running tasks per service."
  }

  assert {
    condition     = alltrue([for n in values(output.alarm_names) : startswith(n, "core-prod-ecs-api-")]) && module.alarms[0].alarm_settings["ecs-api-running-tasks"].threshold == 0 && module.alarms[0].alarm_settings["ecs-api-cpu"].threshold == 80
    error_message = "Alarm names start with the module base name; preset thresholds apply."
  }

  assert {
    condition     = alltrue([for k, r in module.alarms[0].alarm_routes : r.topic_arn == null])
    error_message = "Without topic_arns, alarms have no actions."
  }
}

run "alarms_off" {
  command = plan

  variables {
    alarms = { enabled = false }
  }

  assert {
    condition     = length(module.alarms) == 0 && length(output.alarm_names) == 0 && length(output.alarm_arns) == 0
    error_message = "alarms.enabled = false creates no alarms."
  }
}

run "alarms_tuned_and_routed" {
  command   = apply
  state_key = "alarms"

  variables {
    services = {
      api    = { image = "nginx:1.27", container_port = 8080 }
      worker = { image = "nginx:1.27", container_port = 9090 }
    }
    alarms = {
      topic_arns = {
        critical = "arn:aws:sns:eu-west-1:123456789012:platform-prod-critical"
        warning  = "arn:aws:sns:eu-west-1:123456789012:platform-prod-warning"
        info     = "arn:aws:sns:eu-west-1:123456789012:platform-prod-info"
      }
      overrides = {
        cpu    = { threshold = 70 }
        memory = { enabled = false }
      }
    }
  }

  assert {
    condition     = sort(keys(output.alarm_arns)) == tolist(["ecs-api-cpu", "ecs-api-running-tasks", "ecs-worker-cpu", "ecs-worker-running-tasks"])
    error_message = "One alarm set per service; a disabled alarm is dropped."
  }

  assert {
    condition     = module.alarms[0].alarm_settings["ecs-worker-cpu"].threshold == 70 && module.alarms[0].alarm_settings["ecs-worker-cpu"].evaluation_periods == 5 && module.alarms[0].alarm_settings["ecs-api-running-tasks"].threshold == 0
    error_message = "Overrides change one setting; the rest keep the preset defaults."
  }

  assert {
    condition     = module.alarms[0].alarm_routes["ecs-api-running-tasks"].topic_arn == "arn:aws:sns:eu-west-1:123456789012:platform-prod-critical" && module.alarms[0].alarm_routes["ecs-api-cpu"].topic_arn == "arn:aws:sns:eu-west-1:123456789012:platform-prod-warning"
    error_message = "Each alarm notifies the topic for its severity."
  }
}

run "alarms_plan_with_unknown_arns" {
  command = plan

  variables {
    kms = { create = true }
  }

  assert {
    condition     = length(module.alarms) == 1 && length(output.alarm_names) == 3
    error_message = "Alarm keys and names must be known at plan with a module key."
  }
}

run "alarms_without_container_insights" {
  command = plan

  variables {
    container_insights = "disabled"
  }

  assert {
    condition     = sort(keys(output.alarm_names)) == tolist(["ecs-api-cpu", "ecs-api-memory"])
    error_message = "The running tasks alarm needs Container Insights."
  }
}

run "alarms_without_services" {
  command = plan

  variables {
    services = {}
  }

  assert {
    condition     = length(output.alarm_names) == 0
    error_message = "A cluster without services has no alarms."
  }
}

run "rejects_invalid_alarm_topic" {
  command = plan

  variables {
    alarms = { topic_arns = { critical = "arn:aws:sqs:eu-west-1:123456789012:core-prod-critical" } }
  }

  expect_failures = [var.alarms]
}
