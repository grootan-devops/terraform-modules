module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags
  names       = local.names
}

module "encryption" {
  source = "../../core/encryption"

  application        = var.application
  environment        = var.environment
  name               = var.name
  purpose            = "ecs"
  tags               = var.tags
  kms                = var.kms
  service_statements = local.kms_service_statements
}

module "log_group" {
  source   = "../../observability/log-group"
  for_each = local.log_group_names

  application                 = var.application
  environment                 = var.environment
  name                        = var.name
  tags                        = var.tags
  log_group_name              = each.value
  retention_in_days           = var.cloudwatch_logs.retention_in_days
  log_group_class             = var.cloudwatch_logs.log_group_class
  deletion_protection_enabled = var.cloudwatch_logs.deletion_protection_enabled
  kms_key_arn                 = local.log_kms_key_arn
}

module "exec_log_group" {
  source = "../../observability/log-group"
  count  = local.exec_enabled ? 1 : 0

  application                 = var.application
  environment                 = var.environment
  name                        = var.name
  tags                        = var.tags
  log_group_name              = local.exec_log_group_name
  retention_in_days           = var.cloudwatch_logs.retention_in_days
  log_group_class             = var.cloudwatch_logs.log_group_class
  deletion_protection_enabled = var.cloudwatch_logs.deletion_protection_enabled
  kms_key_arn                 = local.log_kms_key_arn
}

module "execution_role" {
  source = "../../security/iam-role"
  count  = local.has_services ? 1 : 0

  application              = var.application
  environment              = var.environment
  name                     = var.name
  purpose                  = "ecs-exec"
  tags                     = var.tags
  path                     = var.iam_role.path
  permissions_boundary_arn = var.iam_role.permissions_boundary_arn
  policy_documents         = [jsonencode({ Version = "2012-10-17", Statement = local.execution_statements })]
  trust = {
    services = ["ecs-tasks.${local.dns_suffix}"]
  }
}

module "task_role" {
  source   = "../../security/iam-role"
  for_each = local.task_roles

  application              = var.application
  environment              = var.environment
  name                     = var.name
  purpose                  = "${each.key}-task"
  tags                     = var.tags
  path                     = var.iam_role.path
  permissions_boundary_arn = var.iam_role.permissions_boundary_arn
  managed_policy_arns      = concat(var.iam_role.managed_policy_arns, each.value.task_role.managed_policy_arns)
  policy_statements        = concat(var.iam_role.policy_statements, each.value.task_role.policy_statements)
  policy_documents         = each.value.execute_command || var.tracing.enabled || length(each.value.efs_volumes) > 0 ? [jsonencode({ Version = "2012-10-17", Statement = local.task_statements[each.key] })] : []
  trust = {
    services   = ["ecs-tasks.${local.dns_suffix}"]
    conditions = local.task_trust_conditions
  }
}

#trivy:ignore:AVD-AWS-0104
module "security_group" {
  source = "../../network/security-group"
  count  = var.security_group.create ? 1 : 0

  application   = var.application
  environment   = var.environment
  name          = var.name
  purpose       = "tasks"
  tags          = var.tags
  vpc_id        = var.vpc_id
  ingress_rules = local.ingress_rules
  egress_rules  = local.egress_rules
}

resource "aws_ecs_cluster" "this" {
  name = local.cluster_name

  setting {
    name  = "containerInsights"
    value = var.container_insights
  }

  dynamic "configuration" {
    for_each = local.exec_enabled || local.kms_encrypted ? [1] : []
    content {
      dynamic "execute_command_configuration" {
        for_each = local.exec_enabled ? [1] : []
        content {
          kms_key_id = local.kms_key_arn
          logging    = "OVERRIDE"

          log_configuration {
            cloud_watch_encryption_enabled = local.log_kms_key_arn != null
            cloud_watch_log_group_name     = module.exec_log_group[0].name
          }
        }
      }

      dynamic "managed_storage_configuration" {
        for_each = local.kms_encrypted ? [1] : []
        content {
          fargate_ephemeral_storage_kms_key_id = local.kms_key_arn
        }
      }
    }
  }

  tags = merge(module.naming.tags, { Name = local.cluster_name })
}

resource "aws_service_discovery_private_dns_namespace" "this" {
  count = local.namespace_enabled ? 1 : 0

  name        = local.namespace_name
  description = "${local.cluster_name} service discovery"
  vpc         = var.vpc_id

  tags = merge(module.naming.tags, { Name = local.namespace_name })
}

