mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      name   = "us-west-2"
      region = "us-west-2"
    }
  }

  # The rendered policy is passed to IAM arguments the provider validates as JSON.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  # The provider validates ARN-typed arguments, so computed ARNs that feed
  # other resources need ARN-shaped mock values.
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/core-prod-services-mock"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-west-2:123456789012:log-group:/ecs/core-prod-services/api"
    }
  }

  mock_resource "aws_ecs_cluster" {
    defaults = {
      id  = "arn:aws:ecs:us-west-2:123456789012:cluster/core-prod-services"
      arn = "arn:aws:ecs:us-west-2:123456789012:cluster/core-prod-services"
    }
  }

  mock_resource "aws_ecs_task_definition" {
    defaults = {
      arn = "arn:aws:ecs:us-west-2:123456789012:task-definition/core-prod-services-api:1"
    }
  }

  mock_resource "aws_service_discovery_private_dns_namespace" {
    defaults = {
      id  = "ns-0123456789abcdef"
      arn = "arn:aws:servicediscovery:us-west-2:123456789012:namespace/ns-0123456789abcdef"
    }
  }

  mock_resource "aws_service_discovery_service" {
    defaults = {
      arn = "arn:aws:servicediscovery:us-west-2:123456789012:service/srv-0123456789abcdef"
    }
  }

  mock_resource "aws_security_group" {
    defaults = {
      id = "sg-0aaaaaaaaaaaaaaaa"
    }
  }
}

variables {
  application           = "core"
  environment           = "prod"
  name                  = "services"
  vpc_id                = "vpc-0a1b2c3d4e5f67890"
  subnet_ids            = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  kms_key_arn           = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
  alb_security_group_id = "sg-0123456789abcdef0"

  services = {
    api = {
      container_port = 8000
      image          = "123456789012.dkr.ecr.us-west-2.amazonaws.com/api:v1.0.0"
    }
  }
}

# ------------------------------------------------------------------------------
# Naming
# ------------------------------------------------------------------------------
run "verify_rendered_names" {
  command = plan

  assert {
    condition     = aws_ecs_cluster.this.name == "core-prod-services"
    error_message = "ECS cluster name did not match <application>-<environment>-<name>."
  }

  assert {
    condition     = aws_iam_role.task_execution[0].name == "core-prod-services-task-execution"
    error_message = "Task execution role name did not match <rendered_name>-task-execution."
  }

  assert {
    condition     = aws_iam_role.service_task["api"].name == "core-prod-services-api-task-role"
    error_message = "Service task role name did not match <rendered_name>-<service>-task-role."
  }

  assert {
    condition     = aws_iam_role_policy.service_default_task["api"].name == "core-prod-services-api-default-policy"
    error_message = "Service default policy name did not match <rendered_name>-<service>-default-policy."
  }

  assert {
    condition     = aws_security_group.service[0].name == "core-prod-services-service-sg"
    error_message = "Service security group name did not match <rendered_name>-service-sg."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this["api"].name == "/ecs/core-prod-services/api"
    error_message = "Log group name did not match /ecs/<rendered_name>/<service>."
  }

  assert {
    condition     = aws_ecs_task_definition.this["api"].family == "core-prod-services-api"
    error_message = "Task definition family did not match <rendered_name>-<service>."
  }

  assert {
    condition     = aws_ecs_service.this["api"].name == "api"
    error_message = "ECS service name must be the service key."
  }

  assert {
    condition     = aws_service_discovery_private_dns_namespace.this[0].name == "core.prod.local"
    error_message = "Default service discovery namespace must be <application>.<environment>.local."
  }

  assert {
    condition     = aws_service_discovery_service.this["api"].name == "api"
    error_message = "Service discovery service name must be the service key."
  }
}

