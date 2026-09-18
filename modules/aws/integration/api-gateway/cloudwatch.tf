locals {
  enabled_cloudwatch_log_groups = toset([
    "api_gateway_access"
  ])

  cloudwatch_log_name_by_type = tomap({
    api_gateway_access = try(var.stage.stage_name, null) != null ? (
      "/aws/apigateway/${local.rendered_name}/${local.stage_name}/access"
    ) : "/aws/apigateway/${local.rendered_name}/access"
  })

  cloudwatch_log_retention_by_type = tomap({
    api_gateway_access = var.access_logs.retention_in_days
  })
}

resource "aws_cloudwatch_log_group" "this" {
  for_each = local.enabled_cloudwatch_log_groups

  name                        = local.cloudwatch_log_name_by_type[each.key]
  retention_in_days           = local.cloudwatch_log_retention_by_type[each.key]
  kms_key_id                  = coalesce(var.access_logs.kms_key_id, var.kms_key_arn)
  log_group_class             = var.access_logs.log_group_class
  deletion_protection_enabled = true

  tags = merge(local.tags, { Name = "/aws/apigateway/${local.rendered_name}" })
}
