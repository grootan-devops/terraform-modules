mock_provider "aws" {
  # The region and partition are interpolated into integration and authorizer
  # URIs, so they need real values for the OpenAPI assertions.
  mock_data "aws_region" {
    defaults = {
      name   = "us-west-2"
      region = "us-west-2"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition          = "aws"
      dns_suffix         = "amazonaws.com"
      reverse_dns_prefix = "com.amazonaws"
    }
  }

  # The provider validates ARN-typed arguments, so computed ARNs that feed
  # other resources need ARN-shaped mock values.
  mock_resource "aws_api_gateway_rest_api" {
    defaults = {
      id               = "a1b2c3d4e5"
      root_resource_id = "r00tid0001"
      arn              = "arn:aws:apigateway:us-west-2::/restapis/a1b2c3d4e5"
      execution_arn    = "arn:aws:execute-api:us-west-2:123456789012:a1b2c3d4e5"
    }
  }

  mock_resource "aws_api_gateway_stage" {
    defaults = {
      arn           = "arn:aws:apigateway:us-west-2::/restapis/a1b2c3d4e5/stages/prod"
      execution_arn = "arn:aws:execute-api:us-west-2:123456789012:a1b2c3d4e5/prod"
      invoke_url    = "https://a1b2c3d4e5.execute-api.us-west-2.amazonaws.com/prod"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-west-2:123456789012:log-group:/aws/apigateway/core-prod-api/access"
    }
  }
}

variables {
  application = "core"
  environment = "prod"
  name        = "api"
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
}

# ------------------------------------------------------------------------------
# Naming
# ------------------------------------------------------------------------------
run "verify_rendered_names" {
  command = plan

  assert {
    condition     = aws_api_gateway_rest_api.this.name == "core-prod-api"
    error_message = "REST API name did not match <application>-<environment>-<name>."
  }

  assert {
    condition     = aws_api_gateway_rest_api.this.description == "REST API Gateway for core api"
    error_message = "REST API description did not use the application and name."
  }

  assert {
    condition     = jsondecode(aws_api_gateway_rest_api.this.body).info.title == "core-prod-api"
    error_message = "OpenAPI info.title did not use the rendered name."
  }

  assert {
    condition     = aws_api_gateway_stage.this.stage_name == "prod"
    error_message = "Stage name did not default to the environment."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this["api_gateway_access"].name == "/aws/apigateway/core-prod-api/access"
    error_message = "Access log group name did not match /aws/apigateway/<rendered name>/access."
  }

  assert {
    condition     = aws_api_gateway_deployment.this.description == "Managed deployment for core api"
    error_message = "Deployment description did not use the application and name."
  }

  assert {
    condition     = output.stage_name == "prod"
    error_message = "stage_name output did not return the managed stage name."
  }
}

run "verify_name_fallback_when_null" {
  command = plan

  variables {
    name = null
  }

  assert {
    condition     = aws_api_gateway_rest_api.this.name == "core-prod"
    error_message = "REST API name did not fall back to <application>-<environment> when name is null."
  }

  assert {
    condition     = aws_api_gateway_rest_api.this.description == "REST API Gateway for core prod"
    error_message = "REST API description did not fall back to the application and environment when name is null."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this["api_gateway_access"].name == "/aws/apigateway/core-prod/access"
    error_message = "Access log group name did not use the fallback rendered name when name is null."
  }
}

run "verify_name_fallback_when_empty" {
  command = plan

  variables {
    name = ""
  }

  assert {
    condition     = aws_api_gateway_rest_api.this.name == "core-prod"
    error_message = "REST API name did not fall back to <application>-<environment> when name is empty."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this["api_gateway_access"].name == "/aws/apigateway/core-prod/access"
    error_message = "Access log group name did not use the fallback rendered name when name is empty."
  }
}

run "verify_custom_stage_name" {
  command = plan

  variables {
    stage = {
      stage_name = "v1"
    }
  }

  assert {
    condition     = aws_api_gateway_stage.this.stage_name == "v1"
    error_message = "stage.stage_name was not applied to the stage."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this["api_gateway_access"].name == "/aws/apigateway/core-prod-api/v1/access"
    error_message = "Access log group name did not include the custom stage name."
  }

  assert {
    condition     = aws_api_gateway_stage.this.tags["Name"] == "v1"
    error_message = "Stage Name tag did not use the custom stage name."
  }
}

# ------------------------------------------------------------------------------
# Tags
# ------------------------------------------------------------------------------
run "verify_governance_and_caller_tags" {
  command = plan

  variables {
    tags = {
      CostCenter = "platform"
      Owner      = "team-core"
    }
  }

  assert {
    condition = alltrue([
      for tags in [
        aws_api_gateway_rest_api.this.tags,
        aws_api_gateway_stage.this.tags,
        aws_cloudwatch_log_group.this["api_gateway_access"].tags,
        ] : (
        tags["Application"] == "core" &&
        tags["Environment"] == "prod"
      )
    ])
    error_message = "Application and Environment governance tags were not set on every taggable resource."
  }

  assert {
    condition = alltrue([
      for tags in [
        aws_api_gateway_rest_api.this.tags,
        aws_api_gateway_stage.this.tags,
        aws_cloudwatch_log_group.this["api_gateway_access"].tags,
        ] : (
        tags["CostCenter"] == "platform" &&
        tags["Owner"] == "team-core"
      )
    ])
    error_message = "Caller tags from var.tags were not preserved on every taggable resource."
  }

  assert {
    condition     = aws_api_gateway_rest_api.this.tags["Name"] == "core-prod-api"
    error_message = "REST API Name tag did not use the rendered name."
  }

  assert {
    condition     = aws_api_gateway_stage.this.tags["Name"] == "prod"
    error_message = "Stage Name tag did not use the stage name."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this["api_gateway_access"].tags["Name"] == "/aws/apigateway/core-prod-api"
    error_message = "Access log group Name tag did not use the log group prefix."
  }
}

