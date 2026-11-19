mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "eu-west-1"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    }
  }

  mock_resource "aws_api_gateway_rest_api" {
    defaults = {
      id            = "a1b2c3d4e5"
      arn           = "arn:aws:apigateway:eu-west-1::/restapis/a1b2c3d4e5"
      execution_arn = "arn:aws:execute-api:eu-west-1:123456789012:a1b2c3d4e5"
    }
  }

  mock_resource "aws_api_gateway_stage" {
    defaults = {
      arn        = "arn:aws:apigateway:eu-west-1::/restapis/a1b2c3d4e5/stages/prod"
      invoke_url = "https://a1b2c3d4e5.execute-api.eu-west-1.amazonaws.com/prod"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-west-1:123456789012:log-group:/aws/apigateway/core-prod/prod/access"
    }
  }

  mock_resource "aws_api_gateway_domain_name" {
    defaults = {
      regional_domain_name = "d-abc123.execute-api.eu-west-1.amazonaws.com"
      regional_zone_id     = "ZLY8HYME6SFDD"
    }
  }
}

variables {
  application = "core"
  environment = "prod"
  tags        = { Team = "payments" }
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = aws_api_gateway_rest_api.this.name == "core-prod" && aws_api_gateway_stage.this.stage_name == "prod" && aws_api_gateway_rest_api.this.endpoint_configuration[0].types == tolist(["REGIONAL"])
    error_message = "A Regional API <application>-<environment> with a stage named after the environment."
  }

  assert {
    condition     = aws_api_gateway_rest_api.this.security_policy == "SecurityPolicy_TLS13_1_2_PFS_PQ_2025_09" && aws_api_gateway_rest_api.this.endpoint_access_mode == "STRICT" && !aws_api_gateway_rest_api.this.disable_execute_api_endpoint
    error_message = "Regional APIs use the TLS 1.2+ PFS post-quantum policy with STRICT access."
  }

  assert {
    condition     = aws_api_gateway_stage.this.xray_tracing_enabled && !aws_api_gateway_stage.this.cache_cluster_enabled && aws_api_gateway_stage.this.client_certificate_id == null
    error_message = "X-Ray on, no cache cluster by default (APIGateway.3)."
  }

  assert {
    condition     = module.access_log_group.name == "/aws/apigateway/core-prod/prod/access" && module.access_log_group.retention_in_days == 365 && module.access_log_group.kms_key_arn == null && output.kms_key_arn == null
    error_message = "Access logs go to /aws/apigateway/<api>/<stage>/access for 365 days."
  }

  assert {
    condition     = length(module.execution_log_group) == 1 && keys(aws_api_gateway_method_settings.this) == ["*/*"]
    error_message = "Execution logging pre-creates its log group and sets */* settings."
  }

  assert {
    condition     = aws_api_gateway_method_settings.this["*/*"].settings[0].logging_level == "ERROR" && aws_api_gateway_method_settings.this["*/*"].settings[0].metrics_enabled && !aws_api_gateway_method_settings.this["*/*"].settings[0].data_trace_enabled
    error_message = "Execution logging at ERROR with metrics and no data trace (APIGateway.1)."
  }

  assert {
    condition     = length(aws_wafv2_web_acl_association.this) + length(aws_api_gateway_domain_name.this) + length(aws_api_gateway_base_path_mapping.this) + length(aws_lambda_permission.routes) + length(aws_lambda_permission.authorizers) == 0 && output.regional_domain_name == null
    error_message = "No WAF, domain or invoke permission by default."
  }

  assert {
    condition     = aws_api_gateway_rest_api.this.tags["Name"] == "core-prod" && aws_api_gateway_rest_api.this.tags["Team"] == "payments" && aws_api_gateway_rest_api.this.tags["ManagedBy"] == "Terraform" && aws_api_gateway_stage.this.tags["Name"] == "prod"
    error_message = "Caller and governance tags must be applied."
  }
}

