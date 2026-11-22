locals {
  api_name              = module.naming.names.api
  stage_name            = "$default"
  arn_prefix            = "arn:${module.naming.partition}"
  kms_key_arn           = module.encryption.key_arn
  log_kms_key_arn       = try(coalesce(var.cloudwatch_logs.kms_key_arn, local.kms_key_arn), null)
  access_log_group_name = "/aws/apigateway/${local.api_name}/default/access"
  access_log_group_arn  = "${local.arn_prefix}:logs:${module.naming.region}:${module.naming.account_id}:log-group:${local.access_log_group_name}"
  apigateway_principal  = "apigateway.${module.naming.dns_suffix}"

  kms_service_statements = [{
    sid        = "AllowCloudWatchLogs"
    actions    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    principals = { Service = ["logs.${module.naming.region}.${module.naming.dns_suffix}"] }
    conditions = [{ test = "ArnLike", variable = "kms:EncryptionContext:aws:logs:arn", values = [local.access_log_group_arn] }]
  }]

  integrations = {
    for k, i in var.integrations : k => {
      integration_type       = i.type == "lambda" ? "AWS_PROXY" : "HTTP_PROXY"
      integration_uri        = i.type == "lambda" ? try(i.lambda.function_arn, null) : i.type == "http" ? i.uri : i.listener_arn
      integration_method     = i.type == "lambda" ? "POST" : i.method
      payload_format_version = i.type == "lambda" ? "2.0" : "1.0"
      connection_type        = i.type == "private" ? "VPC_LINK" : "INTERNET"
      tls_server_names       = i.type == "private" ? [i.tls_server_name] : []
    }
  }

  lambda_integrations = { for k, i in var.integrations : k => i.lambda.function_arn if i.type == "lambda" && i.lambda != null }
  lambda_authorizers  = { for k, a in var.authorizers : k => a.lambda if a.lambda != null }

  route_throttling = { for k, r in var.routes : k => r.throttling if r.throttling != null }

  vpc_link_security_group = var.vpc_link.enabled && var.vpc_link.security_group.create
  vpc_link_security_group_ids = concat(
    local.vpc_link_security_group ? [module.vpc_link_security_group[0].id] : [],
    var.vpc_link.security_group.additional_security_group_ids
  )

  vpc_link_egress_rules = merge(
    { for i, cidr in var.vpc_link.security_group.egress_cidr_blocks : "cidr-${i}" => { description = "Outbound to ${cidr}", ip_protocol = "-1", cidr_ipv4 = cidr } },
    { for i, sg in var.vpc_link.security_group.egress_security_group_ids : "sg-${i}" => { description = "Outbound to a security group", ip_protocol = "-1", referenced_security_group_id = sg } }
  )

  access_log_format = jsonencode({
    requestId               = "$context.requestId"
    extendedRequestId       = "$context.extendedRequestId"
    ip                      = "$context.identity.sourceIp"
    requestTime             = "$context.requestTime"
    httpMethod              = "$context.httpMethod"
    routeKey                = "$context.routeKey"
    path                    = "$context.path"
    status                  = "$context.status"
    protocol                = "$context.protocol"
    responseLength          = "$context.responseLength"
    responseLatency         = "$context.responseLatency"
    integrationLatency      = "$context.integrationLatency"
    integrationErrorMessage = "$context.integrationErrorMessage"
    authorizerError         = "$context.authorizer.error"
    userAgent               = "$context.identity.userAgent"
  })
}
