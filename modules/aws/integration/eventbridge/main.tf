resource "aws_cloudwatch_event_bus" "this" {
  count = var.create_bus ? 1 : 0

  name               = local.target_bus_name
  kms_key_identifier = var.kms_key_arn
  tags               = merge(local.tags, var.bus_tags)
}

resource "aws_cloudwatch_event_rule" "this" {
  for_each = var.rules

  name                = each.key
  description         = each.value.description
  event_bus_name      = local.bus_name
  event_pattern       = each.value.event_pattern
  schedule_expression = each.value.schedule_expression
  state               = each.value.state
  role_arn            = each.value.role_arn
  force_destroy       = each.value.force_destroy
  tags                = merge(local.tags, { Name = "${local.rendered_name}-${each.key}" }, each.value.tags)
}

resource "aws_cloudwatch_event_target" "this" {
  for_each = var.targets

  rule           = aws_cloudwatch_event_rule.this[each.value.rule_name].name
  event_bus_name = local.bus_name
  target_id      = each.key
  arn            = each.value.arn
  role_arn       = each.value.role_arn

  input      = each.value.input
  input_path = each.value.input_path

  dynamic "input_transformer" {
    for_each = each.value.input_transformer != null ? [each.value.input_transformer] : []
    content {
      input_paths    = input_transformer.value.input_paths
      input_template = input_transformer.value.input_template
    }
  }

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

  dynamic "sqs_target" {
    for_each = each.value.sqs_target != null ? [each.value.sqs_target] : []
    content {
      message_group_id = sqs_target.value.message_group_id
    }
  }
}

# Event Bus Policy
resource "aws_cloudwatch_event_bus_policy" "this" {
  count = var.bus_policy != null ? 1 : 0

  policy         = var.bus_policy
  event_bus_name = local.bus_name
}
