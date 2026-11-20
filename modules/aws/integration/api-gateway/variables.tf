variable "application" {
  description = "Application name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,23}$", var.application))
    error_message = "application: 2-24 chars, a-z 0-9 -, starts with a letter."
  }
}

variable "environment" {
  description = "Environment name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,11}$", var.environment))
    error_message = "environment: 2-12 chars, a-z 0-9 -, starts with a letter."
  }
}

variable "name" {
  description = "Instance name."
  type        = string
  default     = null

  validation {
    condition     = var.name == null || can(regex("^[a-z0-9][a-z0-9-]{0,31}$", var.name))
    error_message = "name: 1-32 chars, a-z 0-9 -."
  }
}

variable "tags" {
  description = "Extra tags; governance tags win."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "description" {
  description = "API description."
  type        = string
  default     = null
}

variable "endpoint_type" {
  description = "REGIONAL or EDGE."
  type        = string
  default     = "REGIONAL"
  nullable    = false

  validation {
    condition     = contains(["REGIONAL", "EDGE"], var.endpoint_type)
    error_message = "endpoint_type: REGIONAL or EDGE."
  }
}

variable "tls" {
  description = "Enhanced TLS policies of the API and the custom domain; null picks the default for the endpoint type."
  type = object({
    security_policy        = optional(string)
    domain_security_policy = optional(string, "SecurityPolicy_TLS13_1_2_PFS_PQ_2025_09")
    endpoint_access_mode   = optional(string, "STRICT")
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.tls.security_policy == null || contains(["SecurityPolicy_TLS13_1_3_2025_09", "SecurityPolicy_TLS13_1_3_FIPS_2025_09", "SecurityPolicy_TLS13_1_2_PFS_PQ_2025_09", "SecurityPolicy_TLS13_1_2_FIPS_PFS_PQ_2025_09", "SecurityPolicy_TLS13_1_2_PQ_2025_09", "SecurityPolicy_TLS13_1_2_FIPS_PQ_2025_09", "SecurityPolicy_TLS13_2025_EDGE", "SecurityPolicy_TLS12_PFS_2025_EDGE"], coalesce(var.tls.security_policy, "-"))
    error_message = "tls.security_policy: a 2025 SecurityPolicy_* policy."
  }

  validation {
    condition     = var.tls.security_policy == null || (var.endpoint_type == "EDGE") == endswith(coalesce(var.tls.security_policy, "-"), "_EDGE")
    error_message = "tls.security_policy: *_EDGE policies only, and only, on EDGE APIs."
  }

  validation {
    condition     = contains(["SecurityPolicy_TLS13_1_3_2025_09", "SecurityPolicy_TLS13_1_3_FIPS_2025_09", "SecurityPolicy_TLS13_1_2_PFS_PQ_2025_09", "SecurityPolicy_TLS13_1_2_FIPS_PFS_PQ_2025_09", "SecurityPolicy_TLS13_1_2_PQ_2025_09", "SecurityPolicy_TLS13_1_2_FIPS_PQ_2025_09"], var.tls.domain_security_policy)
    error_message = "tls.domain_security_policy: a 2025 Regional SecurityPolicy_* policy."
  }

  validation {
    condition     = contains(["BASIC", "STRICT"], var.tls.endpoint_access_mode)
    error_message = "tls.endpoint_access_mode: BASIC or STRICT."
  }
}

variable "binary_media_types" {
  description = "Binary media types."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "minimum_compression_size" {
  description = "Compression threshold in bytes (0-10485760); null: off."
  type        = number
  default     = null

  validation {
    condition     = var.minimum_compression_size == null || (var.minimum_compression_size >= 0 && var.minimum_compression_size <= 10485760)
    error_message = "minimum_compression_size: 0-10485760."
  }
}

variable "stage" {
  description = "Stage name (default: environment), description and variables."
  type = object({
    name        = optional(string)
    description = optional(string)
    variables   = optional(map(string), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.stage.name == null || can(regex("^[a-zA-Z0-9_-]{1,128}$", var.stage.name))
    error_message = "stage.name: 1-128 chars of a-z A-Z 0-9 _ -."
  }
}

variable "cache_cluster" {
  description = "Stage cache cluster; always encrypted."
  type = object({
    enabled = optional(bool, false)
    size    = optional(string, "0.5")
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["0.5", "1.6", "6.1", "13.5", "28.4", "58.2", "118", "237"], var.cache_cluster.size)
    error_message = "cache_cluster.size: 0.5, 1.6, 6.1, 13.5, 28.4, 58.2, 118 or 237."
  }
}

variable "tracing" {
  description = "X-Ray tracing on the stage."
  type = object({
    enabled = optional(bool, true)
  })
  default  = {}
  nullable = false
}

variable "kms" {
  description = "Log encryption: {} CloudWatch Logs service encryption, create = true module key, key_id your key (ARN or ID)."
  type = object({
    key_id                  = optional(string)
    create                  = optional(bool, false)
    deletion_window_in_days = optional(number, 30)
    policy_statements = optional(list(object({
      sid        = optional(string)
      effect     = optional(string, "Allow")
      actions    = list(string)
      resources  = optional(list(string))
      principals = optional(map(list(string)), {})
      conditions = optional(list(object({
        test     = string
        variable = string
        values   = list(string)
      })), [])
    })), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = !(var.kms.create && var.kms.key_id != null)
    error_message = "kms: set create or key_id, not both."
  }

  validation {
    condition     = var.kms.key_id == null || can(regex("^(arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/)?(mrk-[a-f0-9]{32}|[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})$", var.kms.key_id))
    error_message = "kms.key_id: a KMS key ARN or key ID."
  }
}

variable "cloudwatch_logs" {
  description = "Access and execution log groups and the access log format."
  type = object({
    retention_in_days           = optional(number, 365)
    log_group_class             = optional(string, "STANDARD")
    deletion_protection_enabled = optional(bool, true)
    kms_key_arn                 = optional(string)
    access_log_format           = optional(string)
  })
  default  = {}
  nullable = false
}

variable "execution_logging" {
  description = "Stage execution logging and metrics."
  type = object({
    enabled            = optional(bool, true)
    logging_level      = optional(string, "ERROR")
    metrics_enabled    = optional(bool, true)
    data_trace_enabled = optional(bool, false)
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["ERROR", "INFO"], var.execution_logging.logging_level)
    error_message = "execution_logging.logging_level: ERROR or INFO (APIGateway.1)."
  }
}

variable "client_certificate_id" {
  description = "Client certificate ID for backends (APIGateway.2)."
  type        = string
  default     = null
}

variable "waf" {
  description = "WAFv2 web ACL association (APIGateway.4)."
  type = object({
    enabled     = optional(bool, false)
    web_acl_arn = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.waf.enabled || var.waf.web_acl_arn != null
    error_message = "waf: set web_acl_arn when enabled."
  }
}

variable "method_settings" {
  description = "Stage-wide throttling and caching."
  type = object({
    throttling_burst_limit                     = optional(number)
    throttling_rate_limit                      = optional(number)
    caching_enabled                            = optional(bool)
    cache_ttl_in_seconds                       = optional(number)
    require_authorization_for_cache_control    = optional(bool)
    unauthorized_cache_control_header_strategy = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = coalesce(var.method_settings.throttling_burst_limit, 0) >= 0 && coalesce(var.method_settings.throttling_rate_limit, 0) >= 0
    error_message = "method_settings: throttling limits 0 or more."
  }
}

variable "authorizers" {
  description = "Cognito user pool authorizers by key."
  type = map(object({
    provider_arns                    = list(string)
    identity_source                  = optional(string, "method.request.header.Authorization")
    authorizer_result_ttl_in_seconds = optional(number, 300)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for a in values(var.authorizers) : length(a.provider_arns) > 0])
    error_message = "authorizers[*].provider_arns: at least one user pool."
  }
}

variable "lambda_authorizers" {
  description = "Lambda REQUEST authorizers by key: the lambda module's invoke_arn and alias_arn."
  type = map(object({
    invoke_arn                       = string
    alias_arn                        = string
    identity_source                  = optional(string, "method.request.header.Authorization")
    authorizer_result_ttl_in_seconds = optional(number, 300)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for a in values(var.lambda_authorizers) : can(regex("^arn:[^:]+:lambda:[^:]+:[0-9]{12}:function:[^:]+:[^:]+$", a.alias_arn))])
    error_message = "lambda_authorizers[*].alias_arn: a qualified function ARN."
  }
}

variable "routes" {
  description = "Routes by path: methods by HTTP verb, CORS and method settings overrides."
  type = map(object({
    cors = optional(object({
      enabled           = optional(bool)
      allow_origins     = optional(list(string))
      allow_methods     = optional(list(string))
      allow_headers     = optional(list(string))
      allow_credentials = optional(bool)
      max_age           = optional(number)
    }))
    method_settings = optional(object({
      throttling_burst_limit                     = optional(number)
      throttling_rate_limit                      = optional(number)
      caching_enabled                            = optional(bool)
      cache_ttl_in_seconds                       = optional(number)
      require_authorization_for_cache_control    = optional(bool)
      unauthorized_cache_control_header_strategy = optional(string)
    }))
    methods = map(object({
      authorizer_key     = optional(string)
      lambda             = optional(object({ invoke_arn = string, alias_arn = string }))
      request_parameters = optional(map(bool), {})
      request_model      = optional(string)
      request_validator  = optional(string)
      operation_name     = optional(string)
      method_settings = optional(object({
        throttling_burst_limit                     = optional(number)
        throttling_rate_limit                      = optional(number)
        caching_enabled                            = optional(bool)
        cache_ttl_in_seconds                       = optional(number)
        require_authorization_for_cache_control    = optional(bool)
        unauthorized_cache_control_header_strategy = optional(string)
      }))
      integration = optional(object({
        type                 = optional(string, "AWS_PROXY")
        http_method          = optional(string)
        uri                  = optional(string)
        connection_type      = optional(string)
        connection_id        = optional(string)
        integration_target   = optional(string)
        request_parameters   = optional(map(string), {})
        request_templates    = optional(map(string), {})
        passthrough_behavior = optional(string)
        cache_key_parameters = optional(list(string), [])
        cache_namespace      = optional(string)
        content_handling     = optional(string)
        timeout_milliseconds = optional(number)
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
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for path in keys(var.routes) : path == "/" || can(regex("^(/[^/]+)+$", path))])
    error_message = "routes: paths start with / and do not end with /."
  }

  validation {
    condition     = alltrue(flatten([for r in values(var.routes) : [for verb in keys(r.methods) : contains(["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD", "ANY"], verb)]]))
    error_message = "routes[*].methods: GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD or ANY."
  }

  validation {
    condition     = var.allow_unauthenticated_methods || alltrue(flatten([for r in values(var.routes) : [for verb, m in r.methods : verb == "OPTIONS" || m.authorizer_key != null]]))
    error_message = "routes: methods need authorizer_key (APIGateway.8)."
  }

  validation {
    condition     = alltrue(flatten([for r in values(var.routes) : [for m in values(r.methods) : contains(["AWS_PROXY", "AWS", "HTTP", "HTTP_PROXY", "MOCK"], m.integration.type)]]))
    error_message = "routes[*].methods[*].integration.type: AWS_PROXY, AWS, HTTP, HTTP_PROXY or MOCK."
  }

  validation {
    condition = alltrue(flatten([for r in values(var.routes) : [for m in values(r.methods) : (
      m.integration.type == "MOCK" ? m.lambda == null :
      m.integration.type == "AWS_PROXY" ? m.lambda != null :
      m.integration.type == "AWS" ? (m.lambda != null) != (m.integration.uri != null) :
      m.lambda == null && m.integration.uri != null
    )]]))
    error_message = "routes[*].methods[*]: AWS_PROXY needs lambda, HTTP needs uri, AWS needs one, MOCK neither."
  }

  validation {
    condition     = alltrue(flatten([for r in values(var.routes) : [for m in values(r.methods) : m.lambda == null || can(regex("^arn:[^:]+:lambda:[^:]+:[0-9]{12}:function:[^:]+:[^:]+$", m.lambda.alias_arn))]]))
    error_message = "routes[*].methods[*].lambda.alias_arn: a qualified function ARN."
  }
}

variable "allow_unauthenticated_methods" {
  description = "Allow methods without an authorizer."
  type        = bool
  default     = false
  nullable    = false
}

variable "models" {
  description = "Models by name: JSON schema."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for k, v in var.models : can(regex("^[a-zA-Z0-9]+$", k)) && can(jsondecode(v))])
    error_message = "models: alphanumeric names, JSON schemas."
  }
}

variable "request_validators" {
  description = "Request validators by name."
  type = map(object({
    validate_request_body       = optional(bool, false)
    validate_request_parameters = optional(bool, false)
  }))
  default  = {}
  nullable = false
}

variable "cors" {
  description = "CORS preflight (MOCK OPTIONS) defaults; routes override."
  type = object({
    enabled           = optional(bool, false)
    allow_origins     = optional(list(string), ["*"])
    allow_methods     = optional(list(string), ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"])
    allow_headers     = optional(list(string), ["Content-Type", "Authorization", "X-Amz-Date", "X-Amz-Security-Token"])
    allow_credentials = optional(bool, false)
    max_age           = optional(number, 86400)
  })
  default  = {}
  nullable = false

  validation {
    condition     = !(var.cors.allow_credentials && contains(var.cors.allow_origins, "*"))
    error_message = "cors: allow_credentials needs explicit origins."
  }
}

variable "gateway_responses" {
  description = "Gateway response overrides by type."
  type = map(object({
    status_code         = optional(string)
    response_parameters = optional(map(string), {})
    response_templates  = optional(map(string))
  }))
  default  = {}
  nullable = false
}

variable "custom_domain" {
  description = "Regional custom domain mapped to the stage."
  type = object({
    enabled         = optional(bool, false)
    domain_name     = optional(string)
    certificate_arn = optional(string)
    base_path       = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.custom_domain.enabled || (var.custom_domain.domain_name != null && var.custom_domain.certificate_arn != null)
    error_message = "custom_domain: set domain_name and certificate_arn."
  }
}
