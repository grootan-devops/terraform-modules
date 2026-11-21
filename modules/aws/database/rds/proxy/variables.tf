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
  description = "Proxy name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,31}$", var.name))
    error_message = "name: 1-32 chars, a-z 0-9 -."
  }
}

variable "tags" {
  description = "Extra tags; governance tags win."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "engine_family" {
  description = "POSTGRESQL, MYSQL or SQLSERVER."
  type        = string
  default     = "POSTGRESQL"
  nullable    = false

  validation {
    condition     = contains(["POSTGRESQL", "MYSQL", "SQLSERVER"], var.engine_family)
    error_message = "engine_family: POSTGRESQL, MYSQL or SQLSERVER."
  }
}

variable "target" {
  description = "Target DB instance, its port (null: engine default) and security groups."
  type = object({
    db_instance_identifier = string
    port                   = optional(number)
    security_group_ids     = optional(list(string), [])
  })
  nullable = false

  validation {
    condition     = var.target.port == null || try(var.target.port >= 1150 && var.target.port <= 65535, false)
    error_message = "target.port: 1150-65535."
  }

  validation {
    condition     = !var.security_group.create || length(var.target.security_group_ids) > 0
    error_message = "target.security_group_ids: at least one with security_group.create."
  }
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs in two or more AZs."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(distinct(var.subnet_ids)) >= 2
    error_message = "subnet_ids: at least two."
  }
}

variable "security_group" {
  description = "Security group: ingress sources, HTTPS egress to AWS APIs and extra groups."
  type = object({
    create                        = optional(bool, true)
    ingress_security_group_ids    = optional(list(string), [])
    ingress_cidr_blocks           = optional(list(string), [])
    ingress_prefix_list_ids       = optional(list(string), [])
    egress_cidr_blocks            = optional(list(string), ["0.0.0.0/0"])
    additional_security_group_ids = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for c in var.security_group.ingress_cidr_blocks : !endswith(c, "/0")])
    error_message = "security_group.ingress_cidr_blocks: no /0."
  }

  validation {
    condition     = var.security_group.create || length(var.security_group.additional_security_group_ids) > 0
    error_message = "security_group: set additional_security_group_ids when create = false."
  }
}

variable "default_auth_scheme" {
  description = "NONE (secrets to the database) or IAM_AUTH (end-to-end IAM)."
  type        = string
  default     = "NONE"
  nullable    = false

  validation {
    condition     = contains(["NONE", "IAM_AUTH"], var.default_auth_scheme)
    error_message = "default_auth_scheme: NONE or IAM_AUTH."
  }
}

variable "auth" {
  description = "Database secrets; clients must use IAM auth unless iam_auth = DISABLED."
  type = list(object({
    secret_arn                = optional(string)
    iam_auth                  = optional(string, "REQUIRED")
    auth_scheme               = optional(string, "SECRETS")
    client_password_auth_type = optional(string)
    description               = optional(string)
    username                  = optional(string)
  }))
  default  = []
  nullable = false

  validation {
    condition     = var.default_auth_scheme == "IAM_AUTH" || length(var.auth) > 0
    error_message = "auth: at least one with default_auth_scheme NONE."
  }

  validation {
    condition     = alltrue([for a in var.auth : contains(["REQUIRED", "DISABLED"], a.iam_auth) || (a.iam_auth == "ENABLED" && var.engine_family == "SQLSERVER")])
    error_message = "auth[*].iam_auth: REQUIRED or DISABLED; ENABLED only for SQLSERVER."
  }

  validation {
    condition     = alltrue([for a in var.auth : a.auth_scheme == "SECRETS" && a.secret_arn != null])
    error_message = "auth[*]: auth_scheme SECRETS with secret_arn."
  }
}

variable "idle_client_timeout" {
  description = "Idle client timeout in seconds (1-28800)."
  type        = number
  default     = 1800
  nullable    = false

  validation {
    condition     = var.idle_client_timeout >= 1 && var.idle_client_timeout <= 28800
    error_message = "idle_client_timeout: 1-28800."
  }
}

variable "debug_logging" {
  description = "Log SQL statement details."
  type        = bool
  default     = false
  nullable    = false
}

variable "connection_pool" {
  description = "Connection pool of the default target group."
  type = object({
    connection_borrow_timeout    = optional(number, 120)
    max_connections_percent      = optional(number, 100)
    max_idle_connections_percent = optional(number, 50)
    init_query                   = optional(string)
    session_pinning_filters      = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.connection_pool.max_connections_percent >= 1 && var.connection_pool.max_connections_percent <= 100 && var.connection_pool.max_idle_connections_percent >= 0 && var.connection_pool.max_idle_connections_percent <= var.connection_pool.max_connections_percent
    error_message = "connection_pool: max 1-100, idle 0-max."
  }

  validation {
    condition     = var.connection_pool.connection_borrow_timeout >= 0 && var.connection_pool.connection_borrow_timeout <= 3600
    error_message = "connection_pool.connection_borrow_timeout: 0-3600."
  }
}

variable "iam_role" {
  description = "Proxy role: extend it or bring your own."
  type = object({
    create                   = optional(bool, true)
    arn                      = optional(string)
    name                     = optional(string)
    path                     = optional(string, "/")
    permissions_boundary_arn = optional(string)
    managed_policy_arns      = optional(list(string), [])
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
    condition     = var.iam_role.create || var.iam_role.arn != null
    error_message = "iam_role: set arn when create = false."
  }
}

variable "cloudwatch_logs" {
  description = "Pre-created proxy log group."
  type = object({
    enabled                     = optional(bool, false)
    retention_in_days           = optional(number, 365)
    log_group_class             = optional(string, "STANDARD")
    deletion_protection_enabled = optional(bool, true)
    kms_key_arn                 = optional(string)
  })
  default  = {}
  nullable = false
}

variable "endpoints" {
  description = "Extra read/write endpoints by key; empty lists use the proxy subnets and groups."
  type = map(object({
    subnet_ids         = optional(list(string), [])
    security_group_ids = optional(list(string), [])
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k in keys(var.endpoints) : can(regex("^[a-z0-9][a-z0-9-]{0,19}$", k))])
    error_message = "endpoints: keys of 1-20 chars, a-z 0-9 -."
  }
}
