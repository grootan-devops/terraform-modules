locals {
  security_policy       = coalesce(var.tls.security_policy, var.endpoint_type == "EDGE" ? "SecurityPolicy_TLS12_PFS_2025_EDGE" : "SecurityPolicy_TLS13_1_2_PFS_PQ_2025_09")
  api_name              = module.naming.names.api
  stage_name            = coalesce(var.stage.name, var.environment)
  arn_prefix            = "arn:${module.naming.partition}"
  log_arn_prefix        = "${local.arn_prefix}:logs:${module.naming.region}:${module.naming.account_id}:log-group"
  kms_key_arn           = module.encryption.key_arn
  log_kms_key_arn       = try(coalesce(var.cloudwatch_logs.kms_key_arn, local.kms_key_arn), null)
  access_log_group_name = "/aws/apigateway/${local.api_name}/${local.stage_name}/access"
  execution_log_group   = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.this.id}/${local.stage_name}"

  kms_service_statements = [{
    sid        = "AllowCloudWatchLogs"
    actions    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    principals = { Service = ["logs.${module.naming.region}.${module.naming.dns_suffix}"] }
    conditions = [{
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["${local.log_arn_prefix}:${local.access_log_group_name}", "${local.log_arn_prefix}:${local.execution_log_group}"]
    }]
  }]

  methods = merge({}, [
    for path, route in var.routes : {
      for verb, m in route.methods : "${verb} ${path}" => merge(m, {
        path           = path
        verb           = verb
        route_settings = route.method_settings
        settings_path  = path == "/" ? "~1/${verb}" : "${trimprefix(path, "/")}/${verb}"
        source_path    = path == "/" ? "/" : replace(path, "/\\{[^/]+\\}/", "*")
        slug           = "${substr(replace("${local.api_name}-${verb}${path}", "/[^a-zA-Z0-9_-]+/", "-"), 0, 80)}-${substr(md5("${local.api_name} ${verb} ${path}"), 0, 8)}"
      })
    }
  ]...)

  lambda_methods = { for k, m in local.methods : k => m if m.lambda != null }

  base_method_settings = {
    logging_level      = var.execution_logging.enabled ? var.execution_logging.logging_level : "OFF"
    metrics_enabled    = var.execution_logging.metrics_enabled
    data_trace_enabled = var.execution_logging.enabled && var.execution_logging.data_trace_enabled
  }

  stage_method_settings = merge(local.base_method_settings, { for k, v in var.method_settings : k => v if v != null })

  method_overrides = {
    for k, m in local.methods : m.settings_path => merge(
      local.stage_method_settings,
      try({ for s, v in m.route_settings : s => v if v != null }, {}),
      try({ for s, v in m.method_settings : s => v if v != null }, {})
    ) if m.route_settings != null || m.method_settings != null
  }

  method_settings = merge({ "*/*" = local.stage_method_settings }, local.method_overrides)

  default_access_log_format = jsonencode({
    requestId               = "$context.requestId"
    extendedRequestId       = "$context.extendedRequestId"
    sourceIp                = "$context.identity.sourceIp"
    requestTime             = "$context.requestTime"
    protocol                = "$context.protocol"
    httpMethod              = "$context.httpMethod"
    resourcePath            = "$context.resourcePath"
    path                    = "$context.path"
    status                  = "$context.status"
    responseLength          = "$context.responseLength"
    responseLatency         = "$context.responseLatency"
    integrationLatency      = "$context.integrationLatency"
    integrationStatus       = "$context.integrationStatus"
    errorMessage            = "$context.error.message"
    integrationErrorMessage = "$context.integrationErrorMessage"
    authorizerError         = "$context.authorizer.error"
    principalId             = "$context.authorizer.principalId"
    accountId               = "$context.accountId"
    apiId                   = "$context.apiId"
    stage                   = "$context.stage"
    userAgent               = "$context.identity.userAgent"
  })
}