run "verify_service_keys_with_underscores_are_hyphenated" {
  command = plan

  variables {
    services = {
      order_api = {
        container_port = 8001
        image          = "123456789012.dkr.ecr.us-west-2.amazonaws.com/order-api:v1.0.0"
      }
    }
  }

  assert {
    condition     = aws_ecs_task_definition.this["order_api"].family == "core-prod-services-order-api"
    error_message = "Underscores in service keys must become hyphens in the task definition family."
  }

  assert {
    condition     = aws_iam_role.service_task["order_api"].name == "core-prod-services-order-api-task-role"
    error_message = "Underscores in service keys must become hyphens in the task role name."
  }

  assert {
    condition     = aws_iam_role.service_task["order_api"].tags["Name"] == "core-prod-services-order-api-task-role"
    error_message = "Task role Name tag must match the hyphenated task role name."
  }
}

run "verify_name_fallback_when_null" {
  command = plan

  variables {
    name = null
  }

  assert {
    condition     = aws_ecs_cluster.this.name == "core-prod"
    error_message = "A null name must fall back to <application>-<environment>."
  }

  assert {
    condition     = aws_security_group.service[0].name == "core-prod-service-sg"
    error_message = "Security group name must use the fallback rendered name."
  }

  assert {
    condition     = aws_ecs_cluster.this.tags["Name"] == "core-prod"
    error_message = "Name tag must use the fallback rendered name."
  }
}

run "verify_name_fallback_when_empty" {
  command = plan

  variables {
    name = ""
  }

  assert {
    condition     = aws_ecs_cluster.this.name == "core-prod"
    error_message = "An empty name must fall back to <application>-<environment>."
  }

  assert {
    condition     = aws_iam_role.task_execution[0].name == "core-prod-task-execution"
    error_message = "Task execution role name must use the fallback rendered name."
  }
}

# ------------------------------------------------------------------------------
# Tags
# ------------------------------------------------------------------------------
run "verify_governance_and_caller_tags" {
  command = plan

  variables {
    tags = {
      CostCenter = "platform"
      Owner      = "platform-team"
    }
  }

  assert {
    condition = alltrue([
      for t in [
        aws_ecs_cluster.this.tags,
        aws_cloudwatch_log_group.this["api"].tags,
        aws_iam_role.task_execution[0].tags,
        aws_ecs_task_definition.this["api"].tags,
        aws_service_discovery_private_dns_namespace.this[0].tags,
        aws_service_discovery_service.this["api"].tags,
      ] :
      t["Application"] == "core" && t["Environment"] == "prod" && t["Name"] == "core-prod-services"
    ])
    error_message = "Taggable resources must carry the Application, Environment and Name governance tags."
  }

  assert {
    condition = alltrue([
      for t in [
        aws_ecs_cluster.this.tags,
        aws_cloudwatch_log_group.this["api"].tags,
        aws_iam_role.task_execution[0].tags,
        aws_iam_role.service_task["api"].tags,
        aws_security_group.service[0].tags,
        aws_ecs_task_definition.this["api"].tags,
        aws_service_discovery_private_dns_namespace.this[0].tags,
        aws_service_discovery_service.this["api"].tags,
      ] :
      t["CostCenter"] == "platform" && t["Owner"] == "platform-team"
    ])
    error_message = "Caller tags from var.tags must be preserved on every taggable resource."
  }

  assert {
    condition     = aws_security_group.service[0].tags["Name"] == "core-prod-services-service-sg" && aws_security_group.service[0].tags["Application"] == "core"
    error_message = "Security group must override Name with its own name and keep the governance tags."
  }

  assert {
    condition     = aws_iam_role.service_task["api"].tags["Name"] == "core-prod-services-api-task-role" && aws_iam_role.service_task["api"].tags["Environment"] == "prod"
    error_message = "Service task role must override Name with its own name and keep the governance tags."
  }
}