run "access_log_wiring" {
  command = apply

  assert {
    condition     = aws_api_gateway_stage.this.access_log_settings[0].destination_arn == output.log_group_arn && jsondecode(aws_api_gateway_stage.this.access_log_settings[0].format).requestId == "$context.requestId"
    error_message = "The stage must log JSON to the module access log group."
  }

  assert {
    condition     = module.execution_log_group[0].name == "API-Gateway-Execution-Logs_a1b2c3d4e5/prod" && module.execution_log_group[0].retention_in_days == 365
    error_message = "The execution log group is pre-created with the retention."
  }

  assert {
    condition     = output.id == "a1b2c3d4e5" && output.execution_arn == "arn:aws:execute-api:eu-west-1:123456789012:a1b2c3d4e5" && output.stage_name == "prod" && output.invoke_url == "https://a1b2c3d4e5.execute-api.eu-west-1.amazonaws.com/prod"
    error_message = "Outputs must expose the API and stage."
  }
}

run "lambda_routes_and_authorizers" {
  command = apply

  variables {
    cors = { enabled = true, allow_origins = ["https://app.example.com"] }
    authorizers = {
      cognito = { provider_arns = ["arn:aws:cognito-idp:eu-west-1:123456789012:userpool/eu-west-1_AbCdEfGhI"] }
    }
    lambda_authorizers = {
      token = {
        invoke_arn = "arn:aws:apigateway:eu-west-1:lambda:path/2015-03-31/functions/arn:aws:lambda:eu-west-1:123456789012:function:core-prod-auth:live/invocations"
        alias_arn  = "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-auth:live"
      }
    }
    routes = {
      "/orders" = {
        methods = {
          GET = {
            authorizer_key = "cognito"
            lambda = {
              invoke_arn = "arn:aws:apigateway:eu-west-1:lambda:path/2015-03-31/functions/arn:aws:lambda:eu-west-1:123456789012:function:core-prod-orders:live/invocations"
              alias_arn  = "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-orders:live"
            }
          }
        }
      }
      "/orders/{id}" = {
        methods = {
          ANY = {
            authorizer_key     = "token"
            request_parameters = { "method.request.header.X-Trace" = false }
            lambda = {
              invoke_arn = "arn:aws:apigateway:eu-west-1:lambda:path/2015-03-31/functions/arn:aws:lambda:eu-west-1:123456789012:function:core-prod-orders:live/invocations"
              alias_arn  = "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-orders:live"
            }
          }
        }
      }
    }
  }

  assert {
    condition     = jsondecode(aws_api_gateway_rest_api.this.body).paths["/orders"].get["x-amazon-apigateway-integration"].type == "aws_proxy" && jsondecode(aws_api_gateway_rest_api.this.body).paths["/orders"].get["x-amazon-apigateway-integration"].httpMethod == "POST" && jsondecode(aws_api_gateway_rest_api.this.body).paths["/orders"].get["x-amazon-apigateway-integration"].uri == "arn:aws:apigateway:eu-west-1:lambda:path/2015-03-31/functions/arn:aws:lambda:eu-west-1:123456789012:function:core-prod-orders:live/invocations"
    error_message = "Lambda routes use the lambda module's invoke ARN with AWS_PROXY."
  }

  assert {
    condition     = jsondecode(aws_api_gateway_rest_api.this.body).paths["/orders"].get.security == [{ cognito = [] }] && jsondecode(aws_api_gateway_rest_api.this.body).components.securitySchemes.cognito["x-amazon-apigateway-authorizer"].providerARNs == ["arn:aws:cognito-idp:eu-west-1:123456789012:userpool/eu-west-1_AbCdEfGhI"]
    error_message = "Methods must use their Cognito authorizer."
  }

  assert {
    condition     = jsondecode(aws_api_gateway_rest_api.this.body).paths["/orders/{id}"]["x-amazon-apigateway-any-method"].security == [{ token = [] }] && jsondecode(aws_api_gateway_rest_api.this.body).components.securitySchemes.token["x-amazon-apigateway-authorizer"].type == "request" && length(jsondecode(aws_api_gateway_rest_api.this.body).paths["/orders/{id}"]["x-amazon-apigateway-any-method"].parameters) == 2
    error_message = "ANY methods, Lambda authorizers and path and header parameters must render."
  }

  assert {
    condition     = jsondecode(aws_api_gateway_rest_api.this.body).paths["/orders"].options["x-amazon-apigateway-integration"].type == "mock" && jsondecode(aws_api_gateway_rest_api.this.body).paths["/orders"].options["x-amazon-apigateway-integration"].responses.default.responseParameters["method.response.header.Access-Control-Allow-Origin"] == "'https://app.example.com'"
    error_message = "CORS adds a MOCK OPTIONS method per route."
  }

  assert {
    condition     = aws_lambda_permission.routes["GET /orders"].function_name == "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-orders" && aws_lambda_permission.routes["GET /orders"].qualifier == "live" && aws_lambda_permission.routes["GET /orders"].source_arn == "arn:aws:execute-api:eu-west-1:123456789012:a1b2c3d4e5/prod/GET/orders"
    error_message = "Invoke permissions target the alias and are scoped to the stage, method and path."
  }

  assert {
    condition     = aws_lambda_permission.routes["ANY /orders/{id}"].source_arn == "arn:aws:execute-api:eu-west-1:123456789012:a1b2c3d4e5/prod/*/orders/*" && length(aws_lambda_permission.routes["ANY /orders/{id}"].statement_id) <= 100
    error_message = "ANY methods and path parameters become wildcards."
  }

  assert {
    condition     = aws_lambda_permission.authorizers["token"].source_arn == "arn:aws:execute-api:eu-west-1:123456789012:a1b2c3d4e5/authorizers/*" && aws_lambda_permission.authorizers["token"].qualifier == "live" && aws_lambda_permission.authorizers["token"].principal == "apigateway.amazonaws.com"
    error_message = "Authorizer permissions are scoped to this API's authorizers."
  }
}

