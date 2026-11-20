resource "aws_apigatewayv2_domain_name" "this" {
  count = var.domain.enabled ? 1 : 0

  domain_name = var.domain.name

  domain_name_configuration {
    certificate_arn = var.domain.certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = var.domain.security_policy
    ip_address_type = var.ip_address_type
  }

  dynamic "mutual_tls_authentication" {
    for_each = var.domain.mutual_tls.enabled ? [var.domain.mutual_tls] : []

    content {
      truststore_uri     = mutual_tls_authentication.value.truststore_uri
      truststore_version = mutual_tls_authentication.value.truststore_version
    }
  }

  tags = merge(module.naming.tags, { Name = var.domain.name })
}

resource "aws_apigatewayv2_api_mapping" "this" {
  count = var.domain.enabled ? 1 : 0

  api_id          = aws_apigatewayv2_api.this.id
  domain_name     = aws_apigatewayv2_domain_name.this[0].id
  stage           = aws_apigatewayv2_stage.this.id
  api_mapping_key = var.domain.base_path
}