# ------------------------------------------------------------------------------
# Security and shipped defaults
# ------------------------------------------------------------------------------
run "verify_security_defaults" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.this["api"].kms_key_id == "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
    error_message = "Service log groups must be encrypted with var.kms_key_arn."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this["api"].retention_in_days == 90
    error_message = "Service log group retention must default to 90 days."
  }

  assert {
    condition     = aws_ecs_service.this["api"].network_configuration[0].assign_public_ip == false
    error_message = "ECS services must not be assigned a public IP."
  }

  assert {
    condition     = toset(aws_ecs_service.this["api"].network_configuration[0].subnets) == toset(["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"])
    error_message = "ECS services must run in the subnets given by var.subnet_ids."
  }

  assert {
    condition     = aws_ecs_service.this["api"].enable_execute_command == false
    error_message = "ECS Exec must be disabled by default."
  }

  assert {
    condition     = aws_ecs_service.this["api"].launch_type == "FARGATE"
    error_message = "ECS services must use the FARGATE launch type."
  }

  assert {
    condition     = toset(aws_ecs_task_definition.this["api"].requires_compatibilities) == toset(["FARGATE"])
    error_message = "Task definitions must require FARGATE compatibility."
  }

  assert {
    condition     = aws_ecs_task_definition.this["api"].network_mode == "awsvpc"
    error_message = "Task definitions must use awsvpc network mode."
  }

  assert {
    condition = (
      aws_ecs_task_definition.this["api"].runtime_platform[0].operating_system_family == "LINUX" &&
      aws_ecs_task_definition.this["api"].runtime_platform[0].cpu_architecture == "X86_64"
    )
    error_message = "Task definitions must target LINUX on X86_64."
  }

  assert {
    condition = jsondecode(aws_ecs_task_definition.this["api"].container_definitions)[0].logConfiguration == {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/core-prod-services/api"
        "awslogs-region"        = "us-west-2"
        "awslogs-stream-prefix" = "ecs"
      }
    }
    error_message = "Containers must ship logs to the service's KMS-encrypted log group with the awslogs driver."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.task_execution[0].policy_arn == "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
    error_message = "Task execution role must have the AWS managed AmazonECSTaskExecutionRolePolicy attached."
  }

  assert {
    condition = (
      data.aws_iam_policy_document.ecs_assume.statement[0].actions == toset(["sts:AssumeRole"]) &&
      one(data.aws_iam_policy_document.ecs_assume.statement[0].principals).identifiers == toset(["ecs-tasks.amazonaws.com"])
    )
    error_message = "ECS roles must only be assumable by ecs-tasks.amazonaws.com."
  }

  assert {
    condition     = length(aws_iam_role_policy.task_execution_secrets) == 0
    error_message = "No secrets read policy should be attached when secret_arns is empty."
  }

  assert {
    condition     = length(aws_iam_role_policy.service_custom_task) == 0
    error_message = "No custom task policy should be attached unless task_role_policy_json is set."
  }

  assert {
    condition = (
      aws_security_group_rule.alb_to_services[0].type == "ingress" &&
      aws_security_group_rule.alb_to_services[0].protocol == "tcp" &&
      aws_security_group_rule.alb_to_services[0].source_security_group_id == "sg-0123456789abcdef0"
    )
    error_message = "Service security group ingress from the load balancer must be limited to TCP from the ALB security group."
  }

  assert {
    condition = (
      aws_security_group_rule.service_mesh[0].type == "ingress" &&
      aws_security_group_rule.service_mesh[0].protocol == "tcp" &&
      aws_security_group_rule.service_mesh[0].self == true
    )
    error_message = "Intra-service ingress must be limited to TCP from the service security group itself."
  }

  assert {
    condition     = aws_security_group.service[0].vpc_id == "vpc-0a1b2c3d4e5f67890"
    error_message = "Service security group must be created in var.vpc_id."
  }
}

