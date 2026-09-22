locals {
  rendered_name             = var.name != null && var.name != "" ? "${var.application}-${var.environment}-${var.name}" : "${var.application}-${var.environment}"
  rendered_description_name = var.name != null ? "${var.application} ${var.name}" : "${var.application} ${var.environment}"
  rendered_description      = "REST API Gateway for ${local.rendered_description_name}"
  stage_name                = coalesce(try(var.stage.stage_name, null), var.environment)

  tags = merge(
    {
      Application = var.application
      Environment = var.environment
      Name        = local.rendered_name
    },
    var.tags
  )

  cors_default_config = {
    enabled           = var.cors.enabled
    allow_origins     = var.cors.allow_origins
    allow_methods     = var.cors.allow_methods
    allow_headers     = var.cors.allow_headers
    allow_credentials = var.cors.allow_credentials
    max_age           = var.cors.max_age
  }

  route_cors_overrides = {
    for route_path, route in var.routes : route_path => try(route.cors, null) == null ? {} : {
      for setting_key, setting_value in route.cors : setting_key => setting_value
      if setting_value != null
    }
  }

  effective_cors_configs = {
    for route_path, _ in var.routes : route_path => merge(local.cors_default_config, local.route_cors_overrides[route_path])
  }

  user_method_configs = merge({}, [
    for route_path, route in var.routes : {
      for method_name, method in route.methods : "${upper(method_name)} ${route_path}" => {
        path                  = route_path
        http_method           = upper(method_name)
        is_cors               = false
        authorizer_key        = try(trimspace(method.authorizer_key), "") == "" ? null : trimspace(method.authorizer_key)
        authorization_type    = try(trimspace(method.authorizer_key), "") == "" ? "NONE" : "COGNITO_USER_POOLS"
        request_parameters    = try(method.request_parameters, {})
        request_model_key     = try(method.request_model_key, null)
        request_validator_key = try(method.request_validator_key, null)
        operation_name        = try(method.operation_name, null)
        lambda_function_arn   = try(method.lambda_function_arn, null)
        is_lambda_backed      = upper(coalesce(try(method.integration.type, null), "AWS_PROXY")) != "MOCK" && !contains(["HTTP", "HTTP_PROXY"], upper(coalesce(try(method.integration.type, null), "AWS_PROXY")))
        method_setting_path   = route_path == "/" ? "~1/${upper(method_name)}" : "${trim(route_path, "/")}/${upper(method_name)}"
        method_settings = merge(
          {
            for setting_key, setting_value in {
              throttling_burst_limit = try(route.rate_limiting.burst_limit, null)
              throttling_rate_limit  = try(route.rate_limiting.rate_limit, null)
            } : setting_key => setting_value
            if setting_value != null
          },
          try(route.method_settings, null) == null ? {} : {
            for setting_key, setting_value in route.method_settings : setting_key => setting_value
            if setting_value != null
          },
          {
            for setting_key, setting_value in {
              throttling_burst_limit = try(method.rate_limiting.burst_limit, null)
              throttling_rate_limit  = try(method.rate_limiting.rate_limit, null)
            } : setting_key => setting_value
            if setting_value != null
          },
          try(method.method_settings, null) == null ? {} : {
            for setting_key, setting_value in method.method_settings : setting_key => setting_value
            if setting_value != null
          }
        )
        integration_type = upper(coalesce(try(method.integration.type, null), "AWS_PROXY"))
        integration_http_method = coalesce(
          try(method.integration.integration_http_method, null),
          contains(["AWS", "AWS_PROXY"], upper(coalesce(try(method.integration.type, null), "AWS_PROXY"))) ? "POST" : upper(coalesce(try(method.integration.type, null), "AWS_PROXY")) == "MOCK" ? null : upper(method_name)
        )
        integration_uri = coalesce(
          try(method.integration.uri, null),
          try(method.lambda_function_arn, null) != null && contains(["AWS", "AWS_PROXY"], upper(coalesce(try(method.integration.type, null), "AWS_PROXY"))) ? "arn:${data.aws_partition.current.partition}:apigateway:${data.aws_region.current.region}:lambda:path/2015-03-31/functions/${method.lambda_function_arn}/invocations" : null
        )
        integration_target             = try(method.integration.integration_target, null)
        connection_type                = try(method.integration.connection_type, null)
        connection_id                  = try(method.integration.connection_id, null)
        integration_request_parameters = try(method.integration.request_parameters, {})
        integration_request_templates  = try(method.integration.request_templates, {})
        passthrough_behavior           = try(method.integration.passthrough_behavior, null)
        cache_key_parameters           = try(method.integration.cache_key_parameters, [])
        cache_namespace                = try(method.integration.cache_namespace, null)
        content_handling               = try(method.integration.content_handling, null)
        timeout_milliseconds           = try(method.integration.timeout_milliseconds, null)
        response_transfer_mode         = try(method.integration.response_transfer_mode, null)
        tls_config                     = try(method.integration.tls_config, null)
        method_responses               = try(method.method_responses, {})
        integration_responses          = try(method.integration_responses, {})
        source_path_suffix             = route_path == "/" ? "/" : "/${replace(trim(route_path, "/"), "/\\{[^/]+\\}/", "*")}"
        safe_key                       = replace("${upper(method_name)}_${route_path == "/" ? "root" : trim(route_path, "/")}", "/[^A-Za-z0-9]+/", "_")
      }
    }
  ]...)

  explicit_options_paths = toset([
    for _, method in local.user_method_configs : method.path
    if method.http_method == "OPTIONS"
  ])

  cors_method_configs = {
    for route_path, cors in local.effective_cors_configs : "OPTIONS ${route_path}" => {
      path                           = route_path
      http_method                    = "OPTIONS"
      is_cors                        = true
      authorization_type             = "NONE"
      authorizer_key                 = null
      request_parameters             = {}
      request_model_key              = null
      request_validator_key          = null
      operation_name                 = "CorsOptions"
      lambda_function_arn            = null
      is_lambda_backed               = false
      method_setting_path            = route_path == "/" ? "~1/OPTIONS" : "${trim(route_path, "/")}/OPTIONS"
      method_settings                = {}
      integration_type               = "MOCK"
      integration_http_method        = null
      integration_uri                = null
      integration_target             = null
      connection_type                = null
      connection_id                  = null
      integration_request_parameters = {}
      integration_request_templates = {
        "application/json" = jsonencode({ statusCode = 200 })
      }
      passthrough_behavior   = "WHEN_NO_MATCH"
      cache_key_parameters   = []
      cache_namespace        = null
      content_handling       = null
      timeout_milliseconds   = null
      response_transfer_mode = null
      tls_config             = null
      method_responses = {
        "200" = {
          response_models = {}
          response_parameters = merge({
            "method.response.header.Access-Control-Allow-Origin"  = true
            "method.response.header.Access-Control-Allow-Headers" = true
            "method.response.header.Access-Control-Allow-Methods" = true
            "method.response.header.Access-Control-Max-Age"       = true
            }, cors.allow_credentials ? {
            "method.response.header.Access-Control-Allow-Credentials" = true
          } : {})
        }
      }
      integration_responses = {
        "200" = {
          selection_pattern = null
          response_parameters = merge({
            "method.response.header.Access-Control-Allow-Origin"  = cors.allow_credentials ? "'${cors.allow_origins[0]}'" : "'${join(",", cors.allow_origins)}'"
            "method.response.header.Access-Control-Allow-Headers" = "'${join(",", cors.allow_headers)}'"
            "method.response.header.Access-Control-Allow-Methods" = "'${join(",", cors.allow_methods)}'"
            "method.response.header.Access-Control-Max-Age"       = "'${cors.max_age}'"
            }, cors.allow_credentials ? {
            "method.response.header.Access-Control-Allow-Credentials" = "'true'"
          } : {})
          response_templates = {}
          content_handling   = null
        }
      }
      source_path_suffix = route_path == "/" ? "/" : "/${replace(trim(route_path, "/"), "/\\{[^/]+\\}/", "*")}"
      safe_key           = replace("OPTIONS_${route_path == "/" ? "root" : trim(route_path, "/")}", "/[^A-Za-z0-9]+/", "_")
    }
    if cors.enabled && !contains(local.explicit_options_paths, route_path)
  }

  native_method_configs = merge(local.user_method_configs, local.cors_method_configs)

  route_paths = sort(distinct([
    for _, method in local.native_method_configs : method.path
  ]))

  openapi_param_in = {
    querystring = "query"
    header      = "header"
    path        = "path"
  }

  openapi_path_params = {
    for method_key, method in local.native_method_configs : method_key => [
      for match in regexall("\\{([^}+]+)\\+?\\}", method.path) : {
        name     = match[0]
        in       = "path"
        required = true
        schema   = { type = "string" }
      }
    ]
  }

  openapi_request_params = {
    for method_key, method in local.native_method_configs : method_key => [
      for full_key, required in method.request_parameters : {
        name     = join(".", slice(split(".", full_key), 3, length(split(".", full_key))))
        in       = lookup(local.openapi_param_in, element(split(".", full_key), 2), "query")
        required = required
        schema   = { type = "string" }
      }
    ]
  }

  openapi_parameters = {
    for method_key, method in local.native_method_configs : method_key => values({
      for param in concat(local.openapi_path_params[method_key], local.openapi_request_params[method_key]) :
      "${param.in}:${param.name}" => param
    })
  }

  openapi_response_headers = merge([
    for method_key, method in local.native_method_configs : {
      for status_code, response in method.method_responses : "${method_key}|${status_code}" => {
        for full_key, _enabled in response.response_parameters :
        join(".", slice(split(".", full_key), 3, length(split(".", full_key)))) => { schema = { type = "string" } }
        if element(split(".", full_key), 2) == "header"
      }
    }
  ]...)

  effective_method_responses = {
    for method_key, method in local.native_method_configs : method_key => (
      length(method.method_responses) > 0 ? method.method_responses : {
        "200" = { response_models = {}, response_parameters = {} }
      }
    )
  }

  openapi_responses = {
    for method_key, responses in local.effective_method_responses : method_key => {
      for status_code, response in responses : status_code => merge(
        { description = "${status_code} response" },
        length(lookup(local.openapi_response_headers, "${method_key}|${status_code}", {})) > 0 ? {
          headers = local.openapi_response_headers["${method_key}|${status_code}"]
        } : {},
        length(response.response_models) > 0 ? {
          content = {
            for content_type, model_name in response.response_models : content_type => {
              schema = { "$ref" = "#/components/schemas/${model_name}" }
            }
          }
        } : {}
      )
    }
  }

  openapi_integrations = {
    for method_key, method in local.native_method_configs : method_key => merge(
      { type = lower(method.integration_type) },
      method.integration_http_method != null ? { httpMethod = method.integration_http_method } : {},
      method.integration_uri != null ? { uri = method.integration_uri } : {},
      method.connection_type != null ? { connectionType = upper(method.connection_type) } : {},
      method.connection_id != null ? { connectionId = method.connection_id } : {},
      method.integration_target != null ? { integrationTarget = method.integration_target } : {},
      method.passthrough_behavior != null ? { passthroughBehavior = lower(method.passthrough_behavior) } : {},
      length(method.integration_request_parameters) > 0 ? { requestParameters = method.integration_request_parameters } : {},
      length(method.integration_request_templates) > 0 ? { requestTemplates = method.integration_request_templates } : {},
      length(method.cache_key_parameters) > 0 ? { cacheKeyParameters = method.cache_key_parameters } : {},
      method.cache_namespace != null ? { cacheNamespace = method.cache_namespace } : {},
      method.content_handling != null ? { contentHandling = method.content_handling } : {},
      method.timeout_milliseconds != null ? { timeoutInMillis = method.timeout_milliseconds } : {},
      method.tls_config != null ? { tlsConfig = { insecureSkipVerification = method.tls_config.insecure_skip_verification } } : {},
      method.integration_type != "AWS_PROXY" && length(method.integration_responses) > 0 ? {
        responses = {
          for status_code, response in method.integration_responses :
          (response.selection_pattern == null ? "default" : response.selection_pattern) => merge(
            { statusCode = tostring(status_code) },
            length(response.response_parameters) > 0 ? { responseParameters = response.response_parameters } : {},
            length(response.response_templates) > 0 ? { responseTemplates = response.response_templates } : {},
            response.content_handling != null ? { contentHandling = response.content_handling } : {}
          )
        }
      } : {}
    )
  }

  openapi_operations = {
    for method_key, method in local.native_method_configs : method_key => merge(
      !method.is_cors && method.operation_name != null ? { operationId = method.operation_name } : {},
      length(local.openapi_parameters[method_key]) > 0 ? { parameters = local.openapi_parameters[method_key] } : {},
      method.request_model_key != null ? {
        requestBody = {
          content = {
            "application/json" = { schema = { "$ref" = "#/components/schemas/${var.models[method.request_model_key].name}" } }
          }
        }
      } : {},
      { responses = local.openapi_responses[method_key] },
      method.authorizer_key != null ? { security = [{ (method.authorizer_key) = [] }] } : {},
      method.request_validator_key != null ? {
        "x-amazon-apigateway-request-validator" = var.request_validators[method.request_validator_key].name
      } : {},
      { "x-amazon-apigateway-integration" = local.openapi_integrations[method_key] }
    )
  }

  openapi_paths = {
    for route_path in local.route_paths : route_path => {
      for method_key, method in local.native_method_configs :
      (method.http_method == "ANY" ? "x-amazon-apigateway-any-method" : lower(method.http_method)) => local.openapi_operations[method_key]
      if method.path == route_path
    }
  }

  openapi_security_schemes = merge(
    {
      for key, authorizer in var.authorizers : key => merge(
        {
          type                           = "apiKey"
          name                           = element(split(".", coalesce(authorizer.identity_source, "method.request.header.Authorization")), length(split(".", coalesce(authorizer.identity_source, "method.request.header.Authorization"))) - 1)
          in                             = "header"
          "x-amazon-apigateway-authtype" = "cognito_user_pools"
          "x-amazon-apigateway-authorizer" = merge(
            {
              type         = "cognito_user_pools"
              providerARNs = authorizer.provider_arns
            },
            authorizer.identity_source != null ? { identitySource = authorizer.identity_source } : {},
            authorizer.authorizer_result_ttl_in_seconds != null ? { authorizerResultTtlInSeconds = authorizer.authorizer_result_ttl_in_seconds } : {}
          )
        }
      )
    },
    {
      for key, authorizer in var.lambda_authorizers : key => {
        type                           = "apiKey"
        name                           = "Authorization"
        in                             = "header"
        "x-amazon-apigateway-authtype" = "custom"
        "x-amazon-apigateway-authorizer" = {
          type                         = "request"
          authorizerUri                = "arn:${data.aws_partition.current.partition}:apigateway:${data.aws_region.current.region}:lambda:path/2015-03-31/functions/${authorizer.lambda_alias_arn}/invocations"
          identitySource               = authorizer.identity_source
          authorizerResultTtlInSeconds = authorizer.authorizer_result_ttl_in_seconds
        }
      }
    }
  )

  openapi_components = merge(
    length(var.models) > 0 ? { schemas = { for key, model in var.models : model.name => jsondecode(model.schema) } } : {},
    (length(var.authorizers) > 0 || length(var.lambda_authorizers) > 0) ? { securitySchemes = local.openapi_security_schemes } : {}
  )

  openapi_spec = merge(
    {
      openapi = "3.0.1"
      info = {
        title       = local.rendered_name
        description = local.rendered_description
        version     = "1.0"
      }
      paths                                   = local.openapi_paths
      "x-amazon-apigateway-gateway-responses" = local.openapi_gateway_responses
    },
    length(local.openapi_components) > 0 ? { components = local.openapi_components } : {},
    length(var.request_validators) > 0 ? {
      "x-amazon-apigateway-request-validators" = {
        for key, validator in var.request_validators : validator.name => {
          validateRequestBody       = validator.validate_request_body
          validateRequestParameters = validator.validate_request_parameters
        }
      }
    } : {}
  )

  gateway_responses = {
    BAD_REQUEST_BODY    = "400"
    UNAUTHORIZED        = "401"
    ACCESS_DENIED       = "403"
    RESOURCE_NOT_FOUND  = "404"
    DEFAULT_5XX         = "500"
    INTEGRATION_FAILURE = "502"
    INTEGRATION_TIMEOUT = "504"
  }

  gateway_response_templates = {
    "application/json" = jsonencode({
      message = "$context.error.messageString"
    })
  }

  gateway_response_parameters = merge(
    {
      "gatewayresponse.header.Access-Control-Allow-Origin"  = var.cors.allow_credentials ? "method.request.header.origin" : "'${join(",", var.cors.allow_origins)}'"
      "gatewayresponse.header.Access-Control-Allow-Headers" = "'${join(",", var.cors.allow_headers)}'"
      "gatewayresponse.header.Access-Control-Allow-Methods" = "'${join(",", var.cors.allow_methods)}'"
    },
    var.cors.allow_credentials ? {
      "gatewayresponse.header.Access-Control-Allow-Credentials" = "'true'"
    } : {}
  )

  default_openapi_gateway_responses = {
    for response_type, status_code in local.gateway_responses : response_type => {
      statusCode         = status_code
      responseParameters = local.gateway_response_parameters
      responseTemplates  = local.gateway_response_templates
    }
  }

  custom_openapi_gateway_responses = {
    for response_type, config in var.gateway_responses : response_type => {
      statusCode         = coalesce(config.status_code, lookup(local.gateway_responses, response_type, "500"))
      responseParameters = merge(local.gateway_response_parameters, coalesce(config.response_parameters, {}))
      responseTemplates  = coalesce(config.response_templates, local.gateway_response_templates)
    }
  }

  openapi_gateway_responses = merge(
    local.default_openapi_gateway_responses,
    local.custom_openapi_gateway_responses
  )

  default_access_log_format = jsonencode({
    requestId               = "$context.requestId"
    extendedRequestId       = "$context.extendedRequestId"
    sourceIp                = "$context.identity.sourceIp"
    requestTime             = "$context.requestTime"
    protocol                = "$context.protocol"
    httpMethod              = "$context.httpMethod"
    resourcePath            = "$context.path"
    status                  = "$context.status"
    responseLength          = "$context.responseLength"
    responseLatency         = "$context.responseLatency"
    integrationLatency      = "$context.integrationLatency"
    integrationStatus       = "$context.integrationStatus"
    errorMessage            = "$context.error.message"
    integrationErrorMessage = "$context.integrationErrorMessage"
    authorizerPrincipalId   = "$context.authorizer.claims.sub"
    authorizerError         = "$context.authorizer.error"
    accountId               = "$context.accountId"
    apiId                   = "$context.apiId"
    caller                  = "$context.identity.caller"
    userAgent               = "$context.identity.userAgent"
  })

  global_rate_limiting_settings = {
    for setting_key, setting_value in {
      throttling_burst_limit = try(var.rate_limiting.burst_limit, null)
      throttling_rate_limit  = try(var.rate_limiting.rate_limit, null)
    } : setting_key => setting_value
    if setting_value != null
  }

  global_method_settings = {
    for setting_key, setting_value in var.method_settings : setting_key => setting_value
    if setting_value != null
  }

  global_effective_method_settings = merge(local.global_rate_limiting_settings, local.global_method_settings)

  global_method_settings_by_path = length(local.global_effective_method_settings) > 0 ? {
    "*/*" = local.global_effective_method_settings
  } : {}

  route_method_settings = {
    for _, method in local.user_method_configs : method.method_setting_path => merge(local.global_effective_method_settings, method.method_settings)
    if length(method.method_settings) > 0
  }

  effective_method_settings = {
    for method_path in toset(concat(keys(local.global_method_settings_by_path), keys(local.route_method_settings))) : method_path => merge(
      try(local.global_method_settings_by_path[method_path], {}),
      try(local.route_method_settings[method_path], {})
    )
  }

  lambda_permission_configs = {
    for method_key, method in local.native_method_configs : method_key => {
      function_name      = method.lambda_function_arn
      http_method        = method.http_method
      source_path_suffix = method.source_path_suffix
      statement_id       = "AllowApiGateway${substr(replace(local.rendered_name, "/[^A-Za-z0-9_-]+/", "_"), 0, 32)}${substr(method.safe_key, 0, 32)}${substr(sha1("${local.rendered_name} ${method_key}"), 0, 12)}"
    }
    if !method.is_cors &&
    method.is_lambda_backed
  }

  validation_errors = concat(
    [
      for key, authorizer in var.authorizers : "authorizers[\"${key}\"].provider_arns must be set."
      if length(try(authorizer.provider_arns, [])) == 0
    ],
    [
      for method_key, method in local.user_method_configs : "routes method ${method_key} references an unknown authorizer_key."
      if try(method.authorizer_key != null && !contains(keys(var.authorizers), method.authorizer_key) && !contains(keys(var.lambda_authorizers), method.authorizer_key), false)
    ],
    [
      for method_key, method in local.user_method_configs : "routes method ${method_key} references an unknown request_validator_key."
      if try(method.request_validator_key != null && !contains(keys(var.request_validators), method.request_validator_key), false)
    ],
    [
      for method_key, method in local.user_method_configs : "routes method ${method_key} references an unknown request_model_key."
      if try(method.request_model_key != null && !contains(keys(var.models), method.request_model_key), false)
    ],
    [
      for method_key, method in local.user_method_configs : "routes method ${method_key} requires lambda_function_arn for AWS_PROXY integrations."
      if method.integration_type == "AWS_PROXY" && method.lambda_function_arn == null
    ],
    [
      for method_key, method in local.user_method_configs : "routes method ${method_key} requires integration.uri unless it is a MOCK integration or a Lambda-backed AWS/AWS_PROXY integration."
      if !contains(["MOCK"], method.integration_type) && (method.integration_uri == null || method.integration_uri == "")
    ],
    [
      for route_path, cors in local.effective_cors_configs : "routes[\"${route_path}\"].cors.allow_credentials cannot be true when allow_origins contains *."
      if cors.enabled && cors.allow_credentials && contains(cors.allow_origins, "*")
    ],
    var.custom_domain.enabled && try(var.custom_domain.domain_name, null) == null ? [
      "custom_domain.domain_name must be set when custom_domain.enabled is true."
    ] : [],
    var.custom_domain.enabled && !contains(["REGIONAL", "EDGE", "PRIVATE"], upper(var.custom_domain.endpoint_type)) ? [
      "custom_domain.endpoint_type must be REGIONAL, EDGE, or PRIVATE."
    ] : [],
    var.custom_domain.enabled && try(var.custom_domain.certificate_arn, null) == null ? [
      "custom_domain.certificate_arn must be set when custom_domain.enabled is true."
    ] : []
  )

  deployment_fingerprint = {
    openapi = local.openapi_spec
  }
}
