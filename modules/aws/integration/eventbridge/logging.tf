module "log_group" {
  source = "../../observability/log-group"
  count  = local.bus_logging ? 1 : 0

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

resource "aws_cloudwatch_log_resource_policy" "this" {
  count = local.bus_logging ? 1 : 0

  policy_name     = module.naming.names.log_policy
  policy_document = local.log_delivery_policy
}

resource "aws_cloudwatch_log_delivery_source" "this" {
  for_each = local.log_sources

  name         = module.naming.names[each.key]
  log_type     = each.key
  resource_arn = aws_cloudwatch_event_bus.this[0].arn

  tags = merge(module.naming.tags, { Name = module.naming.names[each.key] })
}

resource "aws_cloudwatch_log_delivery_destination" "this" {
  count = local.bus_logging ? 1 : 0

  name = module.naming.names.log_delivery

  delivery_destination_configuration {
    destination_resource_arn = module.log_group[0].arn
  }

  tags = merge(module.naming.tags, { Name = module.naming.names.log_delivery })
}

resource "aws_cloudwatch_log_delivery" "error" {
  count = local.bus_logging ? 1 : 0

  delivery_source_name     = aws_cloudwatch_log_delivery_source.this["ERROR_LOGS"].name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.this[0].arn

  tags = merge(module.naming.tags, { Name = module.naming.names.ERROR_LOGS })

  depends_on = [aws_cloudwatch_log_resource_policy.this]
}

resource "aws_cloudwatch_log_delivery" "info" {
  count = local.bus_logging && contains(local.bus_log_types, "INFO_LOGS") ? 1 : 0

  delivery_source_name     = aws_cloudwatch_log_delivery_source.this["INFO_LOGS"].name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.this[0].arn

  tags = merge(module.naming.tags, { Name = module.naming.names.INFO_LOGS })

  depends_on = [aws_cloudwatch_log_delivery.error]
}

resource "aws_cloudwatch_log_delivery" "trace" {
  count = local.bus_logging && contains(local.bus_log_types, "TRACE_LOGS") ? 1 : 0

  delivery_source_name     = aws_cloudwatch_log_delivery_source.this["TRACE_LOGS"].name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.this[0].arn

  tags = merge(module.naming.tags, { Name = module.naming.names.TRACE_LOGS })

  depends_on = [aws_cloudwatch_log_delivery.info]
}