run "verify_shipped_defaults_and_optional_features_off" {
  command = plan

  assert {
    condition     = aws_ecs_task_definition.this["api"].cpu == "256" && aws_ecs_task_definition.this["api"].memory == "512"
    error_message = "Task definitions must default to 256 CPU units and 512 MiB memory."
  }

  assert {
    condition     = aws_ecs_service.this["api"].desired_count == 1
    error_message = "ECS services must default to a desired count of 1."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this["api"].container_definitions)[0].environment == [] && jsondecode(aws_ecs_task_definition.this["api"].container_definitions)[0].secrets == []
    error_message = "Containers must have no environment variables or secrets by default."
  }

  assert {
    condition     = length(aws_ecs_service.this["api"].deployment_circuit_breaker) == 0
    error_message = "No deployment circuit breaker should be configured by default."
  }

  assert {
    condition     = length(aws_ecs_service.this["api"].load_balancer) == 0
    error_message = "No load balancer should be attached by default."
  }

  assert {
    condition     = length(aws_ecs_service.this["api"].service_connect_configuration) == 0
    error_message = "Service Connect must be disabled by default."
  }

  assert {
    condition     = length(aws_ecs_service.this["api"].service_registries) == 1
    error_message = "Services must register with Cloud Map service discovery by default."
  }

  assert {
    condition     = length(aws_appautoscaling_target.this) == 0 && length(aws_appautoscaling_policy.cpu) == 0
    error_message = "Autoscaling must be disabled by default."
  }

  assert {
    condition = (
      aws_service_discovery_service.this["api"].dns_config[0].routing_policy == "MULTIVALUE" &&
      aws_service_discovery_service.this["api"].dns_config[0].dns_records[0].type == "A" &&
      aws_service_discovery_service.this["api"].dns_config[0].dns_records[0].ttl == 10
    )
    error_message = "Service discovery must default to MULTIVALUE A records with a 10 second TTL."
  }

  assert {
    condition     = aws_service_discovery_private_dns_namespace.this[0].vpc == "vpc-0a1b2c3d4e5f67890"
    error_message = "Service discovery namespace must be associated with var.vpc_id."
  }
}

# ------------------------------------------------------------------------------
# IAM wiring (needs computed ARNs)
# ------------------------------------------------------------------------------
run "verify_module_created_roles_are_wired" {
  command   = apply
  state_key = "verify_module_created_roles_are_wired"

  override_resource {
    target = aws_iam_role.task_execution
    values = {
      arn = "arn:aws:iam::123456789012:role/core-prod-services-task-execution"
    }
  }

  override_resource {
    target = aws_iam_role.service_task
    values = {
      arn = "arn:aws:iam::123456789012:role/core-prod-services-api-task-role"
    }
  }

  assert {
    condition     = aws_ecs_task_definition.this["api"].execution_role_arn == "arn:aws:iam::123456789012:role/core-prod-services-task-execution"
    error_message = "Task definitions must use the module-created task execution role."
  }

  assert {
    condition     = aws_ecs_task_definition.this["api"].task_role_arn == "arn:aws:iam::123456789012:role/core-prod-services-api-task-role"
    error_message = "Task definitions must use the module-created per-service task role."
  }

  assert {
    condition     = aws_ecs_service.this["api"].cluster == aws_ecs_cluster.this.id
    error_message = "ECS services must run on the module ECS cluster."
  }

  assert {
    condition     = toset(aws_ecs_service.this["api"].network_configuration[0].security_groups) == toset([aws_security_group.service[0].id])
    error_message = "ECS services must use the module-created security group when none are supplied."
  }

  assert {
    condition     = aws_ecs_service.this["api"].service_registries[0].registry_arn == aws_service_discovery_service.this["api"].arn
    error_message = "ECS services must register with their module-created Cloud Map service."
  }

  assert {
    condition = (
      data.aws_iam_policy_document.service_default_task["api"].statement[0].sid == "CloudWatchLogs" &&
      data.aws_iam_policy_document.service_default_task["api"].statement[0].actions == toset(["logs:CreateLogStream", "logs:PutLogEvents"]) &&
      data.aws_iam_policy_document.service_default_task["api"].statement[0].resources == toset(["${aws_cloudwatch_log_group.this["api"].arn}:*"])
    )
    error_message = "The default task policy must scope log writes to the service's own log group."
  }

  assert {
    condition = (
      length(data.aws_iam_policy_document.service_default_task["api"].statement) == 2 &&
      data.aws_iam_policy_document.service_default_task["api"].statement[1].sid == "XRayTracing"
    )
    error_message = "The default task policy must grant only log and X-Ray permissions when ECS Exec is disabled."
  }

  assert {
    condition     = output.task_execution_role_arn == "arn:aws:iam::123456789012:role/core-prod-services-task-execution"
    error_message = "task_execution_role_arn output must expose the module-created execution role."
  }

  assert {
    condition     = output.service_task_role_arns == { api = "arn:aws:iam::123456789012:role/core-prod-services-api-task-role" }
    error_message = "service_task_role_arns output must map service keys to their task role ARNs."
  }

  assert {
    condition     = output.security_group_id == aws_security_group.service[0].id
    error_message = "security_group_id output must expose the module-created security group."
  }

  assert {
    condition     = output.cluster_arn == aws_ecs_cluster.this.arn && output.cluster_id == aws_ecs_cluster.this.id
    error_message = "Cluster outputs must expose the module ECS cluster."
  }

  assert {
    condition     = output.service_names == { api = "api" }
    error_message = "service_names output must map service keys to service names."
  }
}

