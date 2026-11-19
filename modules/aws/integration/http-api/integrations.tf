resource "aws_apigatewayv2_integration" "this" {
  for_each = local.integrations

  api_id                 = aws_apigatewayv2_api.this.id
  description            = var.integrations[each.key].description
  integration_type       = each.value.integration_type
  integration_uri        = each.value.integration_uri
  integration_method     = each.value.integration_method
  payload_format_version = each.value.payload_format_version
  connection_type        = each.value.connection_type
  connection_id          = each.value.connection_type == "VPC_LINK" ? try(aws_apigatewayv2_vpc_link.this[0].id, null) : null
  timeout_milliseconds   = var.integrations[each.key].timeout_milliseconds
  request_parameters     = length(var.integrations[each.key].request_parameters) > 0 ? var.integrations[each.key].request_parameters : null

  dynamic "tls_config" {
    for_each = each.value.tls_server_names

    content {
      server_name_to_verify = tls_config.value
    }
  }
}

resource "aws_apigatewayv2_authorizer" "this" {
  for_each = var.authorizers

  api_id                            = aws_apigatewayv2_api.this.id
  name                              = each.key
  authorizer_type                   = each.value.jwt != null ? "JWT" : "REQUEST"
  identity_sources                  = each.value.jwt != null ? ["$request.header.Authorization"] : try(length(each.value.lambda.identity_sources) > 0 ? each.value.lambda.identity_sources : null, null)
  authorizer_uri                    = each.value.jwt != null ? null : "${local.arn_prefix}:apigateway:${module.naming.region}:lambda:path/2015-03-31/functions/${try(each.value.lambda.function_arn, "")}/invocations"
  authorizer_payload_format_version = try(each.value.lambda.payload_format_version, null)
  authorizer_result_ttl_in_seconds  = try(each.value.lambda.result_ttl_seconds, null)
  enable_simple_responses           = try(each.value.lambda.simple_responses, null)

  dynamic "jwt_configuration" {
    for_each = each.value.jwt != null ? [each.value.jwt] : []

    content {
      issuer   = jwt_configuration.value.issuer
      audience = jwt_configuration.value.audience
    }
  }
}

resource "aws_apigatewayv2_route" "this" {
  for_each = var.routes

  api_id               = aws_apigatewayv2_api.this.id
  route_key            = each.key
  target               = "integrations/${try(aws_apigatewayv2_integration.this[each.value.integration].id, "")}"
  authorization_type   = each.value.authorizer != null ? (try(var.authorizers[each.value.authorizer].jwt != null, false) ? "JWT" : "CUSTOM") : each.value.authorization
  authorizer_id        = each.value.authorizer != null ? try(aws_apigatewayv2_authorizer.this[each.value.authorizer].id, null) : null
  authorization_scopes = length(each.value.authorization_scopes) > 0 ? each.value.authorization_scopes : null
}

resource "aws_lambda_permission" "integrations" {
  for_each = local.lambda_integrations

  statement_id  = "${substr(replace("${local.api_name}-${each.key}", "/[^a-zA-Z0-9_-]+/", "-"), 0, 80)}-${substr(md5("${local.api_name} integration ${each.key}"), 0, 8)}"
  action        = "lambda:InvokeFunction"
  function_name = join(":", slice(split(":", each.value), 0, min(7, length(split(":", each.value)))))
  qualifier     = try(split(":", each.value)[7], null)
  principal     = local.apigateway_principal
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*"
}

resource "aws_lambda_permission" "authorizers" {
  for_each = local.lambda_authorizers

  statement_id  = "${substr(replace("${local.api_name}-authorizer-${each.key}", "/[^a-zA-Z0-9_-]+/", "-"), 0, 80)}-${substr(md5("${local.api_name} authorizer ${each.key}"), 0, 8)}"
  action        = "lambda:InvokeFunction"
  function_name = join(":", slice(split(":", each.value.function_arn), 0, min(7, length(split(":", each.value.function_arn)))))
  qualifier     = try(split(":", each.value.function_arn)[7], null)
  principal     = local.apigateway_principal
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/authorizers/${aws_apigatewayv2_authorizer.this[each.key].id}"
}
