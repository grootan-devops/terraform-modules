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

  mock_resource "aws_apigatewayv2_api" {
    defaults = {
      id            = "a1b2c3d4e5"
      arn           = "arn:aws:apigateway:eu-west-1::/apis/a1b2c3d4e5"
      execution_arn = "arn:aws:execute-api:eu-west-1:123456789012:a1b2c3d4e5"
      api_endpoint  = "https://a1b2c3d4e5.execute-api.eu-west-1.amazonaws.com"
    }
  }

  mock_resource "aws_apigatewayv2_stage" {
    defaults = {
      id         = "$default"
      arn        = "arn:aws:apigateway:eu-west-1::/apis/a1b2c3d4e5/stages/$default"
      invoke_url = "https://a1b2c3d4e5.execute-api.eu-west-1.amazonaws.com/"
    }
  }

  mock_resource "aws_apigatewayv2_integration" {
    defaults = {
      id = "int0001"
    }
  }

  mock_resource "aws_apigatewayv2_authorizer" {
    defaults = {
      id = "auth01"
    }
  }

  mock_resource "aws_apigatewayv2_vpc_link" {
    defaults = {
      id = "vlink01"
    }
  }

  mock_resource "aws_security_group" {
    defaults = {
      id = "sg-0123456789abcdef0"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-west-1:123456789012:log-group:/aws/apigateway/core-prod/default/access"
    }
  }

  mock_resource "aws_apigatewayv2_domain_name" {
    defaults = {
      id = "api.example.com"
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
    condition     = aws_apigatewayv2_api.this.name == "core-prod" && aws_apigatewayv2_api.this.protocol_type == "HTTP" && aws_apigatewayv2_api.this.ip_address_type == "ipv4" && !aws_apigatewayv2_api.this.disable_execute_api_endpoint && length(aws_apigatewayv2_api.this.cors_configuration) == 0
    error_message = "An IPv4 HTTP API <application>-<environment> without CORS by default."
  }

  assert {
    condition     = aws_apigatewayv2_stage.this.name == "$default" && aws_apigatewayv2_stage.this.auto_deploy && length(aws_apigatewayv2_stage.this.route_settings) == 0
    error_message = "One auto-deployed $default stage."
  }

  assert {
    condition     = aws_apigatewayv2_stage.this.default_route_settings[0].throttling_burst_limit == 2000 && aws_apigatewayv2_stage.this.default_route_settings[0].throttling_rate_limit == 1000 && !aws_apigatewayv2_stage.this.default_route_settings[0].detailed_metrics_enabled
    error_message = "Stage throttling guardrails 2000 burst and 1000 rps, no detailed metrics."
  }

  assert {
    condition     = module.access_log_group.name == "/aws/apigateway/core-prod/default/access" && module.access_log_group.retention_in_days == 365 && module.access_log_group.kms_key_arn == null && output.kms_key_arn == null
    error_message = "Access logs go to /aws/apigateway/<api>/default/access for 365 days with service encryption."
  }

  assert {
    condition     = length(aws_apigatewayv2_integration.this) + length(aws_apigatewayv2_route.this) + length(aws_apigatewayv2_authorizer.this) + length(aws_lambda_permission.integrations) + length(aws_lambda_permission.authorizers) == 0
    error_message = "No integration, route, authorizer or permission by default."
  }

  assert {
    condition     = length(aws_apigatewayv2_vpc_link.this) + length(module.vpc_link_security_group) + length(aws_apigatewayv2_domain_name.this) + length(aws_apigatewayv2_api_mapping.this) == 0 && output.vpc_link_id == null && output.security_group_id == null && output.domain_target_name == null && output.domain_zone_id == null
    error_message = "No VPC link or custom domain by default."
  }

  assert {
    condition     = aws_apigatewayv2_api.this.tags["Name"] == "core-prod" && aws_apigatewayv2_api.this.tags["Team"] == "payments" && aws_apigatewayv2_api.this.tags["ManagedBy"] == "Terraform" && aws_apigatewayv2_stage.this.tags["Name"] == "core-prod-default" && aws_apigatewayv2_stage.this.tags["Team"] == "payments"
    error_message = "Caller and governance tags must be applied."
  }
}