run "verify_execute_command_grants_ssm_messages" {
  command   = apply
  state_key = "verify_execute_command_grants_ssm_messages"

  variables {
    services = {
      api = {
        container_port         = 8000
        image                  = "123456789012.dkr.ecr.us-west-2.amazonaws.com/api:v1.0.0"
        enable_execute_command = true
      }
    }
  }

  assert {
    condition     = aws_ecs_service.this["api"].enable_execute_command == true
    error_message = "enable_execute_command must flow through to the ECS service."
  }

  assert {
    condition = (
      length(data.aws_iam_policy_document.service_default_task["api"].statement) == 3 &&
      data.aws_iam_policy_document.service_default_task["api"].statement[2].sid == "ECSExec" &&
      contains(data.aws_iam_policy_document.service_default_task["api"].statement[2].actions, "ssmmessages:OpenDataChannel")
    )
    error_message = "Enabling ECS Exec must add the ssmmessages permissions to the task role."
  }
}

run "verify_secrets_read_policy_scoped_to_secrets_and_kms_key" {
  command = plan

  variables {
    secret_arns = [
      "arn:aws:secretsmanager:us-west-2:123456789012:secret:core-prod-db-AbCdEf",
      "arn:aws:secretsmanager:us-west-2:123456789012:secret:core-prod-api-key-GhIjKl",
    ]
  }

  assert {
    condition     = length(aws_iam_role_policy.task_execution_secrets) == 1
    error_message = "A secrets read policy must be attached when secret_arns is set."
  }

  assert {
    condition     = aws_iam_role_policy.task_execution_secrets[0].name == "core-prod-services-task-execution-secrets"
    error_message = "Secrets read policy name did not match <rendered_name>-task-execution-secrets."
  }

  assert {
    condition = (
      data.aws_iam_policy_document.task_execution_secrets[0].statement[0].actions == toset(["secretsmanager:GetSecretValue"]) &&
      data.aws_iam_policy_document.task_execution_secrets[0].statement[0].resources == toset([
        "arn:aws:secretsmanager:us-west-2:123456789012:secret:core-prod-db-AbCdEf",
        "arn:aws:secretsmanager:us-west-2:123456789012:secret:core-prod-api-key-GhIjKl",
      ])
    )
    error_message = "Secrets read access must be limited to GetSecretValue on the listed secrets."
  }

  assert {
    condition = (
      data.aws_iam_policy_document.task_execution_secrets[0].statement[1].actions == toset(["kms:Decrypt"]) &&
      data.aws_iam_policy_document.task_execution_secrets[0].statement[1].resources == toset(["arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"])
    )
    error_message = "Secret decryption must be limited to kms:Decrypt on var.kms_key_arn."
  }
}