# ------------------------------------------------------------------------------
# Security defaults
# ------------------------------------------------------------------------------
run "verify_access_logging_defaults" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.this["api_gateway_access"].kms_key_id == var.kms_key_arn
    error_message = "Access log group was not encrypted with kms_key_arn by default."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this["api_gateway_access"].retention_in_days == 30
    error_message = "Access log retention did not default to 30 days."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this["api_gateway_access"].log_group_class == "STANDARD"
    error_message = "Access log group class did not default to STANDARD."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this["api_gateway_access"].deletion_protection_enabled == true
    error_message = "Access log group deletion protection was not enabled."
  }

  assert {
    condition     = length(aws_api_gateway_stage.this.access_log_settings) == 1
    error_message = "Stage access logging was not configured."
  }

  assert {
    condition = alltrue([
      for key in ["requestId", "sourceIp", "httpMethod", "resourcePath", "status", "errorMessage", "authorizerError", "userAgent"] :
      contains(keys(jsondecode(aws_api_gateway_stage.this.access_log_settings[0].format)), key)
    ])
    error_message = "Default access log format did not include the expected JSON request fields."
  }
}

run "verify_access_log_kms_override" {
  command = plan

  variables {
    access_logs = {
      kms_key_id = "arn:aws:kms:us-west-2:123456789012:key/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    }
  }

  assert {
    condition     = aws_cloudwatch_log_group.this["api_gateway_access"].kms_key_id == "arn:aws:kms:us-west-2:123456789012:key/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    error_message = "access_logs.kms_key_id did not override the access log group KMS key."
  }
}

run "verify_access_log_destination" {
  command = apply

  # Applied runs get their own state so later plan runs start from an empty state.
  state_key = "verify_access_log_destination"

  assert {
    condition     = aws_api_gateway_stage.this.access_log_settings[0].destination_arn == aws_cloudwatch_log_group.this["api_gateway_access"].arn
    error_message = "Stage access logs were not delivered to the managed KMS-encrypted log group."
  }

  assert {
    condition     = aws_api_gateway_stage.this.rest_api_id == aws_api_gateway_rest_api.this.id && aws_api_gateway_stage.this.deployment_id == aws_api_gateway_deployment.this.id
    error_message = "Stage was not wired to the managed REST API and deployment."
  }

  assert {
    condition = (
      output.rest_api_id == "a1b2c3d4e5" &&
      output.execution_arn == "arn:aws:execute-api:us-west-2:123456789012:a1b2c3d4e5" &&
      output.invoke_url == "https://a1b2c3d4e5.execute-api.us-west-2.amazonaws.com/prod"
    )
    error_message = "rest_api_id, execution_arn and invoke_url outputs did not return the REST API and stage values."
  }
}

run "verify_tracing_and_endpoint_defaults" {
  command = plan

  assert {
    condition     = aws_api_gateway_stage.this.xray_tracing_enabled == true
    error_message = "X-Ray tracing was not enabled on the stage by default."
  }

  assert {
    condition = (
      aws_api_gateway_rest_api.this.endpoint_configuration[0].types == tolist(["REGIONAL"]) &&
      aws_api_gateway_rest_api.this.endpoint_configuration[0].ip_address_type == "ipv4"
    )
    error_message = "REST API endpoint did not default to REGIONAL over ipv4."
  }

  assert {
    condition     = aws_api_gateway_rest_api.this.disable_execute_api_endpoint == false
    error_message = "Default execute-api endpoint should stay enabled when no custom domain is configured."
  }

  assert {
    condition     = aws_api_gateway_rest_api.this.put_rest_api_mode == "overwrite"
    error_message = "REST API definition should be applied in overwrite mode."
  }

  assert {
    condition     = toset(aws_api_gateway_rest_api.this.binary_media_types) == toset(["image/png", "image/jpeg", "application/pdf", "multipart/form-data"])
    error_message = "Binary media types did not match the shipped defaults."
  }

  assert {
    condition     = aws_api_gateway_stage.this.cache_cluster_enabled == false
    error_message = "Stage cache cluster should be disabled by default."
  }

  assert {
    condition     = length(aws_api_gateway_deployment.this.triggers["redeployment"]) == 40
    error_message = "Deployment redeployment trigger should be a SHA-1 fingerprint of the API definition."
  }
}

run "verify_openapi_defaults" {
  command = plan

  assert {
    condition     = jsondecode(aws_api_gateway_rest_api.this.body).openapi == "3.0.1"
    error_message = "REST API body was not an OpenAPI 3.0.1 document."
  }

  assert {
    condition     = length(jsondecode(aws_api_gateway_rest_api.this.body).paths) == 0
    error_message = "No paths should be defined when routes is empty."
  }

  assert {
    condition = {
      for type, response in jsondecode(aws_api_gateway_rest_api.this.body)["x-amazon-apigateway-gateway-responses"] : type => response.statusCode
      } == {
      ACCESS_DENIED       = "403"
      BAD_REQUEST_BODY    = "400"
      DEFAULT_5XX         = "500"
      INTEGRATION_FAILURE = "502"
      INTEGRATION_TIMEOUT = "504"
      RESOURCE_NOT_FOUND  = "404"
      UNAUTHORIZED        = "401"
    }
    error_message = "Default gateway responses and status codes did not match the shipped set."
  }

  assert {
    condition = alltrue([
      for _, response in jsondecode(aws_api_gateway_rest_api.this.body)["x-amazon-apigateway-gateway-responses"] :
      jsondecode(response.responseTemplates["application/json"]).message == "$context.error.messageString"
    ])
    error_message = "Default gateway responses did not return the JSON error message template."
  }

  assert {
    condition = (
      !contains(keys(jsondecode(aws_api_gateway_rest_api.this.body)), "components") &&
      !contains(keys(jsondecode(aws_api_gateway_rest_api.this.body)), "x-amazon-apigateway-request-validators")
    )
    error_message = "Components and request validators should be omitted when none are configured."
  }
}

run "verify_optional_features_disabled_by_default" {
  command = plan

  assert {
    condition     = length(aws_wafv2_web_acl_association.this) == 0
    error_message = "WAF association should not be created without waf_web_acl_arn."
  }

  assert {
    condition     = length(aws_api_gateway_domain_name.this) == 0 && length(aws_api_gateway_base_path_mapping.this) == 0
    error_message = "Custom domain and base path mapping should be off by default."
  }

  assert {
    condition     = length(aws_lambda_permission.api_gateway) == 0 && length(aws_lambda_permission.api_gateway_authorizer) == 0
    error_message = "No Lambda permissions should be created without routes or authorizers."
  }

  assert {
    condition     = length(terraform_data.validations.input) == 0
    error_message = "Default inputs should produce no module validation errors."
  }
}

# ------------------------------------------------------------------------------
# Routes, integrations and authorization
# ------------------------------------------------------------------------------
run "verify_lambda_route_integration" {
  command = plan

  variables {
    routes = {
      "/items" = {
        methods = {
          GET = {
            lambda_function_arn = "arn:aws:lambda:us-west-2:123456789012:function:core-prod-items:live"
            operation_name      = "ListItems"
            request_parameters = {
              "method.request.querystring.limit" = false
            }
          }
        }
      }
      "/items/{id}" = {
        methods = {
          get = {
            lambda_function_arn = "arn:aws:lambda:us-west-2:123456789012:function:core-prod-items:live"
          }
        }
      }
    }
  }

  assert {
    condition = jsondecode(aws_api_gateway_rest_api.this.body).paths["/items"].get["x-amazon-apigateway-integration"] == {
      type       = "aws_proxy"
      httpMethod = "POST"
      uri        = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:core-prod-items:live/invocations"
    }
    error_message = "Lambda route did not default to an AWS_PROXY POST integration on the function alias."
  }

  assert {
    condition     = jsondecode(aws_api_gateway_rest_api.this.body).paths["/items"].get.operationId == "ListItems"
    error_message = "operation_name was not rendered as the OpenAPI operationId."
  }

  assert {
    condition = jsondecode(aws_api_gateway_rest_api.this.body).paths["/items"].get.parameters == [
      { name = "limit", in = "query", required = false, schema = { type = "string" } }
    ]
    error_message = "Query string request parameter was not rendered as an OpenAPI parameter."
  }

  assert {
    condition = jsondecode(aws_api_gateway_rest_api.this.body).paths["/items/{id}"].get.parameters == [
      { name = "id", in = "path", required = true, schema = { type = "string" } }
    ]
    error_message = "Path parameter was not rendered as a required OpenAPI path parameter."
  }

  assert {
    condition = alltrue([
      for _, path in jsondecode(aws_api_gateway_rest_api.this.body).paths : alltrue([
        for _, operation in path : !contains(keys(operation), "security")
      ])
    ])
    error_message = "Routes without authorizer_key should not reference a security scheme."
  }

  assert {
    condition     = toset(keys(aws_lambda_permission.api_gateway)) == toset(["GET /items", "GET /items/{id}"])
    error_message = "One Lambda invoke permission should be created per Lambda-backed method."
  }

  assert {
    condition = alltrue([
      for _, permission in aws_lambda_permission.api_gateway :
      permission.action == "lambda:InvokeFunction" &&
      permission.principal == "apigateway.amazonaws.com" &&
      permission.function_name == "arn:aws:lambda:us-west-2:123456789012:function:core-prod-items:live"
    ])
    error_message = "Lambda permissions must allow only apigateway.amazonaws.com to invoke the route function."
  }

  assert {
    condition = (
      startswith(aws_lambda_permission.api_gateway["GET /items"].statement_id, "AllowApiGatewaycore-prod-apiGET_items") &&
      length(aws_lambda_permission.api_gateway["GET /items"].statement_id) <= 100
    )
    error_message = "Lambda permission statement_id did not use the rendered name and method key within 100 characters."
  }

  assert {
    condition     = length(aws_api_gateway_method_settings.this) == 0
    error_message = "No method settings should be created when no throttling or method settings are configured."
  }
}

run "verify_lambda_permission_source_arn" {
  command = apply

  # Applied runs get their own state so later plan runs start from an empty state.
  state_key = "verify_lambda_permission_source_arn"

  variables {
    routes = {
      "/items" = {
        methods = {
          GET = {
            lambda_function_arn = "arn:aws:lambda:us-west-2:123456789012:function:core-prod-items:live"
          }
        }
      }
      "/items/{id}" = {
        methods = {
          DELETE = {
            lambda_function_arn = "arn:aws:lambda:us-west-2:123456789012:function:core-prod-items:live"
          }
        }
      }
    }
  }

  assert {
    condition     = aws_lambda_permission.api_gateway["GET /items"].source_arn == "arn:aws:execute-api:us-west-2:123456789012:a1b2c3d4e5/prod/GET/items"
    error_message = "Lambda permission source_arn was not scoped to the stage, method and path."
  }

  assert {
    condition     = aws_lambda_permission.api_gateway["DELETE /items/{id}"].source_arn == "arn:aws:execute-api:us-west-2:123456789012:a1b2c3d4e5/prod/DELETE/items/*"
    error_message = "Lambda permission source_arn did not replace path parameters with a wildcard."
  }
}

run "verify_cognito_authorizer" {
  command = plan

  variables {
    authorizers = {
      cognito = {
        provider_arns = ["arn:aws:cognito-idp:us-west-2:123456789012:userpool/us-west-2_AbCdEfGhI"]
      }
    }
    routes = {
      "/orders" = {
        methods = {
          POST = {
            lambda_function_arn = "arn:aws:lambda:us-west-2:123456789012:function:core-prod-orders:live"
            authorizer_key      = "cognito"
          }
        }
      }
    }
  }

  assert {
    condition     = jsondecode(aws_api_gateway_rest_api.this.body).paths["/orders"].post.security == [{ cognito = [] }]
    error_message = "Route with authorizer_key did not require the Cognito security scheme."
  }

  assert {
    condition = jsondecode(aws_api_gateway_rest_api.this.body).components.securitySchemes.cognito == {
      type                           = "apiKey"
      name                           = "Authorization"
      in                             = "header"
      "x-amazon-apigateway-authtype" = "cognito_user_pools"
      "x-amazon-apigateway-authorizer" = {
        type         = "cognito_user_pools"
        providerARNs = ["arn:aws:cognito-idp:us-west-2:123456789012:userpool/us-west-2_AbCdEfGhI"]
      }
    }
    error_message = "Cognito authorizer was not rendered as a cognito_user_pools security scheme on the Authorization header."
  }
}

run "verify_lambda_authorizer" {
  command = apply

  # Applied runs get their own state so later plan runs start from an empty state.
  state_key = "verify_lambda_authorizer"

  variables {
    lambda_authorizers = {
      api_key = {
        lambda_alias_arn = "arn:aws:lambda:us-west-2:123456789012:function:core-prod-authorizer:live"
      }
    }
    routes = {
      "/reports" = {
        methods = {
          GET = {
            lambda_function_arn = "arn:aws:lambda:us-west-2:123456789012:function:core-prod-reports:live"
            authorizer_key      = "api_key"
          }
        }
      }
    }
  }

  assert {
    condition     = jsondecode(aws_api_gateway_rest_api.this.body).paths["/reports"].get.security == [{ api_key = [] }]
    error_message = "Route with a Lambda authorizer_key did not require the Lambda security scheme."
  }

  assert {
    condition = jsondecode(aws_api_gateway_rest_api.this.body).components.securitySchemes.api_key["x-amazon-apigateway-authorizer"] == {
      type                         = "request"
      authorizerUri                = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:core-prod-authorizer:live/invocations"
      identitySource               = "method.request.header.Authorization, method.request.header.x-api-key"
      authorizerResultTtlInSeconds = 300
    }
    error_message = "Lambda authorizer was not rendered as a REQUEST authorizer with the default identity sources and TTL."
  }

  assert {
    condition = (
      aws_lambda_permission.api_gateway_authorizer["api_key"].statement_id == "AllowApiGatewayAuthorizerapikey" &&
      aws_lambda_permission.api_gateway_authorizer["api_key"].principal == "apigateway.amazonaws.com" &&
      aws_lambda_permission.api_gateway_authorizer["api_key"].function_name == "arn:aws:lambda:us-west-2:123456789012:function:core-prod-authorizer:live"
    )
    error_message = "Lambda authorizer invoke permission was not granted to API Gateway on the authorizer alias."
  }

  assert {
    condition     = aws_lambda_permission.api_gateway_authorizer["api_key"].source_arn == "arn:aws:execute-api:us-west-2:123456789012:a1b2c3d4e5/*/*"
    error_message = "Lambda authorizer permission was not scoped to this REST API."
  }
}

run "verify_non_lambda_integrations" {
  command = plan

  variables {
    routes = {
      "/proxy" = {
        methods = {
          GET = {
            integration = {
              type                 = "HTTP_PROXY"
              uri                  = "https://backend.example.com/proxy"
              timeout_milliseconds = 5000
            }
          }
        }
      }
    }
  }

  assert {
    condition = jsondecode(aws_api_gateway_rest_api.this.body).paths["/proxy"].get["x-amazon-apigateway-integration"] == {
      type            = "http_proxy"
      httpMethod      = "GET"
      uri             = "https://backend.example.com/proxy"
      timeoutInMillis = 5000
    }
    error_message = "HTTP_PROXY integration did not pass through the method, URI and timeout."
  }

  assert {
    condition     = length(aws_lambda_permission.api_gateway) == 0
    error_message = "Non-Lambda integrations must not create Lambda invoke permissions."
  }
}

run "verify_models_and_request_validators" {
  command = plan

  variables {
    models = {
      order = {
        name   = "OrderInput"
        schema = "{\"type\":\"object\",\"required\":[\"sku\"],\"properties\":{\"sku\":{\"type\":\"string\"}}}"
      }
    }
    request_validators = {
      body = {
        name                  = "validate-body"
        validate_request_body = true
      }
    }
    routes = {
      "/orders" = {
        methods = {
          POST = {
            lambda_function_arn   = "arn:aws:lambda:us-west-2:123456789012:function:core-prod-orders:live"
            request_model_key     = "order"
            request_validator_key = "body"
          }
        }
      }
    }
  }

  assert {
    condition     = jsondecode(aws_api_gateway_rest_api.this.body).paths["/orders"].post.requestBody.content["application/json"].schema["$ref"] == "#/components/schemas/OrderInput"
    error_message = "request_model_key did not reference the model schema."
  }

  assert {
    condition     = jsondecode(aws_api_gateway_rest_api.this.body).components.schemas.OrderInput.required == ["sku"]
    error_message = "Model schema was not rendered under components.schemas."
  }

  assert {
    condition     = jsondecode(aws_api_gateway_rest_api.this.body).paths["/orders"].post["x-amazon-apigateway-request-validator"] == "validate-body"
    error_message = "request_validator_key did not attach the request validator."
  }

  assert {
    condition = jsondecode(aws_api_gateway_rest_api.this.body)["x-amazon-apigateway-request-validators"]["validate-body"] == {
      validateRequestBody       = true
      validateRequestParameters = false
    }
    error_message = "Request validator settings were not rendered."
  }
}

# ------------------------------------------------------------------------------
# CORS
# ------------------------------------------------------------------------------
run "verify_cors_disabled_by_default" {
  command = plan

  variables {
    routes = {
      "/items" = {
        methods = {
          GET = {
            lambda_function_arn = "arn:aws:lambda:us-west-2:123456789012:function:core-prod-items:live"
          }
        }
      }
    }
  }

  assert {
    condition     = keys(jsondecode(aws_api_gateway_rest_api.this.body).paths["/items"]) == ["get"]
    error_message = "No OPTIONS method should be generated when CORS is disabled."
  }
}

run "verify_cors_enabled" {
  command = plan

  variables {
    cors = {
      enabled       = true
      allow_origins = ["https://app.example.com"]
    }
    routes = {
      "/items" = {
        methods = {
          GET = {
            lambda_function_arn = "arn:aws:lambda:us-west-2:123456789012:function:core-prod-items:live"
          }
        }
      }
    }
  }

  assert {
    condition = (
      jsondecode(aws_api_gateway_rest_api.this.body).paths["/items"].options["x-amazon-apigateway-integration"].type == "mock" &&
      jsondecode(aws_api_gateway_rest_api.this.body).paths["/items"].options["x-amazon-apigateway-integration"].passthroughBehavior == "when_no_match"
    )
    error_message = "CORS preflight was not generated as a MOCK OPTIONS integration."
  }

  assert {
    condition = (
      jsondecode(aws_api_gateway_rest_api.this.body).paths["/items"].options["x-amazon-apigateway-integration"].responses.default.responseParameters["method.response.header.Access-Control-Allow-Origin"] == "'https://app.example.com'" &&
      jsondecode(aws_api_gateway_rest_api.this.body).paths["/items"].options["x-amazon-apigateway-integration"].responses.default.responseParameters["method.response.header.Access-Control-Max-Age"] == "'86400'"
    )
    error_message = "CORS preflight did not return the configured origin and default max age."
  }

  assert {
    condition     = jsondecode(aws_api_gateway_rest_api.this.body).paths["/items"].options["x-amazon-apigateway-integration"].responses.default.responseParameters["method.response.header.Access-Control-Allow-Methods"] == "'GET,POST,PUT,PATCH,DELETE,OPTIONS'"
    error_message = "CORS preflight did not return the default allowed methods."
  }

  assert {
    condition     = !contains(keys(jsondecode(aws_api_gateway_rest_api.this.body).paths["/items"].options["x-amazon-apigateway-integration"].responses.default.responseParameters), "method.response.header.Access-Control-Allow-Credentials")
    error_message = "Allow-Credentials should only be returned when allow_credentials is true."
  }

  assert {
    condition     = !contains(keys(jsondecode(aws_api_gateway_rest_api.this.body).paths["/items"].options), "security")
    error_message = "CORS preflight must not require authorization."
  }

  assert {
    condition     = toset(keys(aws_lambda_permission.api_gateway)) == toset(["GET /items"])
    error_message = "CORS preflight methods must not create Lambda invoke permissions."
  }
}

run "verify_cors_with_credentials" {
  command = plan

  variables {
    cors = {
      enabled           = true
      allow_origins     = ["https://app.example.com"]
      allow_credentials = true
      max_age           = 600
    }
    routes = {
      "/items" = {
        methods = {
          GET = {
            lambda_function_arn = "arn:aws:lambda:us-west-2:123456789012:function:core-prod-items:live"
          }
        }
      }
    }
  }

  assert {
    condition = (
      jsondecode(aws_api_gateway_rest_api.this.body).paths["/items"].options["x-amazon-apigateway-integration"].responses.default.responseParameters["method.response.header.Access-Control-Allow-Credentials"] == "'true'" &&
      jsondecode(aws_api_gateway_rest_api.this.body).paths["/items"].options["x-amazon-apigateway-integration"].responses.default.responseParameters["method.response.header.Access-Control-Max-Age"] == "'600'"
    )
    error_message = "allow_credentials and max_age were not applied to the CORS preflight response."
  }
}

run "verify_route_cors_origin_override" {
  command = plan

  variables {
    cors = {
      enabled       = true
      allow_origins = ["https://app.example.com"]
    }
    routes = {
      "/admin" = {
        cors = {
          allow_origins = ["https://admin.example.com"]
        }
        methods = {
          GET = {
            lambda_function_arn = "arn:aws:lambda:us-west-2:123456789012:function:core-prod-admin:live"
          }
        }
      }
    }
  }

  assert {
    condition     = jsondecode(aws_api_gateway_rest_api.this.body).paths["/admin"].options["x-amazon-apigateway-integration"].responses.default.responseParameters["method.response.header.Access-Control-Allow-Origin"] == "'https://admin.example.com'"
    error_message = "Route-level cors.allow_origins did not override the default origin."
  }
}

run "verify_explicit_options_suppresses_cors_preflight" {
  command = plan

  variables {
    cors = {
      enabled = true
    }
    routes = {
      "/items" = {
        methods = {
          OPTIONS = {
            lambda_function_arn = "arn:aws:lambda:us-west-2:123456789012:function:core-prod-items:live"
          }
        }
      }
    }
  }

  assert {
    condition     = jsondecode(aws_api_gateway_rest_api.this.body).paths["/items"].options["x-amazon-apigateway-integration"].type == "aws_proxy"
    error_message = "An explicit OPTIONS method should replace the generated CORS preflight."
  }
}

# ------------------------------------------------------------------------------
# Parameters: overrides flow through
# ------------------------------------------------------------------------------
run "verify_parameter_overrides" {
  command = plan

  variables {
    endpoint_type            = "edge"
    minimum_compression_size = 1024
    tracing_enabled          = false
    stage = {
      stage_name            = "v1"
      description           = "Version 1"
      variables             = { backend = "blue" }
      cache_cluster_enabled = true
      cache_cluster_size    = "0.5"
    }
    access_logs = {
      retention_in_days = 90
      log_group_class   = "INFREQUENT_ACCESS"
      format            = "{\"requestId\":\"$context.requestId\"}"
    }
    rate_limiting = {
      burst_limit = 200
      rate_limit  = 100
    }
    method_settings = {
      metrics_enabled = true
      logging_level   = "INFO"
    }
  }

  assert {
    condition     = aws_api_gateway_rest_api.this.endpoint_configuration[0].types == tolist(["EDGE"])
    error_message = "endpoint_type override was not upper-cased and applied."
  }

  assert {
    condition     = aws_api_gateway_rest_api.this.minimum_compression_size == "1024"
    error_message = "minimum_compression_size override was not applied."
  }

  assert {
    condition     = aws_api_gateway_stage.this.xray_tracing_enabled == false
    error_message = "tracing_enabled override was not applied to the stage."
  }

  assert {
    condition = (
      aws_api_gateway_stage.this.description == "Version 1" &&
      aws_api_gateway_stage.this.variables == tomap({ backend = "blue" }) &&
      aws_api_gateway_stage.this.cache_cluster_enabled == true &&
      aws_api_gateway_stage.this.cache_cluster_size == "0.5"
    )
    error_message = "Stage description, variables and cache settings were not applied."
  }

  assert {
    condition = (
      aws_cloudwatch_log_group.this["api_gateway_access"].retention_in_days == 90 &&
      aws_cloudwatch_log_group.this["api_gateway_access"].log_group_class == "INFREQUENT_ACCESS" &&
      aws_api_gateway_stage.this.access_log_settings[0].format == "{\"requestId\":\"$context.requestId\"}"
    )
    error_message = "access_logs retention, class and format overrides were not applied."
  }

  assert {
    condition = (
      keys(aws_api_gateway_method_settings.this) == ["*/*"] &&
      aws_api_gateway_method_settings.this["*/*"].stage_name == "v1" &&
      aws_api_gateway_method_settings.this["*/*"].settings[0].throttling_burst_limit == 200 &&
      aws_api_gateway_method_settings.this["*/*"].settings[0].throttling_rate_limit == 100 &&
      aws_api_gateway_method_settings.this["*/*"].settings[0].metrics_enabled == true &&
      aws_api_gateway_method_settings.this["*/*"].settings[0].logging_level == "INFO"
    )
    error_message = "Global rate_limiting and method_settings were not applied to */* method settings."
  }
}

run "verify_route_method_settings" {
  command = plan

  variables {
    rate_limiting = {
      burst_limit = 100
      rate_limit  = 50
    }
    routes = {
      "/items/{id}" = {
        rate_limiting = {
          burst_limit = 20
        }
        methods = {
          GET = {
            lambda_function_arn = "arn:aws:lambda:us-west-2:123456789012:function:core-prod-items:live"
            rate_limiting = {
              rate_limit = 10
            }
          }
        }
      }
    }
  }

  assert {
    condition     = toset(keys(aws_api_gateway_method_settings.this)) == toset(["*/*", "items/{id}/GET"])
    error_message = "Route-level settings did not create a per-method settings override."
  }

  assert {
    condition = (
      aws_api_gateway_method_settings.this["items/{id}/GET"].settings[0].throttling_burst_limit == 20 &&
      aws_api_gateway_method_settings.this["items/{id}/GET"].settings[0].throttling_rate_limit == 10
    )
    error_message = "Route and method throttling did not override the global defaults."
  }
}

run "verify_gateway_response_overrides" {
  command = plan

  variables {
    gateway_responses = {
      THROTTLED = {
        status_code        = "429"
        response_templates = { "application/json" = "{\"message\":\"Too many requests\"}" }
      }
    }
  }

  assert {
    condition = (
      jsondecode(aws_api_gateway_rest_api.this.body)["x-amazon-apigateway-gateway-responses"].THROTTLED.statusCode == "429" &&
      jsondecode(aws_api_gateway_rest_api.this.body)["x-amazon-apigateway-gateway-responses"].THROTTLED.responseTemplates == { "application/json" = "{\"message\":\"Too many requests\"}" }
    )
    error_message = "Custom gateway response status code and template were not applied."
  }

  assert {
    condition     = length(jsondecode(aws_api_gateway_rest_api.this.body)["x-amazon-apigateway-gateway-responses"]) == 8
    error_message = "Custom gateway responses should be added to the defaults, not replace them."
  }
}

run "verify_waf_association" {
  command = apply

  # Applied runs get their own state so later plan runs start from an empty state.
  state_key = "verify_waf_association"

  variables {
    waf_web_acl_arn = "arn:aws:wafv2:us-west-2:123456789012:regional/webacl/core-prod-api/12345678-1234-1234-1234-123456789012"
  }

  assert {
    condition     = length(aws_wafv2_web_acl_association.this) == 1
    error_message = "WAF association was not created when waf_web_acl_arn is set."
  }

  assert {
    condition = (
      aws_wafv2_web_acl_association.this[0].web_acl_arn == var.waf_web_acl_arn &&
      aws_wafv2_web_acl_association.this[0].resource_arn == aws_api_gateway_stage.this.arn
    )
    error_message = "WAF Web ACL was not associated with the managed stage."
  }
}

run "verify_custom_domain_regional" {
  command = plan

  variables {
    tags = {
      CostCenter = "platform"
    }
    custom_domain = {
      enabled         = true
      domain_name     = "api.example.com"
      certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
      security_policy = "TLS_1_2"
    }
  }

  assert {
    condition = (
      length(aws_api_gateway_domain_name.this) == 1 &&
      aws_api_gateway_domain_name.this[0].domain_name == "api.example.com" &&
      aws_api_gateway_domain_name.this[0].security_policy == "TLS_1_2"
    )
    error_message = "Custom domain was not created with the configured name and TLS policy."
  }

  assert {
    condition = (
      aws_api_gateway_domain_name.this[0].regional_certificate_arn == "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012" &&
      aws_api_gateway_domain_name.this[0].certificate_arn == null &&
      aws_api_gateway_domain_name.this[0].endpoint_configuration[0].types == tolist(["REGIONAL"])
    )
    error_message = "REGIONAL custom domain must use regional_certificate_arn only."
  }

  assert {
    condition     = aws_api_gateway_rest_api.this.disable_execute_api_endpoint == true
    error_message = "Default execute-api endpoint must be disabled when a custom domain is enabled."
  }

  assert {
    condition = (
      length(aws_api_gateway_base_path_mapping.this) == 1 &&
      aws_api_gateway_base_path_mapping.this[0].domain_name == "api.example.com" &&
      aws_api_gateway_base_path_mapping.this[0].stage_name == "prod"
    )
    error_message = "Base path mapping was not created for the managed stage."
  }

  assert {
    condition = (
      aws_api_gateway_domain_name.this[0].tags["Application"] == "core" &&
      aws_api_gateway_domain_name.this[0].tags["Environment"] == "prod" &&
      aws_api_gateway_domain_name.this[0].tags["Name"] == "core-prod-api" &&
      aws_api_gateway_domain_name.this[0].tags["CostCenter"] == "platform"
    )
    error_message = "Custom domain did not carry governance and caller tags."
  }
}

run "verify_custom_domain_edge_without_mapping" {
  command = plan

  variables {
    custom_domain = {
      enabled                  = true
      domain_name              = "api.example.com"
      certificate_arn          = "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
      endpoint_type            = "EDGE"
      create_base_path_mapping = false
    }
  }

  assert {
    condition = (
      aws_api_gateway_domain_name.this[0].certificate_arn == "arn:aws:acm:us-east-1:123456789012:certificate/12345678-1234-1234-1234-123456789012" &&
      aws_api_gateway_domain_name.this[0].regional_certificate_arn == null &&
      aws_api_gateway_domain_name.this[0].endpoint_configuration[0].types == tolist(["EDGE"])
    )
    error_message = "EDGE custom domain must use certificate_arn only."
  }

  assert {
    condition     = length(aws_api_gateway_base_path_mapping.this) == 0
    error_message = "Base path mapping should not be created when create_base_path_mapping is false."
  }
}

# ------------------------------------------------------------------------------
# Module guardrails (terraform_data.validations precondition)
# ------------------------------------------------------------------------------
run "verify_unknown_authorizer_key_fails" {
  command = plan

  variables {
    routes = {
      "/items" = {
        methods = {
          GET = {
            lambda_function_arn = "arn:aws:lambda:us-west-2:123456789012:function:core-prod-items:live"
            authorizer_key      = "missing"
          }
        }
      }
    }
  }

  expect_failures = [terraform_data.validations]
}

run "verify_cognito_authorizer_requires_provider_arns" {
  command = plan

  variables {
    authorizers = {
      cognito = {}
    }
  }

  expect_failures = [terraform_data.validations]
}

run "verify_route_cors_credentials_with_wildcard_fails" {
  command = plan

  variables {
    cors = {
      enabled = true
    }
    routes = {
      "/items" = {
        cors = {
          allow_credentials = true
        }
        methods = {
          GET = {
            lambda_function_arn = "arn:aws:lambda:us-west-2:123456789012:function:core-prod-items:live"
          }
        }
      }
    }
  }

  expect_failures = [terraform_data.validations]
}

run "verify_custom_domain_requires_domain_name" {
  command = plan

  variables {
    custom_domain = {
      enabled         = true
      certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    }
  }

  expect_failures = [terraform_data.validations]
}

run "verify_custom_domain_requires_certificate" {
  command = plan

  variables {
    custom_domain = {
      enabled     = true
      domain_name = "api.example.com"
    }
  }

  expect_failures = [terraform_data.validations]
}

run "verify_custom_domain_invalid_endpoint_type_fails" {
  command = plan

  variables {
    custom_domain = {
      enabled         = true
      domain_name     = "api.example.com"
      certificate_arn = "arn:aws:acm:us-west-2:123456789012:certificate/12345678-1234-1234-1234-123456789012"
      endpoint_type   = "GLOBAL"
    }
  }

  expect_failures = [terraform_data.validations]
}

# ------------------------------------------------------------------------------
# Validation
# ------------------------------------------------------------------------------
run "verify_empty_application_fails" {
  command = plan

  variables {
    application = "  "
  }

  expect_failures = [var.application]
}

run "verify_empty_environment_fails" {
  command = plan

  variables {
    environment = ""
  }

  expect_failures = [var.environment]
}

run "verify_invalid_endpoint_type_fails" {
  command = plan

  variables {
    endpoint_type = "GLOBAL"
  }

  expect_failures = [var.endpoint_type]
}

run "verify_negative_burst_limit_fails" {
  command = plan

  variables {
    rate_limiting = {
      burst_limit = -1
    }
  }

  expect_failures = [var.rate_limiting]
}

run "verify_negative_rate_limit_fails" {
  command = plan

  variables {
    rate_limiting = {
      rate_limit = -1
    }
  }

  expect_failures = [var.rate_limiting]
}

run "verify_empty_waf_web_acl_arn_fails" {
  command = plan

  variables {
    waf_web_acl_arn = " "
  }

  expect_failures = [var.waf_web_acl_arn]
}

run "verify_route_without_leading_slash_fails" {
  command = plan

  variables {
    routes = {
      "items" = {
        methods = {
          GET = {
            lambda_function_arn = "arn:aws:lambda:us-west-2:123456789012:function:core-prod-items:live"
          }
        }
      }
    }
  }

  expect_failures = [var.routes]
}

run "verify_route_with_trailing_slash_fails" {
  command = plan

  variables {
    routes = {
      "/items/" = {
        methods = {
          GET = {
            lambda_function_arn = "arn:aws:lambda:us-west-2:123456789012:function:core-prod-items:live"
          }
        }
      }
    }
  }

  expect_failures = [var.routes]
}

run "verify_invalid_http_method_fails" {
  command = plan

  variables {
    routes = {
      "/items" = {
        methods = {
          FETCH = {
            lambda_function_arn = "arn:aws:lambda:us-west-2:123456789012:function:core-prod-items:live"
          }
        }
      }
    }
  }

  expect_failures = [var.routes]
}

run "verify_negative_route_rate_limit_fails" {
  command = plan

  variables {
    routes = {
      "/items" = {
        rate_limiting = {
          burst_limit = -5
        }
        methods = {
          GET = {
            lambda_function_arn = "arn:aws:lambda:us-west-2:123456789012:function:core-prod-items:live"
          }
        }
      }
    }
  }

  expect_failures = [var.routes]
}

run "verify_cors_credentials_with_wildcard_origin_fails" {
  command = plan

  variables {
    cors = {
      enabled           = true
      allow_credentials = true
    }
  }

  expect_failures = [var.cors]
}

run "verify_empty_stage_name_fails" {
  command = plan

  variables {
    stage = {
      stage_name = " "
    }
  }

  expect_failures = [var.stage]
}