run "access_log_wiring" {
  command = apply

  assert {
    condition     = aws_apigatewayv2_stage.this.access_log_settings[0].destination_arn == output.log_group_arn && output.log_group_arn == "arn:aws:logs:eu-west-1:123456789012:log-group:/aws/apigateway/core-prod/default/access" && output.log_group_name == "/aws/apigateway/core-prod/default/access"
    error_message = "The stage must log to the module access log group (APIGateway.9)."
  }

  assert {
    condition     = sort(keys(jsondecode(aws_apigatewayv2_stage.this.access_log_settings[0].format))) == sort(["requestId", "extendedRequestId", "ip", "requestTime", "httpMethod", "routeKey", "path", "status", "protocol", "responseLength", "responseLatency", "integrationLatency", "integrationErrorMessage", "authorizerError", "userAgent"])
    error_message = "The access log format must be JSON with the standard fields."
  }

  assert {
    condition     = jsondecode(aws_apigatewayv2_stage.this.access_log_settings[0].format).authorizerError == "$context.authorizer.error" && jsondecode(aws_apigatewayv2_stage.this.access_log_settings[0].format).ip == "$context.identity.sourceIp"
    error_message = "Access logs carry the authorizer error and source IP."
  }

  assert {
    condition     = output.id == "a1b2c3d4e5" && output.arn == "arn:aws:apigateway:eu-west-1::/apis/a1b2c3d4e5" && output.name == "core-prod" && output.execution_arn == "arn:aws:execute-api:eu-west-1:123456789012:a1b2c3d4e5" && output.api_endpoint == "https://a1b2c3d4e5.execute-api.eu-west-1.amazonaws.com"
    error_message = "Outputs must expose the API."
  }

  assert {
    condition     = output.stage_name == "$default" && output.invoke_url == "https://a1b2c3d4e5.execute-api.eu-west-1.amazonaws.com/" && output.authorizer_ids == {}
    error_message = "Outputs must expose the stage (alarm dimensions ApiId and Stage)."
  }
}

