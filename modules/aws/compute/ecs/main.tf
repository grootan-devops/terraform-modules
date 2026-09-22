data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  count              = var.task_execution_role_arn == null ? 1 : 0
  name               = "${local.rendered_name}-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  count      = var.task_execution_role_arn == null ? 1 : 0
  role       = aws_iam_role.task_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "task_execution_secrets" {
  count = var.task_execution_role_arn == null && length(var.secret_arns) > 0 ? 1 : 0

  statement {
    sid       = "ReadTaskSecrets"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = var.secret_arns
  }

  dynamic "statement" {
    for_each = var.kms_key_arn == null ? [] : [var.kms_key_arn]
    content {
      sid       = "DecryptTaskSecrets"
      effect    = "Allow"
      actions   = ["kms:Decrypt"]
      resources = [statement.value]
    }
  }
}

resource "aws_iam_role_policy" "task_execution_secrets" {
  count  = var.task_execution_role_arn == null && length(var.secret_arns) > 0 ? 1 : 0
  name   = "${local.rendered_name}-task-execution-secrets"
  role   = aws_iam_role.task_execution[0].id
  policy = data.aws_iam_policy_document.task_execution_secrets[0].json
}

resource "aws_iam_role" "service_task" {
  for_each = {
    for k, s in var.services : k => s
    if s.task_role_arn == null && (s.task_role_policy_json != null || var.task_role_arn == null)
  }

  name               = "${local.rendered_name}-${replace(each.key, "_", "-")}-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = merge(local.tags, { Name = "${local.rendered_name}-${replace(each.key, "_", "-")}-task-role" })
}

data "aws_iam_policy_document" "service_default_task" {
  for_each = var.services

  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = [
      "${aws_cloudwatch_log_group.this[each.key].arn}:*"
    ]
  }

  statement {
    sid    = "XRayTracing"
    effect = "Allow"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords"
    ]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = coalesce(each.value.enable_execute_command, false) ? [1] : []
    content {
      sid    = "ECSExec"
      effect = "Allow"
      actions = [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel"
      ]
      resources = ["*"]
    }
  }
}

resource "aws_iam_role_policy" "service_default_task" {
  for_each = {
    for k, s in var.services : k => s
    if s.task_role_arn == null && (s.task_role_policy_json != null || var.task_role_arn == null)
  }

  name   = "${local.rendered_name}-${replace(each.key, "_", "-")}-default-policy"
  role   = aws_iam_role.service_task[each.key].id
  policy = data.aws_iam_policy_document.service_default_task[each.key].json
}

resource "aws_iam_role_policy" "service_custom_task" {
  for_each = {
    for k, s in var.services : k => s
    if s.task_role_arn == null && s.task_role_policy_json != null
  }

  name   = "${local.rendered_name}-${replace(each.key, "_", "-")}-custom-policy"
  role   = aws_iam_role.service_task[each.key].id
  policy = each.value.task_role_policy_json
}

resource "aws_security_group" "service" {
  count       = length(var.security_group_ids) == 0 ? 1 : 0
  name        = "${local.rendered_name}-service-sg"
  description = "ECS tasks security group"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.rendered_name}-service-sg" })
}

resource "aws_security_group_rule" "alb_to_services" {
  count                    = var.create_alb_ingress_rule && length(var.security_group_ids) == 0 ? 1 : 0
  type                     = "ingress"
  from_port                = 8000
  to_port                  = 8004
  protocol                 = "tcp"
  security_group_id        = aws_security_group.service[0].id
  source_security_group_id = var.alb_security_group_id
  description              = "Allow traffic from ALB to ECS services"
}

resource "aws_security_group_rule" "service_mesh" {
  count             = length(var.security_group_ids) == 0 ? 1 : 0
  type              = "ingress"
  from_port         = 8000
  to_port           = 8004
  protocol          = "tcp"
  security_group_id = aws_security_group.service[0].id
  self              = true
  description       = "Intra-service mesh network rule"
}

resource "aws_service_discovery_private_dns_namespace" "this" {
  count       = local.service_discovery_namespace != "" ? 1 : 0
  name        = local.service_discovery_namespace
  description = "${local.rendered_name} internal service discovery"
  vpc         = var.vpc_id

  tags = local.tags
}

resource "aws_service_discovery_service" "this" {
  for_each = local.service_discovery_namespace != "" ? var.services : {}

  name = each.key

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.this[0].id

    dns_records {
      type = "A"
      ttl  = 10
    }

    routing_policy = "MULTIVALUE"
  }

  tags = local.tags
}