run "other_integrations_models_and_validators" {
  command = apply

  variables {
    allow_unauthenticated_methods = true
    models                        = { Order = "{\"type\":\"object\",\"required\":[\"id\"]}" }
    request_validators            = { body = { validate_request_body = true } }
    gateway_responses             = { ACCESS_DENIED = { status_code = "404" } }
    routes = {
      "/" = {
        methods = {
          GET = { integration = { type = "MOCK", request_templates = { "application/json" = "{\"statusCode\": 200}" } }, integration_responses = { "200" = {} } }
        }
      }
      "/legacy" = {
        methods = {
          POST = {
            request_model     = "Order"
            request_validator = "body"
            integration       = { type = "HTTP_PROXY", uri = "https://legacy.example.com/orders", timeout_milliseconds = 10000 }
          }
        }
      }
    }
  }

  assert {
    condition     = jsondecode(aws_api_gateway_rest_api.this.body).paths["/"].get["x-amazon-apigateway-integration"].type == "mock" && !can(jsondecode(aws_api_gateway_rest_api.this.body).paths["/"].get["x-amazon-apigateway-integration"].httpMethod) && jsondecode(aws_api_gateway_rest_api.this.body).paths["/"].get["x-amazon-apigateway-integration"].responses.default.statusCode == "200"
    error_message = "MOCK integrations take no HTTP method."
  }

  assert {
    condition     = jsondecode(aws_api_gateway_rest_api.this.body).paths["/legacy"].post["x-amazon-apigateway-integration"].uri == "https://legacy.example.com/orders" && jsondecode(aws_api_gateway_rest_api.this.body).paths["/legacy"].post["x-amazon-apigateway-integration"].httpMethod == "POST" && jsondecode(aws_api_gateway_rest_api.this.body).paths["/legacy"].post["x-amazon-apigateway-integration"].timeoutInMillis == 10000
    error_message = "HTTP integrations use their URI and the method verb."
  }

  assert {
    condition     = jsondecode(aws_api_gateway_rest_api.this.body).components.schemas.Order.required == ["id"] && jsondecode(aws_api_gateway_rest_api.this.body).paths["/legacy"].post.requestBody.content["application/json"].schema["$ref"] == "#/components/schemas/Order" && jsondecode(aws_api_gateway_rest_api.this.body).paths["/legacy"].post["x-amazon-apigateway-request-validator"] == "body"
    error_message = "Models and validators are referenced by name."
  }

  assert {
    condition     = jsondecode(aws_api_gateway_rest_api.this.body)["x-amazon-apigateway-request-validators"].body.validateRequestBody && jsondecode(aws_api_gateway_rest_api.this.body)["x-amazon-apigateway-gateway-responses"].ACCESS_DENIED.statusCode == "404" && jsondecode(aws_api_gateway_rest_api.this.body)["x-amazon-apigateway-gateway-responses"].UNAUTHORIZED.statusCode == "401"
    error_message = "Validators and gateway response overrides must render."
  }

  assert {
    condition     = length(aws_lambda_permission.routes) == 0
    error_message = "Only Lambda routes get invoke permissions."
  }
}

