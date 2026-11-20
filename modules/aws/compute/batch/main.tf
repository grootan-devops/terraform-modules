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
  purpose            = "batch"
  tags               = var.tags
  kms                = var.kms
  service_statements = local.kms_service_statements
}

module "log_group" {
  source = "../../observability/log-group"
  count  = local.logs_enabled ? 1 : 0

  application                 = var.application
  environment                 = var.environment
  name                        = var.name
  tags                        = var.tags
  log_group_name              = local.log_group_name
  retention_in_days           = var.cloudwatch_logs.retention_in_days
  log_group_class             = var.cloudwatch_logs.log_group_class
  deletion_protection_enabled = var.cloudwatch_logs.deletion_protection_enabled
  kms_key_arn                 = try(coalesce(var.cloudwatch_logs.kms_key_arn, local.kms_key_arn), null)
}

module "job_role" {
  source = "../../security/iam-role"
  count  = var.iam_role.create && local.has_jobs ? 1 : 0

  application              = var.application
  environment              = var.environment
  name                     = var.name
  purpose                  = "job"
  tags                     = var.tags
  role_name                = var.iam_role.name
  path                     = var.iam_role.path
  permissions_boundary_arn = var.iam_role.permissions_boundary_arn
  managed_policy_arns      = var.iam_role.managed_policy_arns
  policy_statements        = var.iam_role.policy_statements
  trust = {
    services   = ["ecs-tasks.${local.dns_suffix}"]
    conditions = local.task_trust_conditions
  }
}

module "execution_role" {
  source = "../../security/iam-role"
  count  = local.has_jobs ? 1 : 0

  application              = var.application
  environment              = var.environment
  name                     = var.name
  purpose                  = "exec"
  tags                     = var.tags
  path                     = var.iam_role.path
  permissions_boundary_arn = var.iam_role.permissions_boundary_arn
  policy_documents         = [jsonencode({ Version = "2012-10-17", Statement = local.execution_statements })]
  trust = {
    services = ["ecs-tasks.${local.dns_suffix}"]
  }
}

module "instance_role" {
  source = "../../security/iam-role"
  count  = local.has_ec2 ? 1 : 0

  application              = var.application
  environment              = var.environment
  name                     = var.name
  purpose                  = "instance"
  tags                     = var.tags
  path                     = var.iam_role.path
  permissions_boundary_arn = var.iam_role.permissions_boundary_arn
  managed_policy_arns      = ["${local.arn_prefix}:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"]
  instance_profile         = { enabled = true }
  trust = {
    services = ["ec2.${local.dns_suffix}"]
  }
}

module "security_group" {
  source = "../../network/security-group"
  count  = var.security_group.create && length(var.compute_environments) > 0 ? 1 : 0

  application  = var.application
  environment  = var.environment
  name         = var.name
  purpose      = "batch"
  tags         = var.tags
  vpc_id       = var.vpc_id
  egress_rules = local.egress_rules
}

resource "aws_launch_template" "this" {
  for_each = local.ec2_environments

  name_prefix            = "${module.naming.names["ce-${each.key}"]}-"
  description            = "${module.naming.names["ce-${each.key}"]} Batch instances"
  update_default_version = true

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_type           = "gp3"
      volume_size           = each.value.root_volume_size
      encrypted             = "true"
      kms_key_id            = local.kms_key_arn
      delete_on_termination = "true"
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(module.naming.tags, { Name = module.naming.names["ce-${each.key}"] })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(module.naming.tags, { Name = module.naming.names["ce-${each.key}"] })
  }

  tags = merge(module.naming.tags, { Name = module.naming.names["ce-${each.key}"] })
}