resource "aws_ecs_cluster" "this" {
  name = local.rendered_name

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = local.tags
}

resource "aws_cloudwatch_log_group" "this" {
  for_each          = var.services
  name              = "/ecs/${local.rendered_name}/${each.key}"
  retention_in_days = 90
  kms_key_id        = var.kms_key_arn
  tags              = local.tags
}

resource "aws_ecs_task_definition" "this" {
  for_each = var.services

  family                   = "${local.rendered_name}-${replace(each.key, "_", "-")}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = var.task_execution_role_arn != null ? var.task_execution_role_arn : aws_iam_role.task_execution[0].arn
  task_role_arn            = coalesce(each.value.task_role_arn, try(aws_iam_role.service_task[each.key].arn, null), var.task_role_arn)

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = each.key
    image     = each.value.image
    essential = true

    portMappings = [
      merge(
        {
          containerPort = each.value.container_port
          hostPort      = each.value.container_port
          protocol      = "tcp"
        },
        coalesce(each.value.enable_service_connect, false) && each.value.service_connect_port_name != null ? {
          name = each.value.service_connect_port_name
        } : {}
      )
    ]

    environment = (
      each.value.environment == null ? [] : [
        for k, v in each.value.environment : { name = k, value = v }
      ]
    )

    secrets = (
      each.value.secrets == null ? [] : [
        for k, v in each.value.secrets : { name = k, valueFrom = v }
      ]
    )

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.this[each.key].name
        "awslogs-region"        = data.aws_region.current.region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  tags = local.tags

  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

resource "aws_ecs_service" "this" {
  for_each = var.services

  name                   = each.key
  cluster                = aws_ecs_cluster.this.id
  task_definition        = aws_ecs_task_definition.this[each.key].arn
  desired_count          = each.value.desired_count
  launch_type            = "FARGATE"
  enable_execute_command = each.value.enable_execute_command

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = length(var.security_group_ids) > 0 ? var.security_group_ids : [aws_security_group.service[0].id]
    assign_public_ip = false
  }

  dynamic "service_registries" {
    for_each = local.service_discovery_namespace != "" && !coalesce(each.value.enable_service_connect, false) ? [aws_service_discovery_service.this[each.key].arn] : []
    content {
      registry_arn = service_registries.value
    }
  }

  dynamic "load_balancer" {
    for_each = each.value.load_balancer_target_group_arn != null ? [each.value.load_balancer_target_group_arn] : []
    content {
      target_group_arn = load_balancer.value
      container_name   = each.key
      container_port   = each.value.container_port
    }
  }

  dynamic "deployment_circuit_breaker" {
    for_each = coalesce(each.value.enable_deployment_circuit_breaker, false) ? [1] : []
    content {
      enable   = true
      rollback = coalesce(each.value.rollback_on_failure, false)
    }
  }

  dynamic "service_connect_configuration" {
    for_each = coalesce(each.value.enable_service_connect, false) && local.service_discovery_namespace != "" ? [1] : []
    content {
      enabled   = true
      namespace = aws_service_discovery_private_dns_namespace.this[0].arn

      dynamic "service" {
        for_each = each.value.service_connect_port_name != null ? [1] : []
        content {
          port_name      = each.value.service_connect_port_name
          discovery_name = coalesce(each.value.service_connect_discovery_name, each.key)

          dynamic "client_alias" {
            for_each = each.value.service_connect_client_alias_port != null ? [1] : []
            content {
              port     = each.value.service_connect_client_alias_port
              dns_name = coalesce(each.value.service_connect_client_alias_dns, each.key)
            }
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}

resource "aws_appautoscaling_target" "this" {
  for_each = var.enable_autoscaling ? var.services : {}

  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.this[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = coalesce(each.value.desired_count, 1)
  max_capacity       = var.autoscaling_max_capacity
}

resource "aws_appautoscaling_policy" "cpu" {
  for_each = var.enable_autoscaling ? var.services : {}

  name               = "${local.rendered_name}-${replace(each.key, "_", "-")}-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this[each.key].service_namespace
  resource_id        = aws_appautoscaling_target.this[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.this[each.key].scalable_dimension

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = var.autoscaling_cpu_target
    scale_in_cooldown  = 120
    scale_out_cooldown = 60
  }
}
