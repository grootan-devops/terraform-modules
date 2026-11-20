locals {
  effective_cors = {
    for path, route in var.routes : path => merge(var.cors, try({ for k, v in route.cors : k => v if v != null }, {}))
  }

  explicit_options = toset([for m in values(local.methods) : m.path if m.verb == "OPTIONS"])

  cors_paths = [for path, cors in local.effective_cors : path if cors.enabled && !contains(local.explicit_options, path)]

  operations = {
    for k, m in local.methods : k => merge(
      m.operation_name == null ? {} : { operationId = m.operation_name },
      length(local.parameters[k]) == 0 ? {} : { parameters = local.parameters[k] },
      m.request_model == null ? {} : {
        requestBody = { content = { "application/json" = { schema = { "$ref" = "#/components/schemas/${m.request_model}" } } } }
      },
      { responses = local.responses[k] },
      m.authorizer_key == null ? {} : { security = [{ (m.authorizer_key) = [] }] },
      m.request_validator == null ? {} : { "x-amazon-apigateway-request-validator" = m.request_validator },
      { "x-amazon-apigateway-integration" = local.integrations[k] }
    )
  }

  parameters = {
    for k, m in local.methods : k => values(merge(
      { for match in regexall("\\{([^}+]+)\\+?\\}", m.path) : "path:${match[0]}" => { name = match[0], "in" = "path", required = true, schema = { type = "string" } } },
      {
        for key, required in m.request_parameters : "${split(".", key)[2]}:${join(".", slice(split(".", key), 3, length(split(".", key))))}" => {
          name     = join(".", slice(split(".", key), 3, length(split(".", key))))
          "in"     = try({ querystring = "query", header = "header", path = "path" }[split(".", key)[2]], "query")
          required = required
          schema   = { type = "string" }
        }
      }
    ))
  }

  responses = {
    for k, m in local.methods : k => {
      for status, response in(length(m.method_responses) > 0 ? m.method_responses : { "200" = { response_models = {}, response_parameters = {} } }) : status => merge(
        { description = "${status} response" },
        length([for p in keys(response.response_parameters) : p if split(".", p)[2] == "header"]) == 0 ? {} : {
          headers = { for p in keys(response.response_parameters) : join(".", slice(split(".", p), 3, length(split(".", p)))) => { schema = { type = "string" } } if split(".", p)[2] == "header" }
        },
        length(response.response_models) == 0 ? {} : {
          content = { for content_type, model in response.response_models : content_type => { schema = { "$ref" = "#/components/schemas/${model}" } } }
        }
      )
    }
  }

  integrations = {
    for k, m in local.methods : k => merge(
      { type = lower(m.integration.type) },
      m.integration.type == "MOCK" ? {} : { httpMethod = coalesce(m.integration.http_method, contains(["AWS", "AWS_PROXY"], m.integration.type) ? "POST" : m.verb) },
      m.lambda != null ? { uri = m.lambda.invoke_arn } : m.integration.uri == null ? {} : { uri = m.integration.uri },
      m.integration.connection_type == null ? {} : { connectionType = m.integration.connection_type },
      m.integration.connection_id == null ? {} : { connectionId = m.integration.connection_id },
      m.integration.integration_target == null ? {} : { integrationTarget = m.integration.integration_target },
      m.integration.passthrough_behavior == null ? {} : { passthroughBehavior = lower(m.integration.passthrough_behavior) },
      length(m.integration.request_parameters) == 0 ? {} : { requestParameters = m.integration.request_parameters },
      length(m.integration.request_templates) == 0 ? {} : { requestTemplates = m.integration.request_templates },
      length(m.integration.cache_key_parameters) == 0 ? {} : { cacheKeyParameters = m.integration.cache_key_parameters },
      m.integration.cache_namespace == null ? {} : { cacheNamespace = m.integration.cache_namespace },
      m.integration.content_handling == null ? {} : { contentHandling = m.integration.content_handling },
      m.integration.timeout_milliseconds == null ? {} : { timeoutInMillis = m.integration.timeout_milliseconds },
      m.integration.type == "AWS_PROXY" || length(m.integration_responses) == 0 ? {} : {
        responses = {
          for status, r in m.integration_responses : coalesce(r.selection_pattern, "default") => merge(
            { statusCode = status },
            length(r.response_parameters) == 0 ? {} : { responseParameters = r.response_parameters },
            length(r.response_templates) == 0 ? {} : { responseTemplates = r.response_templates },
            r.content_handling == null ? {} : { contentHandling = r.content_handling }
          )
        }
      }
    )
  }

  cors_operations = {
    for path in local.cors_paths : path => {
      operationId = "CorsOptions"
      responses = {
        "200" = {
          description = "200 response"
          headers     = { for h in concat(["Access-Control-Allow-Origin", "Access-Control-Allow-Headers", "Access-Control-Allow-Methods", "Access-Control-Max-Age"], local.effective_cors[path].allow_credentials ? ["Access-Control-Allow-Credentials"] : []) : h => { schema = { type = "string" } } }
        }
      }
      "x-amazon-apigateway-integration" = {
        type                = "mock"
        passthroughBehavior = "when_no_match"
        requestTemplates    = { "application/json" = jsonencode({ statusCode = 200 }) }
        responses = {
          default = {
            statusCode = "200"
            responseParameters = merge(
              {
                "method.response.header.Access-Control-Allow-Origin"  = "'${local.effective_cors[path].allow_credentials ? local.effective_cors[path].allow_origins[0] : join(",", local.effective_cors[path].allow_origins)}'"
                "method.response.header.Access-Control-Allow-Headers" = "'${join(",", local.effective_cors[path].allow_headers)}'"
                "method.response.header.Access-Control-Allow-Methods" = "'${join(",", local.effective_cors[path].allow_methods)}'"
                "method.response.header.Access-Control-Max-Age"       = "'${local.effective_cors[path].max_age}'"
              },
              local.effective_cors[path].allow_credentials ? { "method.response.header.Access-Control-Allow-Credentials" = "'true'" } : {}
            )
          }
        }
      }
    }
  }

  paths = {
    for path in distinct(concat([for m in values(local.methods) : m.path], local.cors_paths)) : path => merge(
      { for k, m in local.methods : (m.verb == "ANY" ? "x-amazon-apigateway-any-method" : lower(m.verb)) => local.operations[k] if m.path == path },
      contains(local.cors_paths, path) ? { options = local.cors_operations[path] } : {}
    )
  }

  security_schemes = merge(
    {
      for key, a in var.authorizers : key => {
        type                           = "apiKey"
        name                           = reverse(split(".", a.identity_source))[0]
        "in"                           = "header"
        "x-amazon-apigateway-authtype" = "cognito_user_pools"
        "x-amazon-apigateway-authorizer" = {
          type                         = "cognito_user_pools"
          providerARNs                 = a.provider_arns
          identitySource               = a.identity_source
          authorizerResultTtlInSeconds = a.authorizer_result_ttl_in_seconds
        }
      }
    },
    {
      for key, a in var.lambda_authorizers : key => {
        type                           = "apiKey"
        name                           = "Unused"
        "in"                           = "header"
        "x-amazon-apigateway-authtype" = "custom"
        "x-amazon-apigateway-authorizer" = {
          type                         = "request"
          authorizerUri                = a.invoke_arn
          identitySource               = a.identity_source
          authorizerResultTtlInSeconds = a.authorizer_result_ttl_in_seconds
        }
      }
    }
  )

  gateway_response_status = {
    BAD_REQUEST_BODY    = "400"
    UNAUTHORIZED        = "401"
    ACCESS_DENIED       = "403"
    RESOURCE_NOT_FOUND  = "404"
    DEFAULT_5XX         = "500"
    INTEGRATION_FAILURE = "502"
    INTEGRATION_TIMEOUT = "504"
  }

  gateway_response_parameters = merge(
    {
      "gatewayresponse.header.Access-Control-Allow-Origin"  = var.cors.allow_credentials ? "method.request.header.origin" : "'${join(",", var.cors.allow_origins)}'"
      "gatewayresponse.header.Access-Control-Allow-Headers" = "'${join(",", var.cors.allow_headers)}'"
      "gatewayresponse.header.Access-Control-Allow-Methods" = "'${join(",", var.cors.allow_methods)}'"
    },
    var.cors.allow_credentials ? { "gatewayresponse.header.Access-Control-Allow-Credentials" = "'true'" } : {}
  )

  gateway_response_templates = { "application/json" = jsonencode({ message = "$context.error.messageString" }) }

  gateway_responses = {
    for type in distinct(concat(keys(local.gateway_response_status), keys(var.gateway_responses))) : type => {
      statusCode         = try(coalesce(var.gateway_responses[type].status_code, local.gateway_response_status[type]), try(local.gateway_response_status[type], "500"))
      responseParameters = merge(local.gateway_response_parameters, try(var.gateway_responses[type].response_parameters, {}))
      responseTemplates  = try(coalesce(var.gateway_responses[type].response_templates, local.gateway_response_templates), local.gateway_response_templates)
    }
  }

  openapi = merge(
    {
      openapi                                 = "3.0.1"
      info                                    = { title = local.api_name, version = "1.0" }
      paths                                   = local.paths
      "x-amazon-apigateway-gateway-responses" = local.gateway_responses
    },
    length(var.models) + length(local.security_schemes) == 0 ? {} : {
      components = merge(
        length(var.models) == 0 ? {} : { schemas = { for name, schema in var.models : name => jsondecode(schema) } },
        length(local.security_schemes) == 0 ? {} : { securitySchemes = local.security_schemes }
      )
    },
    length(var.request_validators) == 0 ? {} : {
      "x-amazon-apigateway-request-validators" = {
        for name, v in var.request_validators : name => {
          validateRequestBody       = v.validate_request_body
          validateRequestParameters = v.validate_request_parameters
        }
      }
    }
  )
}