run "lambda_integrations_and_authorizers" {
  command   = apply
  state_key = "lambda"

  variables {
    integrations = {
      items  = { type = "lambda", lambda = { function_arn = "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-items:live" } }
      health = { type = "lambda", lambda = { function_arn = "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-health" }, timeout_milliseconds = 5000 }
    }
    authorizers = {
      cognito = { jwt = { issuer = "https://cognito-idp.eu-west-1.amazonaws.com/eu-west-1_AbCdEfGhI", audience = ["client-1"] } }
      token   = { lambda = { function_arn = "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-auth:live" } }
    }
    routes = {
      "GET /items"       = { integration = "items", authorizer = "cognito", authorization_scopes = ["items/read"] }
      "POST /items/{id}" = { integration = "items", authorizer = "token" }
      "GET /health"      = { integration = "health", authorization = "NONE" }
    }
  }

  assert {
    condition     = aws_apigatewayv2_integration.this["items"].integration_type == "AWS_PROXY" && aws_apigatewayv2_integration.this["items"].integration_uri == "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-items:live" && aws_apigatewayv2_integration.this["items"].integration_method == "POST" && aws_apigatewayv2_integration.this["items"].payload_format_version == "2.0"
    error_message = "Lambda integrations use AWS_PROXY with payload 2.0 on the given ARN."
  }

  assert {
    condition     = aws_apigatewayv2_integration.this["items"].timeout_milliseconds == 30000 && aws_apigatewayv2_integration.this["health"].timeout_milliseconds == 5000 && aws_apigatewayv2_integration.this["items"].connection_type == "INTERNET" && length(aws_apigatewayv2_integration.this["items"].tls_config) == 0
    error_message = "Timeouts default to 30 s and are overridable."
  }

  assert {
    condition     = aws_lambda_permission.integrations["items"].function_name == "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-items" && aws_lambda_permission.integrations["items"].qualifier == "live" && aws_lambda_permission.integrations["items"].principal == "apigateway.amazonaws.com" && aws_lambda_permission.integrations["items"].source_arn == "arn:aws:execute-api:eu-west-1:123456789012:a1b2c3d4e5/*"
    error_message = "Integration permissions target the alias and this API only."
  }

  assert {
    condition     = aws_lambda_permission.integrations["health"].function_name == "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-health" && aws_lambda_permission.integrations["health"].qualifier == null && length(aws_lambda_permission.integrations["items"].statement_id) <= 100 && aws_lambda_permission.integrations["items"].statement_id != aws_lambda_permission.integrations["health"].statement_id
    error_message = "Unqualified function ARNs get no qualifier; statement IDs are unique."
  }

  assert {
    condition     = aws_apigatewayv2_authorizer.this["cognito"].authorizer_type == "JWT" && aws_apigatewayv2_authorizer.this["cognito"].jwt_configuration[0].issuer == "https://cognito-idp.eu-west-1.amazonaws.com/eu-west-1_AbCdEfGhI" && aws_apigatewayv2_authorizer.this["cognito"].jwt_configuration[0].audience == toset(["client-1"]) && aws_apigatewayv2_authorizer.this["cognito"].identity_sources == toset(["$request.header.Authorization"]) && aws_apigatewayv2_authorizer.this["cognito"].authorizer_uri == null
    error_message = "JWT authorizers take the issuer and audience."
  }

  assert {
    condition     = aws_apigatewayv2_authorizer.this["token"].authorizer_type == "REQUEST" && aws_apigatewayv2_authorizer.this["token"].authorizer_uri == "arn:aws:apigateway:eu-west-1:lambda:path/2015-03-31/functions/arn:aws:lambda:eu-west-1:123456789012:function:core-prod-auth:live/invocations" && aws_apigatewayv2_authorizer.this["token"].authorizer_payload_format_version == "2.0" && aws_apigatewayv2_authorizer.this["token"].enable_simple_responses && aws_apigatewayv2_authorizer.this["token"].authorizer_result_ttl_in_seconds == 300 && aws_apigatewayv2_authorizer.this["token"].identity_sources == toset(["$request.header.Authorization"])
    error_message = "Lambda authorizers are REQUEST authorizers with payload 2.0, simple responses and a 300 s cache."
  }

  assert {
    condition     = aws_lambda_permission.authorizers["token"].function_name == "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-auth" && aws_lambda_permission.authorizers["token"].qualifier == "live" && aws_lambda_permission.authorizers["token"].source_arn == "arn:aws:execute-api:eu-west-1:123456789012:a1b2c3d4e5/authorizers/auth01" && keys(aws_lambda_permission.authorizers) == ["token"]
    error_message = "Authorizer permissions are scoped to their authorizer."
  }

  assert {
    condition     = aws_apigatewayv2_route.this["GET /items"].authorization_type == "JWT" && aws_apigatewayv2_route.this["GET /items"].authorizer_id == "auth01" && aws_apigatewayv2_route.this["GET /items"].authorization_scopes == toset(["items/read"]) && aws_apigatewayv2_route.this["GET /items"].target == "integrations/int0001"
    error_message = "JWT routes use their authorizer, scopes and integration."
  }

  assert {
    condition     = aws_apigatewayv2_route.this["POST /items/{id}"].authorization_type == "CUSTOM" && aws_apigatewayv2_route.this["POST /items/{id}"].authorizer_id == "auth01" && aws_apigatewayv2_route.this["GET /health"].authorization_type == "NONE" && aws_apigatewayv2_route.this["GET /health"].authorizer_id == null
    error_message = "Lambda authorizer routes are CUSTOM; NONE is explicit."
  }

  assert {
    condition     = output.authorizer_ids == { cognito = "auth01", token = "auth01" }
    error_message = "Authorizer IDs are exported by key."
  }
}