resource "aws_batch_compute_environment" "this" {
  for_each = var.compute_environments

  name_prefix = "${module.naming.names["ce-${each.key}"]}-"
  type        = "MANAGED"
  state       = each.value.state

  compute_resources {
    type                = each.value.type
    max_vcpus           = each.value.max_vcpus
    min_vcpus           = contains(["EC2", "SPOT"], each.value.type) ? each.value.min_vcpus : null
    instance_type       = contains(["EC2", "SPOT"], each.value.type) ? each.value.instance_types : null
    instance_role       = contains(["EC2", "SPOT"], each.value.type) ? module.instance_role[0].instance_profile_arn : null
    allocation_strategy = contains(["EC2", "SPOT"], each.value.type) ? coalesce(each.value.allocation_strategy, each.value.type == "SPOT" ? "SPOT_PRICE_CAPACITY_OPTIMIZED" : "BEST_FIT_PROGRESSIVE") : null
    subnets             = var.subnet_ids
    security_group_ids  = local.security_group_ids
    tags                = contains(["EC2", "SPOT"], each.value.type) ? merge(module.naming.tags, { Name = module.naming.names["ce-${each.key}"] }) : null

    dynamic "launch_template" {
      for_each = contains(["EC2", "SPOT"], each.value.type) ? [1] : []
      content {
        launch_template_id = aws_launch_template.this[each.key].id
        version            = tostring(aws_launch_template.this[each.key].latest_version)
      }
    }

    dynamic "ec2_configuration" {
      for_each = contains(["EC2", "SPOT"], each.value.type) ? [1] : []
      content {
        image_type = "ECS_AL2023"
      }
    }
  }

  tags = merge(module.naming.tags, { Name = module.naming.names["ce-${each.key}"] })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_batch_scheduling_policy" "this" {
  count = var.scheduling_policy.enabled ? 1 : 0

  name = module.naming.names.scheduling

  fair_share_policy {
    compute_reservation = var.scheduling_policy.compute_reservation
    share_decay_seconds = var.scheduling_policy.share_decay_seconds

    dynamic "share_distribution" {
      for_each = var.scheduling_policy.share_distribution
      content {
        share_identifier = share_distribution.value.share_identifier
        weight_factor    = share_distribution.value.weight_factor
      }
    }
  }

  tags = merge(module.naming.tags, { Name = module.naming.names.scheduling })
}

resource "aws_batch_job_queue" "this" {
  for_each = var.job_queues

  name                  = module.naming.names["jq-${each.key}"]
  state                 = each.value.state
  priority              = each.value.priority
  scheduling_policy_arn = each.value.scheduling_policy_arn != null ? each.value.scheduling_policy_arn : try(aws_batch_scheduling_policy.this[0].arn, null)

  dynamic "compute_environment_order" {
    for_each = each.value.compute_environments
    content {
      order               = compute_environment_order.key
      compute_environment = contains(keys(var.compute_environments), compute_environment_order.value) ? aws_batch_compute_environment.this[compute_environment_order.value].arn : compute_environment_order.value
    }
  }

  tags = merge(module.naming.tags, { Name = module.naming.names["jq-${each.key}"] })
}

resource "aws_batch_job_definition" "this" {
  for_each = var.job_definitions

  name                  = module.naming.names["jd-${each.key}"]
  type                  = "container"
  platform_capabilities = [each.value.platform]
  container_properties  = local.container_properties[each.key]
  parameters            = each.value.parameters
  propagate_tags        = true

  retry_strategy {
    attempts = each.value.attempts

    dynamic "evaluate_on_exit" {
      for_each = each.value.evaluate_on_exit
      content {
        action           = evaluate_on_exit.value.action
        on_exit_code     = evaluate_on_exit.value.on_exit_code
        on_reason        = evaluate_on_exit.value.on_reason
        on_status_reason = evaluate_on_exit.value.on_status_reason
      }
    }
  }

  dynamic "timeout" {
    for_each = each.value.timeout_seconds == null ? [] : [each.value.timeout_seconds]
    content {
      attempt_duration_seconds = timeout.value
    }
  }

  tags = merge(module.naming.tags, { Name = module.naming.names["jd-${each.key}"] })
}
