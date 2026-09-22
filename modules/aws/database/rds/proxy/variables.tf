variable "application" {
  description = "The name of the product"
  type        = string
}

variable "environment" {
  description = "Deployment environment name (e.g. dev, staging, prod)."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "The environment name must contain only lowercase alphanumeric characters and hyphens."
  }
}

variable "name" {
  description = "The name of the RDS proxy (optional). Will be used in combination with application and environment."
  type        = string
  default     = null
}

variable "tags" {
  description = "A mapping of tags to assign to the resource."
  type        = map(string)
  default     = {}
}

# ==============================================================================
# DB Proxy Configuration
# ==============================================================================

variable "engine_family" {
  description = "The kinds of databases that the proxy can connect to (MYSQL, POSTGRESQL, SQLSERVER)."
  type        = string
}

variable "kms_key_arn" {
  description = "The ARN of the KMS key used to encrypt the database secret in Secrets Manager. Strictly required."
  type        = string
}

variable "vpc_id" {
  description = "The VPC ID where the RDS proxy security group will be created"
  type        = string
}

variable "vpc_subnet_ids" {
  description = "One or more VPC subnet IDs to associate with the new proxy."
  type        = list(string)
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the database proxy"
  type        = list(string)
  default     = []
}

variable "debug_logging" {
  description = "Whether the proxy includes detailed information about SQL statements in its logs."
  type        = bool
  default     = false
}

variable "default_auth_scheme" {
  description = "Default authentication scheme that the proxy uses (NONE or IAM_AUTH)."
  type        = string
  default     = "NONE"
}

variable "endpoint_network_type" {
  description = "Network type of the DB proxy endpoint (IPV4, IPV6, DUAL)."
  type        = string
  default     = "IPV4"
}

variable "idle_client_timeout" {
  description = "The number of seconds that a connection to the proxy can be inactive before the proxy disconnects it."
  type        = number
  default     = 1800
}

variable "target_connection_network_type" {
  description = "Network type that the proxy uses to connect to the target database (IPV4 or IPV6)."
  type        = string
  default     = "IPV4"
}

variable "auth_blocks" {
  description = "Configuration block(s) with authorization mechanisms to connect to the associated instances or clusters."
  type = list(object({
    auth_scheme               = optional(string, "SECRETS")
    client_password_auth_type = optional(string)
    description               = optional(string)
    iam_auth                  = optional(string, "DISABLED")
    secret_arn                = optional(string)
    username                  = optional(string)
  }))
  default = []
}

# ==============================================================================
# DB Proxy Target Group Configuration
# ==============================================================================

variable "connection_pool_config" {
  description = "The settings that determine the size and behavior of the connection pool for the target group."
  type = object({
    connection_borrow_timeout    = optional(number)
    init_query                   = optional(string)
    max_connections_percent      = optional(number)
    max_idle_connections_percent = optional(number)
    session_pinning_filters      = optional(list(string))
  })
  default = {}
}

# ==============================================================================
# DB Proxy Target Configuration
# ==============================================================================

variable "db_instance_identifier" {
  description = "DB instance identifier to register as a target. Either db_instance_identifier or db_cluster_identifier should be specified."
  type        = string
}


# ==============================================================================
# DB Proxy Endpoints Configuration
# ==============================================================================

variable "endpoints" {
  description = "Map of endpoints to create for the proxy."
  type = map(object({
    vpc_subnet_ids      = list(string)
    allowed_cidr_blocks = optional(list(string), [])
    target_role         = optional(string, "READ_WRITE") # Valid values: READ_WRITE, READ_ONLY
    tags                = optional(map(string), {})
  }))
  default = {}
}
