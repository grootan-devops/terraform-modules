variable "application" {
  description = "The name of the product/application."
  type        = string

  validation {
    condition     = length(trimspace(var.application)) > 0
    error_message = "application must not be empty."
  }
}

variable "environment" {
  description = "The environment suffix for resources, for example dev, staging, or prod."
  type        = string

  validation {
    condition     = length(trimspace(var.environment)) > 0
    error_message = "environment must not be empty."
  }
}

variable "minimum_compression_size" {
  description = "Minimum response size in bytes before API Gateway compression is applied. Use null to disable."
  type        = number
  default     = null
}

variable "endpoint_type" {
  description = "Endpoint type for the REST API. Valid values are REGIONAL, EDGE, or PRIVATE."
  type        = string
  default     = "REGIONAL"

  validation {
    condition     = contains(["REGIONAL", "EDGE", "PRIVATE"], upper(var.endpoint_type))
    error_message = "endpoint_type must be REGIONAL, EDGE, or PRIVATE."
  }
}

variable "tracing_enabled" {
  description = "Whether to enable API Gateway X-Ray tracing on the managed stage."
  type        = bool
  default     = true
}

variable "access_logs" {
  description = "Mandatory managed API Gateway stage access log configuration."
  type = object({
    retention_in_days = optional(number, 30)
    kms_key_id        = optional(string)
    log_group_class   = optional(string, "STANDARD")
    format            = optional(string)
  })
  default = {}
}

variable "rate_limiting" {
  description = "Default API Gateway method throttling applied to all methods."
  type = object({
    burst_limit = optional(number)
    rate_limit  = optional(number)
  })
  default = {}

  validation {
    condition     = try(var.rate_limiting.burst_limit == null || var.rate_limiting.burst_limit >= 0, true)
    error_message = "rate_limiting.burst_limit must be greater than or equal to 0 when set."
  }

  validation {
    condition     = try(var.rate_limiting.rate_limit == null || var.rate_limiting.rate_limit >= 0, true)
    error_message = "rate_limiting.rate_limit must be greater than or equal to 0 when set."
  }
}

variable "waf_web_acl_arn" {
  description = "Optional AWS WAFv2 Web ACL ARN to associate with the API Gateway stage."
  type        = string
  default     = null

  validation {
    condition     = try(var.waf_web_acl_arn == null || length(trimspace(var.waf_web_acl_arn)) > 0, true)
    error_message = "waf_web_acl_arn must not be empty when set."
  }
}

variable "authorizers" {
  description = "Map of Cognito user-pool API Gateway authorizers."
  type = map(object({
    name                             = optional(string)
    provider_arns                    = optional(list(string), [])
    identity_source                  = optional(string)
    authorizer_result_ttl_in_seconds = optional(number)
  }))
  default = {}
}

variable "lambda_authorizers" {
  description = "Map of Lambda REQUEST authorizers (accept JWT or API key)."
  type = map(object({
    lambda_alias_arn                 = string
    identity_source                  = optional(string, "method.request.header.Authorization, method.request.header.x-api-key")
    authorizer_result_ttl_in_seconds = optional(number, 300)
  }))
  default = {}
}

variable "routes" {
  description = "Map of route paths to method definitions."
  type = map(object({
    cors = optional(object({
      enabled           = optional(bool)
      allow_origins     = optional(list(string))
      allow_methods     = optional(list(string))
      allow_headers     = optional(list(string))
      allow_credentials = optional(bool)
      max_age           = optional(number)
    }))
    rate_limiting = optional(object({
      burst_limit = optional(number)
      rate_limit  = optional(number)
    }))
    method_settings = optional(object({
      metrics_enabled                            = optional(bool)
      logging_level                              = optional(string)
      data_trace_enabled                         = optional(bool)
      throttling_burst_limit                     = optional(number)
      throttling_rate_limit                      = optional(number)
      caching_enabled                            = optional(bool)
      cache_ttl_in_seconds                       = optional(number)
      cache_data_encrypted                       = optional(bool)
      require_authorization_for_cache_control    = optional(bool)
      unauthorized_cache_control_header_strategy = optional(string)
    }))
    methods = map(object({
      lambda_function_arn   = optional(string)
      authorizer_key        = optional(string)
      request_parameters    = optional(map(bool), {})
      request_model_key     = optional(string)
      request_validator_key = optional(string)
      operation_name        = optional(string)
      rate_limiting = optional(object({
        burst_limit = optional(number)
        rate_limit  = optional(number)
      }))
      method_settings = optional(object({
        metrics_enabled                            = optional(bool)
        logging_level                              = optional(string)
        data_trace_enabled                         = optional(bool)
        throttling_burst_limit                     = optional(number)
        throttling_rate_limit                      = optional(number)
        caching_enabled                            = optional(bool)
        cache_ttl_in_seconds                       = optional(number)
        cache_data_encrypted                       = optional(bool)
        require_authorization_for_cache_control    = optional(bool)
        unauthorized_cache_control_header_strategy = optional(string)
      }))
      integration = optional(object({
        type                    = optional(string, "AWS_PROXY")
        integration_http_method = optional(string)
        uri                     = optional(string)
        integration_target      = optional(string)
        connection_type         = optional(string)
        connection_id           = optional(string)
        request_parameters      = optional(map(string), {})
        request_templates       = optional(map(string), {})
        passthrough_behavior    = optional(string)
        cache_key_parameters    = optional(list(string), [])
        cache_namespace         = optional(string)
        content_handling        = optional(string)
        timeout_milliseconds    = optional(number)
        response_transfer_mode  = optional(string)
        tls_config = optional(object({
          insecure_skip_verification = optional(bool)
        }))
      }), {})
      method_responses = optional(map(object({
        response_models     = optional(map(string), {})
        response_parameters = optional(map(bool), {})
      })), {})
      integration_responses = optional(map(object({
        selection_pattern   = optional(string)
        response_parameters = optional(map(string), {})
        response_templates  = optional(map(string), {})
        content_handling    = optional(string)
      })), {})
    }))
  }))
  default = {}

  validation {
    condition     = alltrue([for path in keys(var.routes) : startswith(path, "/")])
    error_message = "All route paths must start with /."
  }

  validation {
    condition     = alltrue([for path in keys(var.routes) : path == "/" || !endswith(path, "/")])
    error_message = "Route paths must not end with / unless the route is exactly /."
  }

  validation {
    condition = alltrue(flatten([
      for _, route in var.routes : [
        for method in keys(route.methods) : contains(["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD", "ANY"], upper(method))
      ]
    ]))
    error_message = "Route method names must be valid HTTP methods: GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD, or ANY."
  }

  validation {
    condition = alltrue(flatten([
      for _, route in var.routes : concat(
        [
          try(route.rate_limiting.burst_limit == null || route.rate_limiting.burst_limit >= 0, true),
          try(route.rate_limiting.rate_limit == null || route.rate_limiting.rate_limit >= 0, true)
        ],
        [
          for _, method in route.methods : try(method.rate_limiting.burst_limit == null || method.rate_limiting.burst_limit >= 0, true)
        ],
        [
          for _, method in route.methods : try(method.rate_limiting.rate_limit == null || method.rate_limiting.rate_limit >= 0, true)
        ]
      )
    ]))
    error_message = "Route and method rate limiting values must be greater than or equal to 0 when set."
  }
}

