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

variable "ip_address_type" {
  description = "ipv4 or dualstack."
  type        = string
  default     = "ipv4"
  nullable    = false

  validation {
    condition     = contains(["ipv4", "dualstack"], var.ip_address_type)
    error_message = "ip_address_type: ipv4 or dualstack."
  }
}

variable "integrations" {
  description = "Integrations by key: lambda, http or private."
  type = map(object({
    type                 = string
    description          = optional(string)
    lambda               = optional(object({ function_arn = string }))
    uri                  = optional(string)
    method               = optional(string, "ANY")
    listener_arn         = optional(string)
    tls_server_name      = optional(string)
    timeout_milliseconds = optional(number, 30000)
    request_parameters   = optional(map(string), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for i in values(var.integrations) : contains(["lambda", "http", "private"], i.type)])
    error_message = "integrations[*].type: lambda, http or private."
  }

  validation {
    condition = alltrue([for i in values(var.integrations) : (
      i.type == "lambda" ? i.lambda != null && i.uri == null && i.listener_arn == null :
      i.type == "http" ? i.uri != null && i.lambda == null && i.listener_arn == null :
      i.listener_arn != null && i.lambda == null && i.uri == null
    )])
    error_message = "integrations: lambda needs lambda, http uri, private listener_arn."
  }

  validation {
    condition     = alltrue([for i in values(var.integrations) : i.type != "private" || i.tls_server_name != null])
    error_message = "integrations[*].tls_server_name: required for private (APIGateway.10)."
  }

  validation {
    condition     = var.vpc_link.enabled || alltrue([for i in values(var.integrations) : i.type != "private"])
    error_message = "integrations: private needs vpc_link.enabled."
  }

  validation {
    condition     = alltrue([for i in values(var.integrations) : i.lambda == null || can(regex("^arn:[^:]+:lambda:[^:]+:[0-9]{12}:function:[^:]+(:[^:]+)?$", try(i.lambda.function_arn, "")))])
    error_message = "integrations[*].lambda.function_arn: a function or alias ARN."
  }

  validation {
    condition     = alltrue([for i in values(var.integrations) : i.uri == null || startswith(coalesce(i.uri, "-"), "https://")])
    error_message = "integrations[*].uri: an https:// URL."
  }

  validation {
    condition     = alltrue([for i in values(var.integrations) : contains(["ANY", "GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"], i.method)])
    error_message = "integrations[*].method: ANY, GET, POST, PUT, PATCH, DELETE, HEAD or OPTIONS."
  }

  validation {
    condition     = alltrue([for i in values(var.integrations) : i.timeout_milliseconds >= 50 && i.timeout_milliseconds <= 30000])
    error_message = "integrations[*].timeout_milliseconds: 50-30000."
  }
}

variable "authorizers" {
  description = "Authorizers by key: jwt or lambda."
  type = map(object({
    jwt = optional(object({
      issuer   = string
      audience = list(string)
    }))
    lambda = optional(object({
      function_arn           = string
      identity_sources       = optional(list(string), ["$request.header.Authorization"])
      result_ttl_seconds     = optional(number, 300)
      simple_responses       = optional(bool, true)
      payload_format_version = optional(string, "2.0")
    }))
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for a in values(var.authorizers) : (a.jwt != null) != (a.lambda != null)])
    error_message = "authorizers: set jwt or lambda."
  }

  validation {
    condition     = alltrue([for a in values(var.authorizers) : a.jwt == null || startswith(try(a.jwt.issuer, "-"), "https://")])
    error_message = "authorizers[*].jwt.issuer: an https:// URL."
  }

  validation {
    condition     = alltrue([for a in values(var.authorizers) : a.jwt == null || length(try(a.jwt.audience, [])) > 0])
    error_message = "authorizers[*].jwt.audience: at least one."
  }

  validation {
    condition     = alltrue([for a in values(var.authorizers) : a.lambda == null || can(regex("^arn:[^:]+:lambda:[^:]+:[0-9]{12}:function:[^:]+(:[^:]+)?$", try(a.lambda.function_arn, "")))])
    error_message = "authorizers[*].lambda.function_arn: a function or alias ARN."
  }

  validation {
    condition     = alltrue([for a in values(var.authorizers) : a.lambda == null || (try(a.lambda.result_ttl_seconds, 0) >= 0 && try(a.lambda.result_ttl_seconds, 0) <= 3600)])
    error_message = "authorizers[*].lambda.result_ttl_seconds: 0-3600."
  }

  validation {
    condition     = alltrue([for a in values(var.authorizers) : a.lambda == null || try(a.lambda.result_ttl_seconds == 0 || length(a.lambda.identity_sources) > 0, false)])
    error_message = "authorizers[*].lambda: caching needs identity_sources."
  }

  validation {
    condition     = alltrue([for a in values(var.authorizers) : a.lambda == null || try(contains(["1.0", "2.0"], a.lambda.payload_format_version) && (!a.lambda.simple_responses || a.lambda.payload_format_version == "2.0"), false)])
    error_message = "authorizers[*].lambda: payload_format_version 1.0 or 2.0; simple_responses needs 2.0."
  }
}

variable "routes" {
  description = "Routes by route key: integration, authorizer or authorization, scopes, throttling."
  type = map(object({
    integration          = string
    authorizer           = optional(string)
    authorization        = optional(string)
    authorization_scopes = optional(list(string), [])
    throttling = optional(object({
      burst_limit = number
      rate_limit  = number
    }))
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k in keys(var.routes) : k == "$default" || can(regex("^(ANY|GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS) (/|(/[^/ ]+)+)$", k))])
    error_message = "routes: keys are $default or \"<METHOD> /path\"."
  }

  validation {
    condition     = alltrue([for r in values(var.routes) : contains(keys(var.integrations), r.integration)])
    error_message = "routes[*].integration: a key of integrations."
  }

  validation {
    condition     = alltrue([for r in values(var.routes) : (r.authorizer != null) != (r.authorization != null)])
    error_message = "routes: set authorizer or authorization (APIGateway.8)."
  }

  validation {
    condition     = alltrue([for r in values(var.routes) : r.authorization == null || contains(["NONE", "AWS_IAM"], coalesce(r.authorization, "-"))])
    error_message = "routes[*].authorization: NONE or AWS_IAM."
  }

  validation {
    condition     = alltrue([for r in values(var.routes) : r.authorizer == null || contains(keys(var.authorizers), coalesce(r.authorizer, "-"))])
    error_message = "routes[*].authorizer: a key of authorizers."
  }

  validation {
    condition     = alltrue([for r in values(var.routes) : length(r.authorization_scopes) == 0 || try(var.authorizers[r.authorizer].jwt != null, false)])
    error_message = "routes[*].authorization_scopes: JWT authorizers only."
  }

  validation {
    condition     = alltrue([for r in values(var.routes) : r.throttling == null || try(r.throttling.burst_limit >= 0 && r.throttling.rate_limit >= 0, false)])
    error_message = "routes[*].throttling: limits 0 or more."
  }
}

variable "cors" {
  description = "CORS configuration."
  type = object({
    enabled           = optional(bool, false)
    allow_origins     = optional(list(string), [])
    allow_methods     = optional(list(string), ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"])
    allow_headers     = optional(list(string), ["Content-Type", "Authorization", "X-Amz-Date", "X-Amz-Security-Token"])
    expose_headers    = optional(list(string), [])
    allow_credentials = optional(bool, false)
    max_age           = optional(number, 86400)
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.cors.enabled || length(var.cors.allow_origins) > 0
    error_message = "cors: set allow_origins."
  }

  validation {
    condition     = !(var.cors.allow_credentials && contains(var.cors.allow_origins, "*"))
    error_message = "cors: allow_credentials needs explicit origins."
  }

  validation {
    condition     = var.cors.max_age >= 0 && var.cors.max_age <= 86400
    error_message = "cors.max_age: 0-86400."
  }
}

variable "throttling" {
  description = "Stage default throttling."
  type = object({
    burst_limit = optional(number, 2000)
    rate_limit  = optional(number, 1000)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.throttling.burst_limit >= 0 && var.throttling.rate_limit >= 0
    error_message = "throttling: limits 0 or more."
  }
}

variable "detailed_metrics" {
  description = "Per-route CloudWatch metrics."
  type        = bool
  default     = false
  nullable    = false
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
  description = "Access log group and format."
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

variable "vpc_link" {
  description = "VPC link for private integrations."
  type = object({
    enabled    = optional(bool, false)
    vpc_id     = optional(string)
    subnet_ids = optional(list(string), [])
    security_group = optional(object({
      create                        = optional(bool, true)
      egress_security_group_ids     = optional(list(string), [])
      egress_cidr_blocks            = optional(list(string), [])
      additional_security_group_ids = optional(list(string), [])
    }), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.vpc_link.enabled || length(var.vpc_link.subnet_ids) > 0
    error_message = "vpc_link: set subnet_ids."
  }

  validation {
    condition     = !var.vpc_link.enabled || !var.vpc_link.security_group.create || var.vpc_link.vpc_id != null
    error_message = "vpc_link: set vpc_id."
  }

  validation {
    condition     = !var.vpc_link.enabled || !var.vpc_link.security_group.create || length(var.vpc_link.security_group.egress_security_group_ids) + length(var.vpc_link.security_group.egress_cidr_blocks) > 0
    error_message = "vpc_link.security_group: set an egress destination."
  }

  validation {
    condition     = var.vpc_link.security_group.create || length(var.vpc_link.security_group.additional_security_group_ids) > 0
    error_message = "vpc_link.security_group: set additional_security_group_ids when create = false."
  }
}

variable "domain" {
  description = "Regional custom domain mapped to the stage."
  type = object({
    enabled         = optional(bool, false)
    name            = optional(string)
    certificate_arn = optional(string)
    security_policy = optional(string, "TLS_1_2")
    base_path       = optional(string)
    mutual_tls = optional(object({
      enabled            = optional(bool, false)
      truststore_uri     = optional(string)
      truststore_version = optional(string)
    }), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.domain.enabled || (var.domain.name != null && var.domain.certificate_arn != null)
    error_message = "domain: set name and certificate_arn."
  }

  validation {
    condition     = contains(["TLS_1_2"], var.domain.security_policy)
    error_message = "domain.security_policy: TLS_1_2."
  }

  validation {
    condition     = var.domain.base_path == null || can(regex("^[^/]+(/[^/]+)*$", coalesce(var.domain.base_path, "-")))
    error_message = "domain.base_path: no leading or trailing /."
  }

  validation {
    condition     = !var.domain.mutual_tls.enabled || startswith(coalesce(var.domain.mutual_tls.truststore_uri, "-"), "s3://")
    error_message = "domain.mutual_tls.truststore_uri: an s3:// URI."
  }
}

variable "alarms" {
  description = "Built-in CloudWatch alarms: switch, topics by severity, per-alarm overrides."
  type = object({
    enabled    = optional(bool, true)
    topic_arns = optional(map(string), {})
    overrides = optional(object({
      server_error_rate = optional(object({ enabled = optional(bool), threshold = optional(number), evaluation_periods = optional(number), datapoints_to_alarm = optional(number), period = optional(number), severity = optional(string) }), {})
      latency_p99       = optional(object({ enabled = optional(bool), threshold = optional(number), evaluation_periods = optional(number), datapoints_to_alarm = optional(number), period = optional(number), severity = optional(string) }), {})
    }), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for s, arn in var.alarms.topic_arns : can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]+$", arn))])
    error_message = "alarms.topic_arns: SNS topic ARNs by severity."
  }
}
