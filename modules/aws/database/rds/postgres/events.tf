resource "aws_db_event_subscription" "this" {
  for_each = local.event_subscriptions

  name             = "${local.identifier}-${each.key}"
  sns_topic        = var.event_subscription.sns_topic_arn
  source_type      = each.value.source_type
  source_ids       = [each.value.source_id]
  event_categories = each.value.categories
  enabled          = true

  tags = merge(module.naming.tags, { Name = "${local.identifier}-${each.key}" })
}
