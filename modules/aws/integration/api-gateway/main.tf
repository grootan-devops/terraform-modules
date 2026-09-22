resource "terraform_data" "validations" {
  input = local.validation_errors

  lifecycle {
    precondition {
      condition     = length(local.validation_errors) == 0
      error_message = join("\n", local.validation_errors)
    }
  }
}

resource "aws_api_gateway_rest_api" "this" {
  name                         = local.rendered_name
  description                  = local.rendered_description
  binary_media_types           = ["image/png", "image/jpeg", "application/pdf", "multipart/form-data"]
  minimum_compression_size     = var.minimum_compression_size
  disable_execute_api_endpoint = var.custom_domain.enabled
  put_rest_api_mode            = "overwrite"
  body                         = jsonencode(local.openapi_spec)

  endpoint_configuration {
    types           = [upper(var.endpoint_type)]
    ip_address_type = "ipv4"
  }

  tags = local.tags

  depends_on = [terraform_data.validations]
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  description = "Managed deployment for ${local.rendered_description_name}"

  triggers = {
    redeployment = sha1(jsonencode(local.deployment_fingerprint))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_api_gateway_rest_api.this]
}

resource "aws_api_gateway_stage" "this" {
  rest_api_id           = aws_api_gateway_rest_api.this.id
  deployment_id         = aws_api_gateway_deployment.this.id
  stage_name            = local.stage_name
  description           = var.stage.description
  variables             = var.stage.variables
  cache_cluster_enabled = var.stage.cache_cluster_enabled
  cache_cluster_size    = var.stage.cache_cluster_size
  xray_tracing_enabled  = var.tracing_enabled

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.this["api_gateway_access"].arn
    format          = coalesce(var.access_logs.format, local.default_access_log_format)
  }

  tags = merge(local.tags, { Name = local.stage_name })
}

resource "aws_api_gateway_method_settings" "this" {
  for_each = local.effective_method_settings

  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  method_path = each.key

  settings {
    metrics_enabled                            = try(each.value.metrics_enabled, null)
    logging_level                              = try(each.value.logging_level, null)
    data_trace_enabled                         = try(each.value.data_trace_enabled, null)
    throttling_burst_limit                     = try(each.value.throttling_burst_limit, null)
    throttling_rate_limit                      = try(each.value.throttling_rate_limit, null)
    caching_enabled                            = try(each.value.caching_enabled, null)
    cache_ttl_in_seconds                       = try(each.value.cache_ttl_in_seconds, null)
    cache_data_encrypted                       = try(each.value.cache_data_encrypted, null)
    require_authorization_for_cache_control    = try(each.value.require_authorization_for_cache_control, null)
    unauthorized_cache_control_header_strategy = try(each.value.unauthorized_cache_control_header_strategy, null)
  }
}

resource "aws_wafv2_web_acl_association" "this" {
  count = var.waf_web_acl_arn == null ? 0 : 1

  resource_arn = aws_api_gateway_stage.this.arn
  web_acl_arn  = var.waf_web_acl_arn
}

resource "aws_api_gateway_domain_name" "this" {
  count = var.custom_domain.enabled ? 1 : 0

  domain_name              = var.custom_domain.domain_name
  certificate_arn          = upper(var.custom_domain.endpoint_type) == "EDGE" ? var.custom_domain.certificate_arn : null
  regional_certificate_arn = contains(["REGIONAL", "PRIVATE"], upper(var.custom_domain.endpoint_type)) ? var.custom_domain.certificate_arn : null
  security_policy          = var.custom_domain.security_policy
  routing_mode             = var.custom_domain.routing_mode
  endpoint_access_mode     = var.custom_domain.endpoint_access_mode

  endpoint_configuration {
    types           = [upper(var.custom_domain.endpoint_type)]
    ip_address_type = "ipv4"
  }

  depends_on = [terraform_data.validations]

  tags = local.tags
}

resource "aws_api_gateway_base_path_mapping" "this" {
  count = var.custom_domain.enabled && var.custom_domain.create_base_path_mapping ? 1 : 0

  api_id      = aws_api_gateway_rest_api.this.id
  domain_name = aws_api_gateway_domain_name.this[0].domain_name
  base_path   = var.custom_domain.base_path_mapping.base_path
  stage_name  = coalesce(var.custom_domain.base_path_mapping.stage_name, aws_api_gateway_stage.this.stage_name)
}

resource "aws_lambda_permission" "api_gateway_authorizer" {
  for_each = var.lambda_authorizers

  statement_id  = "AllowApiGatewayAuthorizer${replace(each.key, "_", "")}"
  action        = "lambda:InvokeFunction"
  function_name = each.value.lambda_alias_arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"

  lifecycle {
    ignore_changes = [function_name, id, qualifier]
  }
}

resource "aws_lambda_permission" "api_gateway" {
  for_each = local.lambda_permission_configs

  statement_id  = each.value.statement_id
  action        = "lambda:InvokeFunction"
  function_name = each.value.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/${aws_api_gateway_stage.this.stage_name}/${each.value.http_method}${each.value.source_path_suffix}"

  lifecycle {
    ignore_changes = [
      function_name,
      id,
      qualifier
    ]
  }
}
