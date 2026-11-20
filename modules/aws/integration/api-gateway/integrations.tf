resource "aws_lambda_permission" "routes" {
  for_each = local.lambda_methods

  statement_id  = each.value.slug
  action        = "lambda:InvokeFunction"
  function_name = join(":", slice(split(":", each.value.lambda.alias_arn), 0, 7))
  qualifier     = split(":", each.value.lambda.alias_arn)[7]
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/${aws_api_gateway_stage.this.stage_name}/${each.value.verb == "ANY" ? "*" : each.value.verb}${each.value.source_path}"
}

resource "aws_lambda_permission" "authorizers" {
  for_each = var.lambda_authorizers

  statement_id  = "${substr(replace("${local.api_name}-authorizer-${each.key}", "/[^a-zA-Z0-9_-]+/", "-"), 0, 80)}-${substr(md5("${local.api_name} authorizer ${each.key}"), 0, 8)}"
  action        = "lambda:InvokeFunction"
  function_name = join(":", slice(split(":", each.value.alias_arn), 0, 7))
  qualifier     = split(":", each.value.alias_arn)[7]
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/authorizers/*"
}

resource "aws_api_gateway_domain_name" "this" {
  count = var.custom_domain.enabled ? 1 : 0

  domain_name              = var.custom_domain.domain_name
  regional_certificate_arn = var.custom_domain.certificate_arn
  security_policy          = var.tls.domain_security_policy
  endpoint_access_mode     = var.tls.endpoint_access_mode

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = merge(module.naming.tags, { Name = var.custom_domain.domain_name })
}

resource "aws_api_gateway_base_path_mapping" "this" {
  count = var.custom_domain.enabled ? 1 : 0

  api_id      = aws_api_gateway_rest_api.this.id
  domain_name = aws_api_gateway_domain_name.this[0].domain_name
  base_path   = var.custom_domain.base_path
  stage_name  = aws_api_gateway_stage.this.stage_name
}
