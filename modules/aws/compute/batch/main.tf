# ------------------------------------------------------------------------------
# AWS Batch Scheduling Policy
# ------------------------------------------------------------------------------
resource "aws_batch_scheduling_policy" "this" {
  count = var.create_scheduling_policy ? 1 : 0

  name = var.scheduling_policy_name != null ? var.scheduling_policy_name : "${local.rendered_name}-policy"

  dynamic "fair_share_policy" {
    for_each = var.scheduling_policy_fair_share_policy != null ? [var.scheduling_policy_fair_share_policy] : []
    content {
      share_decay_seconds = fair_share_policy.value.share_decay_seconds

      dynamic "share_distribution" {
        for_each = fair_share_policy.value.share_distribution
        content {
          share_identifier = share_distribution.value.share_identifier
          weight_factor    = share_distribution.value.weight_factor
        }
      }
    }
  }

  tags = local.tags
}

# ------------------------------------------------------------------------------
# AWS Batch Compute Environment
# ------------------------------------------------------------------------------
resource "aws_batch_compute_environment" "this" {
  for_each = var.compute_environments

  name         = "${local.rendered_name}-${each.key}"
  type         = each.value.type
  state        = each.value.state
  service_role = each.value.service_role_arn

  compute_resources {
    type               = each.value.compute_resources.type
    max_vcpus          = each.value.compute_resources.max_vcpus
    security_group_ids = each.value.compute_resources.security_group_ids
    subnets            = each.value.compute_resources.subnets
  }

  tags = merge(local.tags, { Name = "${local.rendered_name}-${each.key}" })

  lifecycle {
    create_before_destroy = true
  }
}

# ------------------------------------------------------------------------------
# AWS Batch Job Queue
# ------------------------------------------------------------------------------
resource "aws_batch_job_queue" "this" {
  for_each = var.job_queues

  name                  = "${local.rendered_name}-${each.key}"
  state                 = each.value.state
  priority              = each.value.priority
  scheduling_policy_arn = each.value.scheduling_policy_arn != null ? each.value.scheduling_policy_arn : (var.create_scheduling_policy ? aws_batch_scheduling_policy.this[0].arn : null)

  dynamic "compute_environment_order" {
    for_each = each.value.compute_environments
    content {
      order               = compute_environment_order.key
      compute_environment = lookup(aws_batch_compute_environment.this, compute_environment_order.value, null) != null ? aws_batch_compute_environment.this[compute_environment_order.value].arn : compute_environment_order.value
    }
  }

  tags = merge(local.tags, { Name = "${local.rendered_name}-${each.key}" })
}

# ------------------------------------------------------------------------------
# AWS Batch Job Definition
# ------------------------------------------------------------------------------
resource "aws_batch_job_definition" "this" {
  for_each = local.job_definitions_processed

  name                  = "${local.rendered_name}-${each.key}"
  type                  = each.value.type
  container_properties  = each.value.container_properties
  parameters            = each.value.parameters
  platform_capabilities = each.value.platform_capabilities

  dynamic "retry_strategy" {
    for_each = each.value.retry_strategy != null ? [each.value.retry_strategy] : []
    content {
      attempts = retry_strategy.value.attempts

      dynamic "evaluate_on_exit" {
        for_each = retry_strategy.value.evaluate_on_exit
        content {
          action           = evaluate_on_exit.value.action
          on_exit_code     = evaluate_on_exit.value.on_exit_code
          on_reason        = evaluate_on_exit.value.on_reason
          on_status_reason = evaluate_on_exit.value.on_status_reason
        }
      }
    }
  }

  dynamic "timeout" {
    for_each = each.value.timeout != null ? [each.value.timeout] : []
    content {
      attempt_duration_seconds = timeout.value.attempt_duration_seconds
    }
  }

  tags = merge(local.tags, { Name = "${local.rendered_name}-${each.key}" })
}

# ------------------------------------------------------------------------------
# IAM Role for EventBridge to invoke AWS Batch
# ------------------------------------------------------------------------------
resource "aws_iam_role" "eventbridge_batch" {
  name = "${local.rendered_name}-eb-batch-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "eventbridge_batch" {
  name = "${local.rendered_name}-eb-batch-policy"
  role = aws_iam_role.eventbridge_batch.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "batch:SubmitJob"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eventbridge_batch_custom" {
  for_each = {
    for index, policy_arn in var.custom_eventbridge_policies :
    tostring(index) => policy_arn
  }

  role       = aws_iam_role.eventbridge_batch.name
  policy_arn = each.value
}

# ------------------------------------------------------------------------------
# EventBridge Rules & Targets
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "this" {
  for_each = var.eventbridge_rules

  name                = "${local.rendered_name}-${each.key}"
  description         = each.value.description
  schedule_expression = each.value.schedule_expression
  event_pattern       = each.value.event_pattern
  state               = each.value.state

  tags = merge(local.tags, { Name = "${local.rendered_name}-${each.key}" }, each.value.tags)
}

resource "aws_cloudwatch_event_target" "this" {
  for_each = var.eventbridge_targets

  rule      = aws_cloudwatch_event_rule.this[each.value.rule_name].name
  target_id = each.key
  arn       = lookup(aws_batch_job_queue.this, each.value.job_queue_key, null) != null ? aws_batch_job_queue.this[each.value.job_queue_key].arn : each.value.job_queue_key
  role_arn  = aws_iam_role.eventbridge_batch.arn

  batch_target {
    job_definition = lookup(aws_batch_job_definition.this, each.value.job_definition_key, null) != null ? aws_batch_job_definition.this[each.value.job_definition_key].arn : each.value.job_definition_key
    job_name       = each.value.job_name
    job_attempts   = each.value.attempts
  }

  input = each.value.container_overrides

  dynamic "dead_letter_config" {
    for_each = each.value.dead_letter_arn != null ? [each.value.dead_letter_arn] : []
    content {
      arn = dead_letter_config.value
    }
  }

  dynamic "retry_policy" {
    for_each = each.value.retry_policy != null ? [each.value.retry_policy] : []
    content {
      maximum_event_age_in_seconds = retry_policy.value.maximum_event_age_in_seconds
      maximum_retry_attempts       = retry_policy.value.maximum_retry_attempts
    }
  }
}