run "http_and_private_integrations" {
  command   = apply
  state_key = "private"

  variables {
    vpc_link = {
      enabled    = true
      vpc_id     = "vpc-0123456789abcdef0"
      subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]
      security_group = {
        egress_security_group_ids     = ["sg-0aaaaaaaaaaaaaaaa"]
        egress_cidr_blocks            = ["10.0.0.0/16"]
        additional_security_group_ids = ["sg-0bbbbbbbbbbbbbbbb"]
      }
    }
    integrations = {
      legacy = { type = "http", uri = "https://legacy.example.com/{proxy}", method = "GET", request_parameters = { "append:header.x-source" = "api" } }
      orders = { type = "private", listener_arn = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:listener/app/core-prod/0123456789abcdef/0123456789abcdef", tls_server_name = "orders.internal.example.com" }
    }
    routes = {
      "GET /legacy/{proxy+}" = { integration = "legacy", authorization = "AWS_IAM" }
      "ANY /orders"          = { integration = "orders", authorization = "AWS_IAM" }
    }
  }

  assert {
    condition     = aws_apigatewayv2_integration.this["legacy"].integration_type == "HTTP_PROXY" && aws_apigatewayv2_integration.this["legacy"].integration_uri == "https://legacy.example.com/{proxy}" && aws_apigatewayv2_integration.this["legacy"].integration_method == "GET" && aws_apigatewayv2_integration.this["legacy"].payload_format_version == "1.0" && aws_apigatewayv2_integration.this["legacy"].connection_type == "INTERNET" && aws_apigatewayv2_integration.this["legacy"].request_parameters["append:header.x-source"] == "api"
    error_message = "HTTP integrations proxy to their https URI with the method."
  }

  assert {
    condition     = aws_apigatewayv2_integration.this["orders"].integration_type == "HTTP_PROXY" && aws_apigatewayv2_integration.this["orders"].connection_type == "VPC_LINK" && aws_apigatewayv2_integration.this["orders"].connection_id == "vlink01" && aws_apigatewayv2_integration.this["orders"].integration_method == "ANY" && aws_apigatewayv2_integration.this["orders"].integration_uri == "arn:aws:elasticloadbalancing:eu-west-1:123456789012:listener/app/core-prod/0123456789abcdef/0123456789abcdef"
    error_message = "Private integrations go through the module VPC link to the listener."
  }

  assert {
    condition     = aws_apigatewayv2_integration.this["orders"].tls_config[0].server_name_to_verify == "orders.internal.example.com"
    error_message = "Private integrations use TLS (APIGateway.10)."
  }

  assert {
    condition     = aws_apigatewayv2_vpc_link.this[0].name == "core-prod" && aws_apigatewayv2_vpc_link.this[0].subnet_ids == toset(["subnet-0123456789abcdef0", "subnet-0123456789abcdef1"]) && aws_apigatewayv2_vpc_link.this[0].security_group_ids == toset(["sg-0123456789abcdef0", "sg-0bbbbbbbbbbbbbbbb"]) && aws_apigatewayv2_vpc_link.this[0].tags["Team"] == "payments"
    error_message = "The VPC link uses the subnets, its security group and the extra groups."
  }

  assert {
    condition     = sort(keys(module.vpc_link_security_group[0].egress_rule_ids)) == tolist(["cidr-0", "sg-0"]) && length(module.vpc_link_security_group[0].ingress_rule_ids) == 0
    error_message = "The VPC link group has only the listed egress rules."
  }

  assert {
    condition     = output.vpc_link_id == "vlink01" && output.security_group_id == "sg-0123456789abcdef0" && length(aws_lambda_permission.integrations) == 0
    error_message = "VPC link and security group IDs are exported; no Lambda permission."
  }

  assert {
    condition     = aws_apigatewayv2_route.this["ANY /orders"].authorization_type == "AWS_IAM" && aws_apigatewayv2_route.this["GET /legacy/{proxy+}"].authorizer_id == null
    error_message = "AWS_IAM routes need no authorizer."
  }
}

run "vpc_link_with_caller_groups" {
  command   = plan
  state_key = "callersg"

  variables {
    vpc_link = {
      enabled        = true
      subnet_ids     = ["subnet-0123456789abcdef0"]
      security_group = { create = false, additional_security_group_ids = ["sg-0bbbbbbbbbbbbbbbb"] }
    }
  }

  assert {
    condition     = length(module.vpc_link_security_group) == 0 && aws_apigatewayv2_vpc_link.this[0].security_group_ids == toset(["sg-0bbbbbbbbbbbbbbbb"])
    error_message = "security_group.create = false uses only the caller groups."
  }
}