variable "models" {
  description = "Map of API Gateway request/response models."
  type = map(object({
    name         = string
    description  = optional(string)
    content_type = optional(string, "application/json")
    schema       = string
  }))
  default = {}
}

variable "request_validators" {
  description = "Map of API Gateway request validators."
  type = map(object({
    name                        = string
    validate_request_body       = optional(bool, false)
    validate_request_parameters = optional(bool, false)
  }))
  default = {}
}

variable "cors" {
  description = "Default automatic CORS support using MOCK OPTIONS methods. Routes can override these values."
  type = object({
    enabled           = optional(bool, false)
    allow_origins     = optional(list(string), ["*"])
    allow_methods     = optional(list(string), ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"])
    allow_headers     = optional(list(string), ["Content-Type", "Authorization", "X-Amz-Date", "X-Amz-Security-Token"])
    allow_credentials = optional(bool, false)
    max_age           = optional(number, 86400)
  })
  default = {}

  validation {
    condition     = !(var.cors.enabled && var.cors.allow_credentials && contains(var.cors.allow_origins, "*"))
    error_message = "cors.allow_credentials cannot be true when cors.allow_origins contains *."
  }
}

variable "stage" {
  description = "Stage configuration."
  type = object({
    stage_name            = optional(string)
    description           = optional(string)
    variables             = optional(map(string), {})
    cache_cluster_enabled = optional(bool, false)
    cache_cluster_size    = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = try(var.stage.stage_name == null || length(trimspace(var.stage.stage_name)) > 0, true)
    error_message = "stage.stage_name must not be empty when set."
  }
}

variable "method_settings" {
  description = "Default API Gateway method settings applied to all methods. Routes and methods can override these values."
  type = object({
    metrics_enabled                            = optional(bool)
    logging_level                              = optional(string)
    data_trace_enabled                         = optional(bool)
    throttling_burst_limit                     = optional(number)
    throttling_rate_limit                      = optional(number)
    caching_enabled                            = optional(bool)
    cache_ttl_in_seconds                       = optional(number)
    cache_data_encrypted                       = optional(bool)
    require_authorization_for_cache_control    = optional(bool)
    unauthorized_cache_control_header_strategy = optional(string)
  })
  default  = {}
  nullable = false
}

variable "custom_domain" {
  description = "Optional API Gateway custom domain configuration."
  type = object({
    enabled                  = optional(bool, false)
    domain_name              = optional(string)
    certificate_arn          = optional(string)
    security_policy          = optional(string)
    routing_mode             = optional(string)
    endpoint_access_mode     = optional(string)
    endpoint_type            = optional(string, "REGIONAL")
    create_base_path_mapping = optional(bool, true)
    base_path_mapping = optional(object({
      base_path  = optional(string)
      stage_name = optional(string)
    }), {})
  })
  default = {}
}

variable "gateway_responses" {
  description = "Custom gateway responses map keyed by response type (e.g. ACCESS_DENIED, UNAUTHORIZED) to override default status codes, parameters, and templates."
  type = map(object({
    status_code         = optional(string)
    response_parameters = optional(map(string))
    response_templates  = optional(map(string))
  }))
  default = {}
}

variable "name" {
  type        = string
  description = "Name for the resource. If not provided, will be derived from application and environment."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Additional tags to apply to all resources"
  default     = {}
}

variable "kms_key_arn" {
  description = "KMS Key ARN used for encrypting API Gateway CloudWatch logs. Strictly required."
  type        = string
}
