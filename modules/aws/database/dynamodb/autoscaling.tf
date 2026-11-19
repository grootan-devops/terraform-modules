resource "aws_appautoscaling_target" "this" {
  for_each = local.autoscaling_targets

  service_namespace  = "dynamodb"
  resource_id        = "table/${aws_dynamodb_table.this.name}${each.value.resource_suffix}"
  scalable_dimension = each.value.dimension
  min_capacity       = each.value.min_capacity
  max_capacity       = each.value.max_capacity

  tags = merge(module.naming.tags, { Name = "${local.table_name}-${each.key}" })
}

resource "aws_appautoscaling_policy" "this" {
  for_each = local.autoscaling_targets

  name               = "${local.table_name}-${each.key}"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this[each.key].service_namespace
  resource_id        = aws_appautoscaling_target.this[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.this[each.key].scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = var.autoscaling.target_utilization
    scale_in_cooldown  = var.autoscaling.scale_in_cooldown
    scale_out_cooldown = var.autoscaling.scale_out_cooldown

    predefined_metric_specification {
      predefined_metric_type = each.value.metric
    }
  }
}