# ------------------------------------------------------------------------------
# Parameter overrides
# ------------------------------------------------------------------------------
run "verify_optional_service_inputs_flow_through" {
  command = plan

  variables {
    services = {
      api = {
        container_port                    = 8002
        image                             = "123456789012.dkr.ecr.us-west-2.amazonaws.com/api:v2.0.0"
        cpu                               = 1024
        memory                            = 2048
        desired_count                     = 3
        environment                       = { LOG_LEVEL = "info" }
        secrets                           = { DATABASE_URL = "arn:aws:secretsmanager:us-west-2:123456789012:secret:core-prod-db-AbCdEf" }
        load_balancer_target_group_arn    = "arn:aws:elasticloadbalancing:us-west-2:123456789012:targetgroup/core-prod-api/0123456789abcdef"
        enable_deployment_circuit_breaker = true
        rollback_on_failure               = true
      }
    }
  }

  assert {
    condition     = aws_ecs_task_definition.this["api"].cpu == "1024" && aws_ecs_task_definition.this["api"].memory == "2048"
    error_message = "Task CPU and memory overrides did not flow through."
  }

  assert {
    condition     = aws_ecs_service.this["api"].desired_count == 3
    error_message = "Desired count override did not flow through."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this["api"].container_definitions)[0].image == "123456789012.dkr.ecr.us-west-2.amazonaws.com/api:v2.0.0"
    error_message = "Container image did not flow through."
  }

  assert {
    condition = jsondecode(aws_ecs_task_definition.this["api"].container_definitions)[0].portMappings == [
      {
        containerPort = 8002
        hostPort      = 8002
        protocol      = "tcp"
      }
    ]
    error_message = "Container port mapping did not flow through."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this["api"].container_definitions)[0].environment == [{ name = "LOG_LEVEL", value = "info" }]
    error_message = "Container environment variables did not flow through."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this["api"].container_definitions)[0].secrets == [{ name = "DATABASE_URL", valueFrom = "arn:aws:secretsmanager:us-west-2:123456789012:secret:core-prod-db-AbCdEf" }]
    error_message = "Container secrets did not flow through."
  }

  assert {
    condition = (
      one(aws_ecs_service.this["api"].load_balancer).target_group_arn == "arn:aws:elasticloadbalancing:us-west-2:123456789012:targetgroup/core-prod-api/0123456789abcdef" &&
      one(aws_ecs_service.this["api"].load_balancer).container_name == "api" &&
      one(aws_ecs_service.this["api"].load_balancer).container_port == 8002
    )
    error_message = "Load balancer target group attachment did not flow through."
  }

  assert {
    condition = (
      aws_ecs_service.this["api"].deployment_circuit_breaker[0].enable == true &&
      aws_ecs_service.this["api"].deployment_circuit_breaker[0].rollback == true
    )
    error_message = "Deployment circuit breaker and rollback did not flow through."
  }
}

run "verify_external_roles_and_security_groups" {
  command = plan

  variables {
    task_execution_role_arn = "arn:aws:iam::123456789012:role/core-prod-shared-execution"
    task_role_arn           = "arn:aws:iam::123456789012:role/core-prod-shared-task"
    security_group_ids      = ["sg-0fedcba9876543210"]

    services = {
      api = {
        container_port = 8000
        image          = "123456789012.dkr.ecr.us-west-2.amazonaws.com/api:v1.0.0"
      }
      worker = {
        container_port = 8001
        image          = "123456789012.dkr.ecr.us-west-2.amazonaws.com/worker:v1.0.0"
        task_role_arn  = "arn:aws:iam::123456789012:role/core-prod-worker-task"
      }
    }
  }

  assert {
    condition     = length(aws_iam_role.task_execution) == 0 && length(aws_iam_role_policy_attachment.task_execution) == 0
    error_message = "No task execution role should be created when task_execution_role_arn is supplied."
  }

  assert {
    condition     = length(aws_iam_role.service_task) == 0 && length(aws_iam_role_policy.service_default_task) == 0
    error_message = "No per-service task roles should be created when a shared or per-service task role is supplied."
  }

  assert {
    condition     = aws_ecs_task_definition.this["api"].execution_role_arn == "arn:aws:iam::123456789012:role/core-prod-shared-execution"
    error_message = "Task definitions must use the supplied task execution role."
  }

  assert {
    condition     = aws_ecs_task_definition.this["api"].task_role_arn == "arn:aws:iam::123456789012:role/core-prod-shared-task"
    error_message = "Task definitions must fall back to the shared task_role_arn."
  }

  assert {
    condition     = aws_ecs_task_definition.this["worker"].task_role_arn == "arn:aws:iam::123456789012:role/core-prod-worker-task"
    error_message = "A per-service task_role_arn must win over the shared task_role_arn."
  }

  assert {
    condition = (
      length(aws_security_group.service) == 0 &&
      length(aws_security_group_rule.alb_to_services) == 0 &&
      length(aws_security_group_rule.service_mesh) == 0
    )
    error_message = "No security group or rules should be created when security_group_ids is supplied."
  }

  assert {
    condition     = toset(aws_ecs_service.this["api"].network_configuration[0].security_groups) == toset(["sg-0fedcba9876543210"])
    error_message = "ECS services must use the supplied security groups."
  }

  assert {
    condition     = output.task_execution_role_arn == null && output.security_group_id == null && output.service_task_role_arns == {}
    error_message = "Role and security group outputs must be empty when nothing is created."
  }
}