run "route_throttling_and_metrics" {
  command   = plan
  state_key = "throttle"

  variables {
    throttling       = { burst_limit = 100, rate_limit = 50 }
    detailed_metrics = true
    integrations = {
      items = { type = "lambda", lambda = { function_arn = "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-items:live" } }
    }
    routes = {
      "$default"    = { integration = "items", authorization = "AWS_IAM" }
      "POST /items" = { integration = "items", authorization = "AWS_IAM", throttling = { burst_limit = 10, rate_limit = 5 } }
    }
  }

  assert {
    condition     = aws_apigatewayv2_stage.this.default_route_settings[0].throttling_burst_limit == 100 && aws_apigatewayv2_stage.this.default_route_settings[0].throttling_rate_limit == 50 && aws_apigatewayv2_stage.this.default_route_settings[0].detailed_metrics_enabled
    error_message = "Stage throttling and detailed metrics are configurable."
  }

  assert {
    condition     = length(aws_apigatewayv2_stage.this.route_settings) == 1 && one(aws_apigatewayv2_stage.this.route_settings).route_key == "POST /items" && one(aws_apigatewayv2_stage.this.route_settings).throttling_rate_limit == 5 && one(aws_apigatewayv2_stage.this.route_settings).throttling_burst_limit == 10 && one(aws_apigatewayv2_stage.this.route_settings).detailed_metrics_enabled
    error_message = "Routes with throttling get route settings."
  }

  assert {
    condition     = aws_apigatewayv2_route.this["$default"].route_key == "$default" && aws_apigatewayv2_route.this["$default"].authorization_type == "AWS_IAM"
    error_message = "The $default route is supported."
  }
}