resource "aws_service_discovery_service" "this" {
  for_each = local.discovery_services

  name = each.key

  dns_config {
    namespace_id   = aws_service_discovery_private_dns_namespace.this[0].id
    routing_policy = "MULTIVALUE"

    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  tags = merge(module.naming.tags, { Name = "${local.cluster_name}-${each.key}" })
}

resource "aws_ecs_task_definition" "this" {
  for_each = var.services

  family                   = module.naming.names["td-${each.key}"]
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(each.value.cpu)
  memory                   = tostring(each.value.memory)
  execution_role_arn       = module.execution_role[0].arn
  task_role_arn            = local.task_role_arns[each.key]
  container_definitions    = local.container_definitions[each.key]

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = each.value.cpu_architecture
  }

  dynamic "volume" {
    for_each = each.value.writable_paths
    content {
      name = "scratch-${volume.key}"
    }
  }

  dynamic "volume" {
    for_each = each.value.efs_volumes
    content {
      name = volume.key

      efs_volume_configuration {
        file_system_id     = volume.value.file_system_id
        root_directory     = volume.value.root_directory
        transit_encryption = "ENABLED"

        authorization_config {
          access_point_id = volume.value.access_point_id
          iam             = volume.value.access_point_id != null ? "ENABLED" : "DISABLED"
        }
      }
    }
  }

  tags = merge(module.naming.tags, { Name = module.naming.names["td-${each.key}"] })
}

resource "aws_ecs_service" "this" {
  for_each = var.services

  name                              = each.key
  cluster                           = aws_ecs_cluster.this.arn
  task_definition                   = aws_ecs_task_definition.this[each.key].arn
  desired_count                     = each.value.desired_count
  launch_type                       = "FARGATE"
  platform_version                  = "LATEST"
  enable_execute_command            = each.value.execute_command
  enable_ecs_managed_tags           = true
  propagate_tags                    = "SERVICE"
  health_check_grace_period_seconds = length(each.value.target_group_arns) > 0 ? each.value.health_check_grace_period_seconds : null

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = local.security_group_ids
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = each.value.target_group_arns
    content {
      target_group_arn = load_balancer.value
      container_name   = each.key
      container_port   = each.value.container_port
    }
  }

  dynamic "service_registries" {
    for_each = each.value.service_discovery ? [1] : []
    content {
      registry_arn = aws_service_discovery_service.this[each.key].arn
    }
  }

  deployment_circuit_breaker {
    enable   = each.value.deployment_circuit_breaker.enabled
    rollback = each.value.deployment_circuit_breaker.enabled && each.value.deployment_circuit_breaker.rollback
  }

  dynamic "service_connect_configuration" {
    for_each = each.value.service_connect.enabled ? [each.value.service_connect] : []
    content {
      enabled   = true
      namespace = aws_service_discovery_private_dns_namespace.this[0].arn

      service {
        port_name      = each.key
        discovery_name = coalesce(service_connect_configuration.value.discovery_name, each.key)

        client_alias {
          port     = coalesce(service_connect_configuration.value.client_alias_port, each.value.container_port)
          dns_name = coalesce(service_connect_configuration.value.client_alias_dns, each.key)
        }
      }
    }
  }

  tags = merge(module.naming.tags, { Name = "${local.cluster_name}-${each.key}" })

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}

resource "aws_appautoscaling_target" "this" {
  for_each = local.autoscaled_services

  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.this[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = coalesce(each.value.autoscaling.min_capacity, each.value.desired_count)
  max_capacity       = each.value.autoscaling.max_capacity

  tags = merge(module.naming.tags, { Name = "${local.cluster_name}-${each.key}" })
}

resource "aws_appautoscaling_policy" "cpu" {
  for_each = local.autoscaled_services

  name               = "${local.cluster_name}-${each.key}-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this[each.key].service_namespace
  resource_id        = aws_appautoscaling_target.this[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.this[each.key].scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = each.value.autoscaling.cpu_target
    scale_in_cooldown  = 120
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

resource "aws_appautoscaling_policy" "memory" {
  for_each = { for k, s in local.autoscaled_services : k => s if s.autoscaling.memory_target != null }

  name               = "${local.cluster_name}-${each.key}-memory"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this[each.key].service_namespace
  resource_id        = aws_appautoscaling_target.this[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.this[each.key].scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = each.value.autoscaling.memory_target
    scale_in_cooldown  = 120
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
  }
}
