module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags
  names = {
    api = { max_length = 128 }
  }
}

module "encryption" {
  source = "../../core/encryption"

  application        = var.application
  environment        = var.environment
  name               = var.name
  purpose            = "httpapi"
  tags               = var.tags
  kms                = var.kms
  service_statements = local.kms_service_statements
}

resource "aws_apigatewayv2_api" "this" {
  name                         = local.api_name
  description                  = coalesce(var.description, "${local.api_name} HTTP API")
  protocol_type                = "HTTP"
  ip_address_type              = var.ip_address_type
  disable_execute_api_endpoint = var.domain.enabled

  dynamic "cors_configuration" {
    for_each = var.cors.enabled ? [var.cors] : []

    content {
      allow_origins     = cors_configuration.value.allow_origins
      allow_methods     = cors_configuration.value.allow_methods
      allow_headers     = cors_configuration.value.allow_headers
      expose_headers    = length(cors_configuration.value.expose_headers) > 0 ? cors_configuration.value.expose_headers : null
      allow_credentials = cors_configuration.value.allow_credentials
      max_age           = cors_configuration.value.max_age
    }
  }

  tags = merge(module.naming.tags, { Name = local.api_name })
}

resource "aws_apigatewayv2_stage" "this" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = local.stage_name
  auto_deploy = true

  access_log_settings {
    destination_arn = module.access_log_group.arn
    format          = coalesce(var.cloudwatch_logs.access_log_format, local.access_log_format)
  }

  default_route_settings {
    throttling_burst_limit   = var.throttling.burst_limit
    throttling_rate_limit    = var.throttling.rate_limit
    detailed_metrics_enabled = var.detailed_metrics
  }

  dynamic "route_settings" {
    for_each = local.route_throttling

    content {
      route_key                = route_settings.key
      throttling_burst_limit   = route_settings.value.burst_limit
      throttling_rate_limit    = route_settings.value.rate_limit
      detailed_metrics_enabled = var.detailed_metrics
    }
  }

  tags = merge(module.naming.tags, { Name = "${local.api_name}-default" })

  depends_on = [aws_apigatewayv2_route.this]
}
