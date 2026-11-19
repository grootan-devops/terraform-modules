module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags
  names = merge(
    {
      bus            = { max_length = 256 }
      archive        = { max_length = 48 }
      log_delivery   = { suffix = "logs", max_length = 60 }
      log_policy     = { suffix = "log-delivery", max_length = 255 }
      ERROR_LOGS     = { suffix = "error-logs", max_length = 60 }
      INFO_LOGS      = { suffix = "info-logs", max_length = 60 }
      TRACE_LOGS     = { suffix = "trace-logs", max_length = 60 }
      schedule_group = { max_length = 64 }
    },
    { for key in keys(var.rules) : "rule-${key}" => { suffix = key, max_length = 64 } }
  )
}

module "encryption" {
  source = "../../core/encryption"

  application        = var.application
  environment        = var.environment
  name               = var.name
  purpose            = "events"
  tags               = var.tags
  kms                = var.kms
  service_statements = local.kms_service_statements
}

resource "aws_cloudwatch_event_bus" "this" {
  count = var.bus.enabled ? 1 : 0

  name               = local.bus_name
  description        = var.bus.description
  kms_key_identifier = local.kms_key_arn

  dynamic "log_config" {
    for_each = local.bus_logging ? [1] : []
    content {
      level          = var.cloudwatch_logs.level
      include_detail = var.cloudwatch_logs.include_detail
    }
  }

  tags = merge(module.naming.tags, { Name = local.bus_name })
}

module "bus_policy" {
  source = "../../core/policy-document"
  count  = length(var.policy_statements) > 0 ? 1 : 0

  default_resources = [local.bus_arn]
  statements        = var.policy_statements
}

resource "aws_cloudwatch_event_bus_policy" "this" {
  count = length(var.policy_statements) > 0 ? 1 : 0

  event_bus_name = var.bus.enabled ? aws_cloudwatch_event_bus.this[0].name : "default"
  policy         = module.bus_policy[0].json
}

resource "aws_cloudwatch_event_archive" "this" {
  count = var.archive.enabled ? 1 : 0

  name               = module.naming.names.archive
  description        = var.archive.description
  event_source_arn   = var.bus.enabled ? aws_cloudwatch_event_bus.this[0].arn : local.bus_arn
  event_pattern      = var.archive.event_pattern
  retention_days     = var.archive.retention_days
  kms_key_identifier = local.kms_key_arn
}

resource "aws_cloudwatch_event_rule" "this" {
  for_each = var.rules

  name           = module.naming.names["rule-${each.key}"]
  description    = each.value.description
  event_bus_name = var.bus.enabled ? aws_cloudwatch_event_bus.this[0].name : "default"
  event_pattern  = each.value.event_pattern
  state          = each.value.state

  tags = merge(module.naming.tags, { Name = module.naming.names["rule-${each.key}"] })
}

module "role" {
  source = "../../security/iam-role"
  count  = local.creates_role ? 1 : 0

  application              = var.application
  environment              = var.environment
  name                     = var.name
  purpose                  = "events"
  tags                     = var.tags
  role_name                = var.iam_role.name
  path                     = var.iam_role.path
  permissions_boundary_arn = var.iam_role.permissions_boundary_arn
  managed_policy_arns      = var.iam_role.managed_policy_arns
  policy_statements        = var.iam_role.policy_statements
  policy_documents         = local.role_policy_documents
  trust = {
    services   = ["events.${module.naming.dns_suffix}", "scheduler.${module.naming.dns_suffix}"]
    conditions = [{ test = "StringEquals", variable = "aws:SourceAccount", values = [module.naming.account_id] }]
  }
}

resource "aws_cloudwatch_event_target" "this" {
  for_each = local.targets

  rule           = aws_cloudwatch_event_rule.this[each.value.rule].name
  event_bus_name = aws_cloudwatch_event_rule.this[each.value.rule].event_bus_name
  target_id      = each.value.key
  arn            = each.value.arn
  role_arn       = contains(local.rule_role_types, each.value.type) ? local.role_arn : null
  input          = each.value.input
  input_path     = each.value.input_path

  dynamic "input_transformer" {
    for_each = each.value.input_transformer == null ? [] : [each.value.input_transformer]
    content {
      input_paths    = input_transformer.value.input_paths
      input_template = input_transformer.value.input_template
    }
  }

  dynamic "dead_letter_config" {
    for_each = each.value.dead_letter_queue.enabled ? [1] : []
    content {
      arn = each.value.dead_letter_queue.arn
    }
  }

  retry_policy {
    maximum_event_age_in_seconds = each.value.retry_policy.maximum_event_age_in_seconds
    maximum_retry_attempts       = each.value.retry_policy.maximum_retry_attempts
  }

  dynamic "sqs_target" {
    for_each = each.value.type == "sqs" && try(each.value.sqs.message_group_id, null) != null ? [each.value.sqs] : []
    content {
      message_group_id = sqs_target.value.message_group_id
    }
  }

  dynamic "kinesis_target" {
    for_each = each.value.type == "kinesis" && try(each.value.kinesis.partition_key_path, null) != null ? [each.value.kinesis] : []
    content {
      partition_key_path = kinesis_target.value.partition_key_path
    }
  }

  dynamic "batch_target" {
    for_each = each.value.type == "batch" ? [each.value.batch] : []
    content {
      job_definition = batch_target.value.job_definition_arn
      job_name       = coalesce(batch_target.value.job_name, "${aws_cloudwatch_event_rule.this[each.value.rule].name}-${each.value.key}")
      array_size     = batch_target.value.array_size
      job_attempts   = batch_target.value.job_attempts
    }
  }

  dynamic "ecs_target" {
    for_each = each.value.type == "ecs" ? [each.value.ecs] : []
    content {
      task_definition_arn     = ecs_target.value.task_definition_arn
      task_count              = ecs_target.value.task_count
      launch_type             = ecs_target.value.launch_type
      platform_version        = ecs_target.value.platform_version
      propagate_tags          = ecs_target.value.propagate_tags
      enable_ecs_managed_tags = ecs_target.value.enable_ecs_managed_tags
      enable_execute_command  = ecs_target.value.enable_execute_command

      dynamic "network_configuration" {
        for_each = length(ecs_target.value.subnet_ids) > 0 ? [1] : []
        content {
          subnets          = ecs_target.value.subnet_ids
          security_groups  = ecs_target.value.security_group_ids
          assign_public_ip = ecs_target.value.assign_public_ip
        }
      }
    }
  }

  dynamic "http_target" {
    for_each = each.value.type == "api_destination" && each.value.http != null ? [each.value.http] : []
    content {
      header_parameters       = http_target.value.header_parameters
      query_string_parameters = http_target.value.query_string_parameters
      path_parameter_values   = http_target.value.path_parameter_values
    }
  }
}
