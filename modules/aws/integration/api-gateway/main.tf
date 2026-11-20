module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags
  names = {
    api = { max_length = 255 }
  }
}

module "encryption" {
  source = "../../core/encryption"

  application        = var.application
  environment        = var.environment
  name               = var.name
  purpose            = "apigw"
  tags               = var.tags
  kms                = var.kms
  service_statements = local.kms_service_statements
}

resource "aws_api_gateway_rest_api" "this" {
  name                         = local.api_name
  description                  = coalesce(var.description, "${local.api_name} REST API")
  body                         = jsonencode(local.openapi)
  put_rest_api_mode            = "overwrite"
  binary_media_types           = length(var.binary_media_types) > 0 ? var.binary_media_types : null
  minimum_compression_size     = var.minimum_compression_size
  disable_execute_api_endpoint = var.custom_domain.enabled
  security_policy              = local.security_policy
  endpoint_access_mode         = var.tls.endpoint_access_mode

  endpoint_configuration {
    types = [var.endpoint_type]
  }

  tags = merge(module.naming.tags, { Name = local.api_name })

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = length(setintersection(keys(var.authorizers), keys(var.lambda_authorizers))) == 0
      error_message = "authorizers and lambda_authorizers: keys must differ."
    }

    precondition {
      condition     = alltrue([for m in values(local.methods) : m.authorizer_key == null || contains(concat(keys(var.authorizers), keys(var.lambda_authorizers)), m.authorizer_key)])
      error_message = "routes: authorizer_key not in authorizers or lambda_authorizers."
    }

    precondition {
      condition     = alltrue([for m in values(local.methods) : m.request_model == null || contains(keys(var.models), m.request_model)])
      error_message = "routes: request_model not in models."
    }

    precondition {
      condition     = alltrue([for m in values(local.methods) : m.request_validator == null || contains(keys(var.request_validators), m.request_validator)])
      error_message = "routes: request_validator not in request_validators."
    }

    precondition {
      condition     = alltrue([for c in values(local.effective_cors) : !(c.enabled && c.allow_credentials && contains(c.allow_origins, "*"))])
      error_message = "routes: cors allow_credentials needs explicit origins."
    }
  }
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  description = "${local.api_name} deployment"

  triggers = {
    redeployment = sha1(jsonencode(local.openapi))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "this" {
  rest_api_id           = aws_api_gateway_rest_api.this.id
  deployment_id         = aws_api_gateway_deployment.this.id
  stage_name            = local.stage_name
  description           = var.stage.description
  variables             = var.stage.variables
  cache_cluster_enabled = var.cache_cluster.enabled
  cache_cluster_size    = var.cache_cluster.enabled ? var.cache_cluster.size : null
  client_certificate_id = var.client_certificate_id
  xray_tracing_enabled  = var.tracing.enabled

  access_log_settings {
    destination_arn = module.access_log_group.arn
    format          = coalesce(var.cloudwatch_logs.access_log_format, local.default_access_log_format)
  }

  tags = merge(module.naming.tags, { Name = local.stage_name })
}

resource "aws_api_gateway_method_settings" "this" {
  for_each = local.method_settings

  rest_api_id = aws_api_gateway_rest_api.this.id
  stage_name  = aws_api_gateway_stage.this.stage_name
  method_path = each.key

  settings {
    logging_level                              = each.value.logging_level
    metrics_enabled                            = each.value.metrics_enabled
    data_trace_enabled                         = each.value.data_trace_enabled
    throttling_burst_limit                     = try(each.value.throttling_burst_limit, null)
    throttling_rate_limit                      = try(each.value.throttling_rate_limit, null)
    caching_enabled                            = try(each.value.caching_enabled, null)
    cache_ttl_in_seconds                       = try(each.value.cache_ttl_in_seconds, null)
    cache_data_encrypted                       = try(each.value.caching_enabled, false) || (each.key == "*/*" && var.cache_cluster.enabled) ? true : null
    require_authorization_for_cache_control    = try(each.value.require_authorization_for_cache_control, null)
    unauthorized_cache_control_header_strategy = try(each.value.unauthorized_cache_control_header_strategy, null)
  }

  depends_on = [module.execution_log_group]
}

resource "aws_wafv2_web_acl_association" "this" {
  count = var.waf.enabled ? 1 : 0

  resource_arn = aws_api_gateway_stage.this.arn
  web_acl_arn  = var.waf.web_acl_arn
}
