module "schedule_naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  name        = var.name
  names       = { for key in keys(var.scheduler.schedules) : "schedule-${key}" => { suffix = key, max_length = 64 } }
}

resource "aws_scheduler_schedule_group" "this" {
  count = var.scheduler.enabled ? 1 : 0

  name = module.naming.names.schedule_group

  tags = merge(module.naming.tags, { Name = module.naming.names.schedule_group })
}

resource "aws_scheduler_schedule" "this" {
  for_each = var.scheduler.schedules

  name                         = module.schedule_naming.names["schedule-${each.key}"]
  group_name                   = aws_scheduler_schedule_group.this[0].name
  description                  = each.value.description
  schedule_expression          = each.value.expression
  schedule_expression_timezone = each.value.timezone
  start_date                   = each.value.start_date
  end_date                     = each.value.end_date
  state                        = each.value.state
  action_after_completion      = each.value.action_after_completion
  kms_key_arn                  = local.kms_key_arn

  flexible_time_window {
    mode                      = each.value.flexible_window_minutes == null ? "OFF" : "FLEXIBLE"
    maximum_window_in_minutes = each.value.flexible_window_minutes
  }

  target {
    arn      = local.schedule_target_arns[each.key]
    role_arn = local.role_arn
    input    = local.schedule_inputs[each.key]

    dynamic "dead_letter_config" {
      for_each = each.value.target.dead_letter_queue.enabled ? [1] : []
      content {
        arn = each.value.target.dead_letter_queue.arn
      }
    }

    retry_policy {
      maximum_event_age_in_seconds = each.value.target.retry_policy.maximum_event_age_in_seconds
      maximum_retry_attempts       = each.value.target.retry_policy.maximum_retry_attempts
    }

    dynamic "sqs_parameters" {
      for_each = each.value.target.type == "sqs" && try(each.value.target.sqs.message_group_id, null) != null ? [each.value.target.sqs] : []
      content {
        message_group_id = sqs_parameters.value.message_group_id
      }
    }

    dynamic "kinesis_parameters" {
      for_each = each.value.target.type == "kinesis" ? [each.value.target.kinesis] : []
      content {
        partition_key = kinesis_parameters.value.partition_key
      }
    }

    dynamic "eventbridge_parameters" {
      for_each = each.value.target.type == "event_bus" ? [each.value.target.event_bus] : []
      content {
        detail_type = eventbridge_parameters.value.detail_type
        source      = eventbridge_parameters.value.source
      }
    }

    dynamic "ecs_parameters" {
      for_each = each.value.target.type == "ecs" ? [each.value.target.ecs] : []
      content {
        task_definition_arn     = ecs_parameters.value.task_definition_arn
        task_count              = ecs_parameters.value.task_count
        launch_type             = ecs_parameters.value.launch_type
        platform_version        = ecs_parameters.value.platform_version
        propagate_tags          = ecs_parameters.value.propagate_tags
        enable_ecs_managed_tags = ecs_parameters.value.enable_ecs_managed_tags
        enable_execute_command  = ecs_parameters.value.enable_execute_command

        dynamic "network_configuration" {
          for_each = length(ecs_parameters.value.subnet_ids) > 0 ? [1] : []
          content {
            subnets          = ecs_parameters.value.subnet_ids
            security_groups  = ecs_parameters.value.security_group_ids
            assign_public_ip = ecs_parameters.value.assign_public_ip
          }
        }
      }
    }
  }
}