run "named_instance_and_stage" {
  command   = plan
  state_key = "named"

  variables {
    name                     = "public"
    description              = "Public API"
    endpoint_type            = "EDGE"
    stage                    = { name = "v1", variables = { mode = "live" } }
    binary_media_types       = ["image/png"]
    minimum_compression_size = 1024
  }

  assert {
    condition     = aws_api_gateway_rest_api.this.name == "core-prod-public" && aws_api_gateway_stage.this.stage_name == "v1" && module.access_log_group.name == "/aws/apigateway/core-prod-public/v1/access" && aws_api_gateway_stage.this.variables["mode"] == "live"
    error_message = "name and stage.name shape the API, stage and log group names."
  }

  assert {
    condition     = aws_api_gateway_rest_api.this.description == "Public API" && aws_api_gateway_rest_api.this.endpoint_configuration[0].types == tolist(["EDGE"]) && aws_api_gateway_rest_api.this.binary_media_types == tolist(["image/png"]) && aws_api_gateway_rest_api.this.minimum_compression_size == "1024"
    error_message = "Description, endpoint type, binary media types and compression must apply."
  }

  assert {
    condition     = aws_api_gateway_rest_api.this.security_policy == "SecurityPolicy_TLS12_PFS_2025_EDGE"
    error_message = "EDGE APIs default to the edge PFS policy."
  }
}

run "execution_logging_off" {
  command   = plan
  state_key = "noexec"

  variables {
    execution_logging = { enabled = false, metrics_enabled = false }
    tracing           = { enabled = false }
  }

  assert {
    condition     = !aws_api_gateway_stage.this.xray_tracing_enabled
    error_message = "tracing.enabled = false turns X-Ray off."
  }

  assert {
    condition     = length(module.execution_log_group) == 0 && aws_api_gateway_method_settings.this["*/*"].settings[0].logging_level == "OFF" && !aws_api_gateway_method_settings.this["*/*"].settings[0].metrics_enabled
    error_message = "Without execution logging there is no execution log group and logging is OFF."
  }
}

run "method_settings_and_cache" {
  command   = plan
  state_key = "settings"

  variables {
    allow_unauthenticated_methods = true
    cache_cluster                 = { enabled = true, size = "1.6" }
    method_settings               = { throttling_rate_limit = 100, throttling_burst_limit = 200 }
    routes = {
      "/orders" = {
        method_settings = { throttling_rate_limit = 10 }
        methods = {
          GET = { integration = { type = "HTTP_PROXY", uri = "https://orders.example.com" }, method_settings = { caching_enabled = true, cache_ttl_in_seconds = 60 } }
        }
      }
    }
  }

  assert {
    condition     = keys(aws_api_gateway_method_settings.this) == ["*/*", "orders/GET"] && aws_api_gateway_stage.this.cache_cluster_size == "1.6"
    error_message = "Stage-wide settings plus one override per configured method."
  }

  assert {
    condition     = aws_api_gateway_method_settings.this["*/*"].settings[0].throttling_rate_limit == 100 && aws_api_gateway_method_settings.this["*/*"].settings[0].cache_data_encrypted
    error_message = "Stage settings apply; the cache cluster is encrypted (APIGateway.5)."
  }

  assert {
    condition     = aws_api_gateway_method_settings.this["orders/GET"].settings[0].throttling_rate_limit == 10 && aws_api_gateway_method_settings.this["orders/GET"].settings[0].throttling_burst_limit == 200 && aws_api_gateway_method_settings.this["orders/GET"].settings[0].caching_enabled && aws_api_gateway_method_settings.this["orders/GET"].settings[0].cache_data_encrypted && aws_api_gateway_method_settings.this["orders/GET"].settings[0].logging_level == "ERROR"
    error_message = "Method overrides inherit stage settings; cached methods are encrypted."
  }
}

run "module_key_is_planned_safely" {
  command = plan

  variables {
    kms = { create = true }
  }

  assert {
    condition     = module.encryption.created
    error_message = "kms.create must plan without knowing the key ARN."
  }
}

run "module_key_encrypts_logs" {
  command = apply

  variables {
    kms = { create = true }
  }

  assert {
    condition     = module.access_log_group.kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && module.execution_log_group[0].kms_key_arn == module.access_log_group.kms_key_arn && output.kms_key_arn == module.access_log_group.kms_key_arn
    error_message = "The module key must encrypt the access and execution logs."
  }
}