run "cors" {
  command   = plan
  state_key = "cors"

  variables {
    cors = {
      enabled           = true
      allow_origins     = ["https://app.example.com"]
      allow_credentials = true
      expose_headers    = ["X-Request-Id"]
      max_age           = 600
    }
  }

  assert {
    condition     = aws_apigatewayv2_api.this.cors_configuration[0].allow_origins == toset(["https://app.example.com"]) && aws_apigatewayv2_api.this.cors_configuration[0].allow_credentials && aws_apigatewayv2_api.this.cors_configuration[0].max_age == 600
    error_message = "CORS takes explicit origins and credentials."
  }

  assert {
    condition     = aws_apigatewayv2_api.this.cors_configuration[0].allow_methods == toset(["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]) && contains(aws_apigatewayv2_api.this.cors_configuration[0].allow_headers, "Authorization") && aws_apigatewayv2_api.this.cors_configuration[0].expose_headers == toset(["X-Request-Id"])
    error_message = "CORS methods and headers default sensibly."
  }
}

run "custom_domain" {
  command   = apply
  state_key = "domain"

  variables {
    ip_address_type = "dualstack"
    domain = {
      enabled         = true
      name            = "api.example.com"
      certificate_arn = "arn:aws:acm:eu-west-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
      base_path       = "v1"
    }
  }

  assert {
    condition     = aws_apigatewayv2_domain_name.this[0].domain_name == "api.example.com" && aws_apigatewayv2_domain_name.this[0].domain_name_configuration[0].endpoint_type == "REGIONAL" && aws_apigatewayv2_domain_name.this[0].domain_name_configuration[0].security_policy == "TLS_1_2" && aws_apigatewayv2_domain_name.this[0].domain_name_configuration[0].ip_address_type == "dualstack" && length(aws_apigatewayv2_domain_name.this[0].mutual_tls_authentication) == 0
    error_message = "A Regional TLS 1.2 domain on the API's IP address type."
  }

  assert {
    condition     = aws_apigatewayv2_api_mapping.this[0].stage == "$default" && aws_apigatewayv2_api_mapping.this[0].api_mapping_key == "v1" && aws_apigatewayv2_api_mapping.this[0].domain_name == "api.example.com" && aws_apigatewayv2_api_mapping.this[0].api_id == "a1b2c3d4e5"
    error_message = "The domain maps the $default stage under the base path."
  }

  assert {
    condition     = aws_apigatewayv2_api.this.disable_execute_api_endpoint && aws_apigatewayv2_api.this.ip_address_type == "dualstack"
    error_message = "A custom domain turns the execute-api endpoint off."
  }

  assert {
    condition     = output.domain_target_name != null && output.domain_zone_id != null && aws_apigatewayv2_domain_name.this[0].tags["Name"] == "api.example.com"
    error_message = "Route 53 alias targets are exported."
  }
}

run "mutual_tls" {
  command   = plan
  state_key = "mtls"

  variables {
    domain = {
      enabled         = true
      name            = "api.example.com"
      certificate_arn = "arn:aws:acm:eu-west-1:123456789012:certificate/12345678-1234-1234-1234-123456789012"
      mutual_tls      = { enabled = true, truststore_uri = "s3://core-prod-truststore/truststore.pem", truststore_version = "abc123" }
    }
  }

  assert {
    condition     = aws_apigatewayv2_domain_name.this[0].mutual_tls_authentication[0].truststore_uri == "s3://core-prod-truststore/truststore.pem" && aws_apigatewayv2_domain_name.this[0].mutual_tls_authentication[0].truststore_version == "abc123" && aws_apigatewayv2_api_mapping.this[0].api_mapping_key == null
    error_message = "Mutual TLS uses the truststore."
  }
}

run "module_key_is_planned_safely" {
  command   = plan
  state_key = "kmsplan"

  variables {
    kms = { create = true }
    vpc_link = {
      enabled        = true
      vpc_id         = "vpc-0123456789abcdef0"
      subnet_ids     = ["subnet-0123456789abcdef0"]
      security_group = { egress_cidr_blocks = ["10.0.0.0/16"] }
    }
    integrations = {
      orders = { type = "private", listener_arn = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:listener/app/core-prod/0123456789abcdef/0123456789abcdef", tls_server_name = "orders.internal.example.com" }
      items  = { type = "lambda", lambda = { function_arn = "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-items:live" } }
    }
    authorizers = {
      token = { lambda = { function_arn = "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-auth:live" } }
    }
    routes = {
      "GET /orders" = { integration = "orders", authorizer = "token" }
      "GET /items"  = { integration = "items", authorizer = "token" }
    }
  }

  assert {
    condition     = module.encryption.created && length(aws_lambda_permission.integrations) == 1 && length(aws_lambda_permission.authorizers) == 1 && length(aws_apigatewayv2_vpc_link.this) == 1
    error_message = "kms.create and unknown IDs must plan."
  }
}

run "module_key_encrypts_logs" {
  command   = apply
  state_key = "kms"

  variables {
    kms = { create = true }
  }

  assert {
    condition     = module.access_log_group.kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && output.kms_key_arn == module.access_log_group.kms_key_arn
    error_message = "The module key must encrypt the access logs."
  }
}

run "caller_key_id_and_log_overrides" {
  command   = plan
  state_key = "keyid"

  variables {
    kms = { key_id = "11111111-2222-3333-4444-555555555555" }
    cloudwatch_logs = {
      kms_key_arn       = "arn:aws:kms:eu-west-1:123456789012:key/99999999-2222-3333-4444-555555555555"
      retention_in_days = 731
      access_log_format = "$context.requestId $context.status"
    }
  }

  assert {
    condition     = output.kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && module.access_log_group.kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/99999999-2222-3333-4444-555555555555" && module.access_log_group.retention_in_days == 731
    error_message = "A key ID becomes the key ARN; cloudwatch_logs overrides the log key and retention."
  }

  assert {
    condition     = aws_apigatewayv2_stage.this.access_log_settings[0].format == "$context.requestId $context.status"
    error_message = "cloudwatch_logs.access_log_format overrides the format."
  }
}

run "named_instance" {
  command   = plan
  state_key = "named"

  variables {
    name        = "public"
    description = "Public API"
  }

  assert {
    condition     = aws_apigatewayv2_api.this.name == "core-prod-public" && aws_apigatewayv2_api.this.description == "Public API" && module.access_log_group.name == "/aws/apigateway/core-prod-public/default/access" && aws_apigatewayv2_api.this.tags["Name"] == "core-prod-public"
    error_message = "name shapes the API and log group names."
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

run "rejects_invalid_ip_address_type" {
  command = plan

  variables {
    ip_address_type = "ipv6"
  }

  expect_failures = [var.ip_address_type]
}

run "rejects_unknown_integration_type" {
  command = plan

  variables {
    integrations = { items = { type = "mock" } }
  }

  expect_failures = [var.integrations]
}

run "rejects_integration_without_target" {
  command = plan

  variables {
    integrations = { items = { type = "lambda", uri = "https://example.com" } }
  }

  expect_failures = [var.integrations]
}

run "rejects_private_without_tls" {
  command = plan

  variables {
    vpc_link     = { enabled = true, vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0123456789abcdef0"], security_group = { egress_cidr_blocks = ["10.0.0.0/16"] } }
    integrations = { orders = { type = "private", listener_arn = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:listener/app/core-prod/0123456789abcdef/0123456789abcdef" } }
  }

  expect_failures = [var.integrations]
}

run "rejects_private_without_vpc_link" {
  command = plan

  variables {
    integrations = { orders = { type = "private", listener_arn = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:listener/app/core-prod/0123456789abcdef/0123456789abcdef", tls_server_name = "orders.internal.example.com" } }
  }

  expect_failures = [var.integrations]
}

run "rejects_invalid_function_arn" {
  command = plan

  variables {
    integrations = { items = { type = "lambda", lambda = { function_arn = "arn:aws:apigateway:eu-west-1:lambda:path/2015-03-31/functions/x/invocations" } } }
  }

  expect_failures = [var.integrations]
}

run "rejects_plain_http_uri" {
  command = plan

  variables {
    integrations = { legacy = { type = "http", uri = "http://legacy.example.com" } }
  }

  expect_failures = [var.integrations]
}

run "rejects_invalid_integration_method" {
  command = plan

  variables {
    integrations = { legacy = { type = "http", uri = "https://legacy.example.com", method = "get" } }
  }

  expect_failures = [var.integrations]
}

run "rejects_invalid_timeout" {
  command = plan

  variables {
    integrations = { legacy = { type = "http", uri = "https://legacy.example.com", timeout_milliseconds = 30001 } }
  }

  expect_failures = [var.integrations]
}

run "rejects_authorizer_with_both_types" {
  command = plan

  variables {
    authorizers = {
      auth = {
        jwt    = { issuer = "https://issuer.example.com", audience = ["a"] }
        lambda = { function_arn = "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-auth" }
      }
    }
  }

  expect_failures = [var.authorizers]
}

run "rejects_http_issuer" {
  command = plan

  variables {
    authorizers = { auth = { jwt = { issuer = "http://issuer.example.com", audience = ["a"] } } }
  }

  expect_failures = [var.authorizers]
}

run "rejects_empty_audience" {
  command = plan

  variables {
    authorizers = { auth = { jwt = { issuer = "https://issuer.example.com", audience = [] } } }
  }

  expect_failures = [var.authorizers]
}

run "rejects_invalid_authorizer_function" {
  command = plan

  variables {
    authorizers = { auth = { lambda = { function_arn = "core-prod-auth" } } }
  }

  expect_failures = [var.authorizers]
}

run "rejects_invalid_authorizer_ttl" {
  command = plan

  variables {
    authorizers = { auth = { lambda = { function_arn = "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-auth", result_ttl_seconds = 3601 } } }
  }

  expect_failures = [var.authorizers]
}

run "rejects_cache_without_identity_sources" {
  command = plan

  variables {
    authorizers = { auth = { lambda = { function_arn = "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-auth", identity_sources = [] } } }
  }

  expect_failures = [var.authorizers]
}

run "rejects_simple_responses_on_payload_1" {
  command = plan

  variables {
    authorizers = { auth = { lambda = { function_arn = "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-auth", payload_format_version = "1.0" } } }
  }

  expect_failures = [var.authorizers]
}

run "rejects_invalid_route_key" {
  command = plan

  variables {
    integrations = { items = { type = "http", uri = "https://items.example.com" } }
    routes       = { "/items" = { integration = "items", authorization = "NONE" } }
  }

  expect_failures = [var.routes]
}

run "rejects_unknown_route_integration" {
  command = plan

  variables {
    routes = { "GET /items" = { integration = "missing", authorization = "NONE" } }
  }

  expect_failures = [var.routes]
}

run "rejects_route_without_authorization" {
  command = plan

  variables {
    integrations = { items = { type = "http", uri = "https://items.example.com" } }
    routes       = { "GET /items" = { integration = "items" } }
  }

  expect_failures = [var.routes]
}

run "rejects_invalid_route_authorization" {
  command = plan

  variables {
    integrations = { items = { type = "http", uri = "https://items.example.com" } }
    routes       = { "GET /items" = { integration = "items", authorization = "JWT" } }
  }

  expect_failures = [var.routes]
}

run "rejects_unknown_route_authorizer" {
  command = plan

  variables {
    integrations = { items = { type = "http", uri = "https://items.example.com" } }
    routes       = { "GET /items" = { integration = "items", authorizer = "missing" } }
  }

  expect_failures = [var.routes]
}

run "rejects_scopes_without_jwt" {
  command = plan

  variables {
    integrations = { items = { type = "http", uri = "https://items.example.com" } }
    routes       = { "GET /items" = { integration = "items", authorization = "AWS_IAM", authorization_scopes = ["items/read"] } }
  }

  expect_failures = [var.routes]
}

run "rejects_negative_route_throttling" {
  command = plan

  variables {
    integrations = { items = { type = "http", uri = "https://items.example.com" } }
    routes       = { "GET /items" = { integration = "items", authorization = "AWS_IAM", throttling = { burst_limit = -1, rate_limit = 1 } } }
  }

  expect_failures = [var.routes]
}

run "rejects_cors_without_origins" {
  command = plan

  variables {
    cors = { enabled = true }
  }

  expect_failures = [var.cors]
}

run "rejects_credentials_with_any_origin" {
  command = plan

  variables {
    cors = { enabled = true, allow_origins = ["*"], allow_credentials = true }
  }

  expect_failures = [var.cors]
}

run "rejects_invalid_cors_max_age" {
  command = plan

  variables {
    cors = { enabled = true, allow_origins = ["https://app.example.com"], max_age = 86401 }
  }

  expect_failures = [var.cors]
}

run "rejects_negative_throttling" {
  command = plan

  variables {
    throttling = { rate_limit = -1 }
  }

  expect_failures = [var.throttling]
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

run "rejects_vpc_link_without_subnets" {
  command = plan

  variables {
    vpc_link = { enabled = true, vpc_id = "vpc-0123456789abcdef0", security_group = { egress_cidr_blocks = ["10.0.0.0/16"] } }
  }

  expect_failures = [var.vpc_link]
}

run "rejects_vpc_link_without_vpc_id" {
  command = plan

  variables {
    vpc_link = { enabled = true, subnet_ids = ["subnet-0123456789abcdef0"], security_group = { egress_cidr_blocks = ["10.0.0.0/16"] } }
  }

  expect_failures = [var.vpc_link]
}

run "rejects_vpc_link_without_egress" {
  command = plan

  variables {
    vpc_link = { enabled = true, vpc_id = "vpc-0123456789abcdef0", subnet_ids = ["subnet-0123456789abcdef0"] }
  }

  expect_failures = [var.vpc_link]
}

run "rejects_vpc_link_without_groups" {
  command = plan

  variables {
    vpc_link = { enabled = true, subnet_ids = ["subnet-0123456789abcdef0"], security_group = { create = false } }
  }

  expect_failures = [var.vpc_link]
}

run "rejects_domain_without_certificate" {
  command = plan

  variables {
    domain = { enabled = true, name = "api.example.com" }
  }

  expect_failures = [var.domain]
}

run "rejects_enhanced_security_policy" {
  command = plan

  variables {
    domain = { enabled = true, name = "api.example.com", certificate_arn = "arn:aws:acm:eu-west-1:123456789012:certificate/12345678-1234-1234-1234-123456789012", security_policy = "SecurityPolicy_TLS13_1_3_2025_09" }
  }

  expect_failures = [var.domain]
}

run "rejects_invalid_base_path" {
  command = plan

  variables {
    domain = { enabled = true, name = "api.example.com", certificate_arn = "arn:aws:acm:eu-west-1:123456789012:certificate/12345678-1234-1234-1234-123456789012", base_path = "/v1" }
  }

  expect_failures = [var.domain]
}

run "rejects_mutual_tls_without_truststore" {
  command = plan

  variables {
    domain = { enabled = true, name = "api.example.com", certificate_arn = "arn:aws:acm:eu-west-1:123456789012:certificate/12345678-1234-1234-1234-123456789012", mutual_tls = { enabled = true } }
  }

  expect_failures = [var.domain]
}