run "verify_custom_task_policy_creates_dedicated_role" {
  command = plan

  variables {
    task_role_arn = "arn:aws:iam::123456789012:role/core-prod-shared-task"

    services = {
      api = {
        container_port        = 8000
        image                 = "123456789012.dkr.ecr.us-west-2.amazonaws.com/api:v1.0.0"
        task_role_policy_json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::core-prod-assets/*\"}]}"
      }
    }
  }

  assert {
    condition     = length(aws_iam_role.service_task) == 1 && length(aws_iam_role_policy.service_default_task) == 1
    error_message = "A service with task_role_policy_json must get its own task role with the default policy."
  }

  assert {
    condition     = aws_iam_role_policy.service_custom_task["api"].name == "core-prod-services-api-custom-policy"
    error_message = "Custom task policy name did not match <rendered_name>-<service>-custom-policy."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.service_custom_task["api"].policy).Statement[0].Action == "s3:GetObject"
    error_message = "Custom task policy document did not flow through."
  }
}

run "verify_service_discovery_custom_namespace" {
  command = plan

  variables {
    service_discovery_namespace = "internal.example.com"
  }

  assert {
    condition     = aws_service_discovery_private_dns_namespace.this[0].name == "internal.example.com"
    error_message = "Custom service discovery namespace did not flow through."
  }

  assert {
    condition     = aws_service_discovery_private_dns_namespace.this[0].description == "core-prod-services internal service discovery"
    error_message = "Service discovery namespace description did not match the rendered name."
  }
}

run "verify_service_discovery_can_be_disabled" {
  command = plan

  variables {
    service_discovery_namespace = ""
  }

  assert {
    condition     = length(aws_service_discovery_private_dns_namespace.this) == 0 && length(aws_service_discovery_service.this) == 0
    error_message = "No Cloud Map resources should be created when service_discovery_namespace is empty."
  }

  assert {
    condition     = length(aws_ecs_service.this["api"].service_registries) == 0
    error_message = "ECS services must not register with Cloud Map when service discovery is disabled."
  }
}

run "verify_service_connect" {
  command   = apply
  state_key = "verify_service_connect"

  variables {
    services = {
      api = {
        container_port                    = 8000
        image                             = "123456789012.dkr.ecr.us-west-2.amazonaws.com/api:v1.0.0"
        enable_service_connect            = true
        service_connect_port_name         = "http"
        service_connect_discovery_name    = "api-internal"
        service_connect_client_alias_port = 80
        service_connect_client_alias_dns  = "api.core.internal"
      }
    }
  }

  assert {
    condition     = aws_ecs_service.this["api"].service_connect_configuration[0].enabled == true
    error_message = "Service Connect must be enabled when enable_service_connect is true."
  }

  assert {
    condition     = aws_ecs_service.this["api"].service_connect_configuration[0].namespace == aws_service_discovery_private_dns_namespace.this[0].arn
    error_message = "Service Connect must use the module Cloud Map namespace."
  }

  assert {
    condition = (
      aws_ecs_service.this["api"].service_connect_configuration[0].service[0].port_name == "http" &&
      aws_ecs_service.this["api"].service_connect_configuration[0].service[0].discovery_name == "api-internal"
    )
    error_message = "Service Connect port name and discovery name did not flow through."
  }

  assert {
    condition = (
      aws_ecs_service.this["api"].service_connect_configuration[0].service[0].client_alias[0].port == 80 &&
      aws_ecs_service.this["api"].service_connect_configuration[0].service[0].client_alias[0].dns_name == "api.core.internal"
    )
    error_message = "Service Connect client alias did not flow through."
  }

  assert {
    condition     = length(aws_ecs_service.this["api"].service_registries) == 0
    error_message = "Services using Service Connect must not also register a Cloud Map service registry."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this["api"].container_definitions)[0].portMappings[0].name == "http"
    error_message = "The container port mapping must carry the Service Connect port name."
  }
}

run "verify_autoscaling_defaults_when_enabled" {
  command = plan

  variables {
    enable_autoscaling = true
  }

  assert {
    condition     = aws_appautoscaling_target.this["api"].resource_id == "service/core-prod-services/api"
    error_message = "Autoscaling target must point at the module ECS service."
  }

  assert {
    condition = (
      aws_appautoscaling_target.this["api"].service_namespace == "ecs" &&
      aws_appautoscaling_target.this["api"].scalable_dimension == "ecs:service:DesiredCount"
    )
    error_message = "Autoscaling target must scale ecs:service:DesiredCount."
  }

  assert {
    condition     = aws_appautoscaling_target.this["api"].min_capacity == 1 && aws_appautoscaling_target.this["api"].max_capacity == 6
    error_message = "Autoscaling must default to min = desired_count (1) and max = 6."
  }

  assert {
    condition     = aws_appautoscaling_policy.cpu["api"].name == "core-prod-services-api-cpu"
    error_message = "Autoscaling policy name did not match <rendered_name>-<service>-cpu."
  }

  assert {
    condition = (
      aws_appautoscaling_policy.cpu["api"].policy_type == "TargetTrackingScaling" &&
      aws_appautoscaling_policy.cpu["api"].target_tracking_scaling_policy_configuration[0].target_value == 60 &&
      aws_appautoscaling_policy.cpu["api"].target_tracking_scaling_policy_configuration[0].predefined_metric_specification[0].predefined_metric_type == "ECSServiceAverageCPUUtilization"
    )
    error_message = "Autoscaling must default to CPU target tracking at 60%."
  }

  assert {
    condition = (
      aws_appautoscaling_policy.cpu["api"].target_tracking_scaling_policy_configuration[0].scale_in_cooldown == 120 &&
      aws_appautoscaling_policy.cpu["api"].target_tracking_scaling_policy_configuration[0].scale_out_cooldown == 60
    )
    error_message = "Autoscaling cooldowns must default to 120s in and 60s out."
  }
}

run "verify_autoscaling_overrides" {
  command = plan

  variables {
    enable_autoscaling       = true
    autoscaling_max_capacity = 12
    autoscaling_cpu_target   = 75

    services = {
      api = {
        container_port = 8000
        image          = "123456789012.dkr.ecr.us-west-2.amazonaws.com/api:v1.0.0"
        desired_count  = 2
      }
    }
  }

  assert {
    condition     = aws_appautoscaling_target.this["api"].min_capacity == 2 && aws_appautoscaling_target.this["api"].max_capacity == 12
    error_message = "Autoscaling min must follow desired_count and max must follow autoscaling_max_capacity."
  }

  assert {
    condition     = aws_appautoscaling_policy.cpu["api"].target_tracking_scaling_policy_configuration[0].target_value == 75
    error_message = "autoscaling_cpu_target did not flow through."
  }
}

run "verify_alb_ingress_rule_can_be_disabled" {
  command = plan

  variables {
    create_alb_ingress_rule = false
  }

  assert {
    condition     = length(aws_security_group_rule.alb_to_services) == 0
    error_message = "No ALB ingress rule should be created when create_alb_ingress_rule is false."
  }

  assert {
    condition     = length(aws_security_group_rule.service_mesh) == 1
    error_message = "The intra-service rule must still be created with the module security group."
  }
}

# ------------------------------------------------------------------------------
# Validation
# ------------------------------------------------------------------------------
run "verify_invalid_environment_fails" {
  command = plan

  variables {
    environment = "INVALID_UPPERCASE"
  }

  expect_failures = [var.environment]
}