run "caller_key_id_and_log_key_override" {
  command = plan

  variables {
    kms             = { key_id = "11111111-2222-3333-4444-555555555555" }
    cloudwatch_logs = { kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/99999999-2222-3333-4444-555555555555", retention_in_days = 731 }
  }

  assert {
    condition     = output.kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && module.access_log_group.kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/99999999-2222-3333-4444-555555555555" && module.access_log_group.retention_in_days == 731
    error_message = "A key ID becomes the key ARN; cloudwatch_logs overrides the log key and retention."
  }
}

run "waf_custom_domain_and_tls" {
  command = apply

  variables {
    waf = { enabled = true, web_acl_arn = "arn:aws:wafv2:eu-west-1:123456789012:regional/webacl/core-prod/12345678-1234-1234-1234-123456789012" }
    tls = { security_policy = "SecurityPolicy_TLS13_1_3_2025_09" }
    custom_domain = {
      enabled         = true
      domain_name     = "api.example.com"
      certificate_arn = "arn:aws:acm:eu-west-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
    }
    client_certificate_id = "abc123"
  }

  assert {
    condition     = aws_wafv2_web_acl_association.this[0].resource_arn == output.stage_arn && aws_wafv2_web_acl_association.this[0].web_acl_arn == "arn:aws:wafv2:eu-west-1:123456789012:regional/webacl/core-prod/12345678-1234-1234-1234-123456789012"
    error_message = "The web ACL must be associated with the stage (APIGateway.4)."
  }

  assert {
    condition     = aws_api_gateway_domain_name.this[0].security_policy == "SecurityPolicy_TLS13_1_2_PFS_PQ_2025_09" && aws_api_gateway_domain_name.this[0].endpoint_access_mode == "STRICT" && aws_api_gateway_rest_api.this.security_policy == "SecurityPolicy_TLS13_1_3_2025_09" && aws_api_gateway_domain_name.this[0].endpoint_configuration[0].types == tolist(["REGIONAL"])
    error_message = "The API and the Regional domain use their enhanced TLS policies (APIGateway.11)."
  }

  assert {
    condition     = aws_api_gateway_base_path_mapping.this[0].stage_name == "prod" && aws_api_gateway_rest_api.this.disable_execute_api_endpoint && aws_api_gateway_stage.this.client_certificate_id == "abc123"
    error_message = "The domain maps to the stage and the execute-api endpoint is turned off."
  }

  assert {
    condition     = output.regional_domain_name == "d-abc123.execute-api.eu-west-1.amazonaws.com" && output.regional_zone_id == "ZLY8HYME6SFDD"
    error_message = "Route 53 alias targets are exported."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Public_API"
  }

  expect_failures = [var.name]
}

run "rejects_invalid_application" {
  command = plan

  variables {
    application = "Core"
  }

  expect_failures = [var.application]
}

run "rejects_invalid_environment" {
  command = plan

  variables {
    environment = "PROD"
  }

  expect_failures = [var.environment]
}

run "rejects_private_endpoint" {
  command = plan

  variables {
    endpoint_type = "PRIVATE"
  }

  expect_failures = [var.endpoint_type]
}

run "rejects_tls_1_0" {
  command = plan

  variables {
    tls = { security_policy = "TLS_1_0" }
  }

  expect_failures = [var.tls]
}

run "rejects_legacy_tls_1_2" {
  command = plan

  variables {
    tls = { security_policy = "TLS_1_2" }
  }

  expect_failures = [var.tls]
}

run "rejects_edge_policy_on_regional_api" {
  command = plan

  variables {
    tls = { security_policy = "SecurityPolicy_TLS13_2025_EDGE" }
  }

  expect_failures = [var.tls]
}

run "rejects_edge_policy_on_domain" {
  command = plan

  variables {
    tls = { domain_security_policy = "SecurityPolicy_TLS12_PFS_2025_EDGE" }
  }

  expect_failures = [var.tls]
}

run "rejects_unknown_access_mode" {
  command = plan

  variables {
    tls = { endpoint_access_mode = "LOOSE" }
  }

  expect_failures = [var.tls]
}

run "rejects_invalid_compression_size" {
  command = plan

  variables {
    minimum_compression_size = -1
  }

  expect_failures = [var.minimum_compression_size]
}

run "rejects_invalid_stage_name" {
  command = plan

  variables {
    stage = { name = "v1/beta" }
  }

  expect_failures = [var.stage]
}

run "rejects_invalid_cache_size" {
  command = plan

  variables {
    cache_cluster = { enabled = true, size = "2" }
  }

  expect_failures = [var.cache_cluster]
}

run "rejects_create_and_key_id" {
  command = plan

  variables {
    kms = { create = true, key_id = "11111111-2222-3333-4444-555555555555" }
  }

  expect_failures = [var.kms]
}

run "rejects_invalid_key_id" {
  command = plan

  variables {
    kms = { key_id = "alias/api" }
  }

  expect_failures = [var.kms]
}

run "rejects_execution_logging_off_level" {
  command = plan

  variables {
    execution_logging = { logging_level = "OFF" }
  }

  expect_failures = [var.execution_logging]
}

run "rejects_waf_without_acl" {
  command = plan

  variables {
    waf = { enabled = true }
  }

  expect_failures = [var.waf]
}

run "rejects_negative_throttling" {
  command = plan

  variables {
    method_settings = { throttling_rate_limit = -1 }
  }

  expect_failures = [var.method_settings]
}

run "rejects_authorizer_without_user_pool" {
  command = plan

  variables {
    authorizers = { cognito = { provider_arns = [] } }
  }

  expect_failures = [var.authorizers]
}

run "rejects_unqualified_authorizer_function" {
  command = plan

  variables {
    lambda_authorizers = { token = { invoke_arn = "x", alias_arn = "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-auth" } }
  }

  expect_failures = [var.lambda_authorizers]
}

run "rejects_trailing_slash_path" {
  command = plan

  variables {
    allow_unauthenticated_methods = true
    routes                        = { "/orders/" = { methods = { GET = { integration = { type = "MOCK" } } } } }
  }

  expect_failures = [var.routes]
}

run "rejects_invalid_verb" {
  command = plan

  variables {
    allow_unauthenticated_methods = true
    routes                        = { "/orders" = { methods = { get = { integration = { type = "MOCK" } } } } }
  }

  expect_failures = [var.routes]
}

run "rejects_unauthenticated_method" {
  command = plan

  variables {
    routes = { "/orders" = { methods = { GET = { integration = { type = "MOCK" } } } } }
  }

  expect_failures = [var.routes]
}

run "rejects_unknown_integration_type" {
  command = plan

  variables {
    allow_unauthenticated_methods = true
    routes                        = { "/orders" = { methods = { GET = { integration = { type = "VPC_LINK" } } } } }
  }

  expect_failures = [var.routes]
}

run "rejects_proxy_without_lambda" {
  command = plan

  variables {
    allow_unauthenticated_methods = true
    routes                        = { "/orders" = { methods = { GET = {} } } }
  }

  expect_failures = [var.routes]
}

run "rejects_unqualified_route_function" {
  command = plan

  variables {
    allow_unauthenticated_methods = true
    routes                        = { "/orders" = { methods = { GET = { lambda = { invoke_arn = "x", alias_arn = "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-orders" } } } } }
  }

  expect_failures = [var.routes]
}

run "rejects_invalid_model" {
  command = plan

  variables {
    models = { "order-v1" = "{}" }
  }

  expect_failures = [var.models]
}

run "rejects_credentials_with_any_origin" {
  command = plan

  variables {
    cors = { enabled = true, allow_credentials = true }
  }

  expect_failures = [var.cors]
}

run "rejects_domain_without_certificate" {
  command = plan

  variables {
    custom_domain = { enabled = true, domain_name = "api.example.com" }
  }

  expect_failures = [var.custom_domain]
}

run "rejects_clashing_authorizer_keys" {
  command = plan

  variables {
    authorizers = { auth = { provider_arns = ["arn:aws:cognito-idp:eu-west-1:123456789012:userpool/eu-west-1_AbCdEfGhI"] } }
    lambda_authorizers = {
      auth = {
        invoke_arn = "arn:aws:apigateway:eu-west-1:lambda:path/2015-03-31/functions/arn:aws:lambda:eu-west-1:123456789012:function:core-prod-auth:live/invocations"
        alias_arn  = "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-auth:live"
      }
    }
  }

  expect_failures = [aws_api_gateway_rest_api.this]
}

run "rejects_unknown_authorizer_key" {
  command = plan

  variables {
    routes = { "/orders" = { methods = { GET = { authorizer_key = "missing", integration = { type = "MOCK" } } } } }
  }

  expect_failures = [aws_api_gateway_rest_api.this]
}

run "rejects_unknown_request_model" {
  command = plan

  variables {
    allow_unauthenticated_methods = true
    routes                        = { "/orders" = { methods = { POST = { request_model = "Missing", integration = { type = "MOCK" } } } } }
  }

  expect_failures = [aws_api_gateway_rest_api.this]
}

run "rejects_unknown_request_validator" {
  command = plan

  variables {
    allow_unauthenticated_methods = true
    routes                        = { "/orders" = { methods = { POST = { request_validator = "missing", integration = { type = "MOCK" } } } } }
  }

  expect_failures = [aws_api_gateway_rest_api.this]
}

run "rejects_route_credentials_with_any_origin" {
  command = plan

  variables {
    allow_unauthenticated_methods = true
    routes                        = { "/orders" = { cors = { enabled = true, allow_credentials = true }, methods = { GET = { integration = { type = "MOCK" } } } } }
  }

  expect_failures = [aws_api_gateway_rest_api.this]
}

run "alarms_by_default" {
  command = plan

  assert {
    condition     = sort(keys(output.alarm_names)) == tolist(["apigw-api-4xx-rate", "apigw-api-5xx-rate", "apigw-api-integration-latency-p99", "apigw-api-latency-p99"])
    error_message = "Default alarms: 5XX and 4XX rates, p99 latency and p99 integration latency."
  }

  assert {
    condition     = alltrue([for n in values(output.alarm_names) : startswith(n, "core-prod-apigw-api-")]) && module.alarms[0].alarm_settings["apigw-api-latency-p99"].threshold == 2500
    error_message = "Alarm names start with the module base name; p99 latency at 2500 ms."
  }

  assert {
    condition     = alltrue([for k, r in module.alarms[0].alarm_routes : r.topic_arn == null])
    error_message = "Without topic_arns, alarms have no actions."
  }
}

run "alarms_off" {
  command = plan

  variables {
    alarms = { enabled = false }
  }

  assert {
    condition     = length(module.alarms) == 0 && length(output.alarm_names) == 0 && length(output.alarm_arns) == 0
    error_message = "alarms.enabled = false creates no alarms."
  }
}

run "alarms_tuned_and_routed" {
  command = apply

  variables {
    alarms = {
      topic_arns = {
        critical = "arn:aws:sns:eu-west-1:123456789012:platform-prod-critical"
        warning  = "arn:aws:sns:eu-west-1:123456789012:platform-prod-warning"
        info     = "arn:aws:sns:eu-west-1:123456789012:platform-prod-info"
      }
      overrides = {
        server_error_rate = { threshold = 2 }
        client_error_rate = { enabled = false }
      }
    }
  }

  assert {
    condition     = sort(keys(output.alarm_arns)) == tolist(["apigw-api-5xx-rate", "apigw-api-integration-latency-p99", "apigw-api-latency-p99"])
    error_message = "A disabled alarm is dropped."
  }

  assert {
    condition     = module.alarms[0].alarm_settings["apigw-api-5xx-rate"].threshold == 2 && module.alarms[0].alarm_settings["apigw-api-5xx-rate"].evaluation_periods == 3 && module.alarms[0].alarm_settings["apigw-api-integration-latency-p99"].threshold == 2000
    error_message = "Overrides change one setting; the rest keep the preset defaults."
  }

  assert {
    condition     = module.alarms[0].alarm_routes["apigw-api-5xx-rate"].topic_arn == "arn:aws:sns:eu-west-1:123456789012:platform-prod-critical" && module.alarms[0].alarm_routes["apigw-api-latency-p99"].topic_arn == "arn:aws:sns:eu-west-1:123456789012:platform-prod-warning"
    error_message = "Each alarm notifies the topic for its severity."
  }
}

run "alarms_plan_with_unknown_arns" {
  command = plan

  variables {
    kms = { create = true }
  }

  assert {
    condition     = length(module.alarms) == 1 && length(output.alarm_names) == 4
    error_message = "Alarm keys and names must be known at plan with a module key."
  }
}

run "rejects_invalid_alarm_topic" {
  command = plan

  variables {
    alarms = { topic_arns = { critical = "arn:aws:sqs:eu-west-1:123456789012:core-prod-critical" } }
  }

  expect_failures = [var.alarms]
}
