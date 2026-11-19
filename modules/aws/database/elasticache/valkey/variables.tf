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
  description = "Replication group name."
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

variable "engine_version" {
  description = "Valkey version (major.minor)."
  type        = string
  default     = "9.1"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+$", var.engine_version)) && try(tonumber(split(".", var.engine_version)[0]) > 7 || (tonumber(split(".", var.engine_version)[0]) == 7 && tonumber(split(".", var.engine_version)[1]) >= 2), false)
    error_message = "engine_version: major.minor, 7.2 or later."
  }
}

variable "node_type" {
  description = "Node type."
  type        = string
  default     = "cache.t4g.micro"
  nullable    = false
}

variable "num_cache_clusters" {
  description = "Nodes: primary plus replicas (1-6)."
  type        = number
  default     = 2
  nullable    = false

  validation {
    condition     = var.num_cache_clusters >= 1 && var.num_cache_clusters <= 6
    error_message = "num_cache_clusters: 1-6."
  }
}

variable "port" {
  description = "Port the nodes listen on."
  type        = number
  default     = 6379
  nullable    = false

  validation {
    condition     = var.port >= 1024 && var.port <= 65535
    error_message = "port: 1024-65535."
  }
}

variable "parameters" {
  description = "Parameter group values by name."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "snapshot_retention_limit" {
  description = "Automatic snapshot retention in days."
  type        = number
  default     = 7
  nullable    = false

  validation {
    condition     = var.snapshot_retention_limit >= 1 && var.snapshot_retention_limit <= 35
    error_message = "snapshot_retention_limit: 1-35."
  }
}

variable "snapshot_window" {
  description = "Daily UTC snapshot window (hh:mm-hh:mm). Null: AWS picks."
  type        = string
  default     = null

  validation {
    condition     = var.snapshot_window == null || can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]-([01][0-9]|2[0-3]):[0-5][0-9]$", coalesce(var.snapshot_window, "x")))
    error_message = "snapshot_window: hh:mm-hh:mm."
  }
}

variable "user_group_id" {
  description = "RBAC user group ID."
  type        = string
  default     = null
}

variable "auth_token_wo" {
  description = "Write-only AUTH token."
  type        = string
  default     = null
  sensitive   = true
  ephemeral   = true

  validation {
    condition     = var.auth_token_wo == null || (length(coalesce(var.auth_token_wo, "x")) >= 16 && length(coalesce(var.auth_token_wo, "x")) <= 128)
    error_message = "auth_token_wo: 16-128 chars."
  }

  validation {
    condition     = var.auth_token_wo == null || var.user_group_id == null
    error_message = "auth_token_wo: not with user_group_id."
  }
}

variable "auth_token_wo_version" {
  description = "AUTH token version; change it to send a new token."
  type        = number
  default     = null

  validation {
    condition     = var.auth_token_wo == null || var.auth_token_wo_version != null
    error_message = "auth_token_wo needs auth_token_wo_version."
  }
}

variable "auth_token_update_strategy" {
  description = "Token change: SET, ROTATE or DELETE. Null: ROTATE."
  type        = string
  default     = null

  validation {
    condition     = contains(["SET", "ROTATE", "DELETE"], coalesce(var.auth_token_update_strategy, "ROTATE"))
    error_message = "auth_token_update_strategy: SET, ROTATE or DELETE."
  }
}

variable "kms" {
  description = "Encryption: {} AWS managed key, create = true module key, key_id your key (ARN or ID)."
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

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(distinct(var.subnet_ids)) >= (var.num_cache_clusters > 1 ? 2 : 1)
    error_message = "subnet_ids: at least two with replicas."
  }
}

variable "security_group" {
  description = "Security group: ingress sources and extra groups."
  type = object({
    create                        = optional(bool, true)
    ingress_security_group_ids    = optional(list(string), [])
    ingress_cidr_blocks           = optional(list(string), [])
    ingress_prefix_list_ids       = optional(list(string), [])
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

variable "cloudwatch_logs" {
  description = "Slow and engine log delivery to CloudWatch Logs."
  type = object({
    enabled                     = optional(bool, true)
    log_types                   = optional(list(string), ["slow-log", "engine-log"])
    log_format                  = optional(string, "json")
    retention_in_days           = optional(number, 365)
    log_group_class             = optional(string, "STANDARD")
    deletion_protection_enabled = optional(bool, true)
    kms_key_arn                 = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = length(var.cloudwatch_logs.log_types) > 0 && alltrue([for t in var.cloudwatch_logs.log_types : contains(["slow-log", "engine-log"], t)])
    error_message = "cloudwatch_logs.log_types: slow-log and/or engine-log."
  }

  validation {
    condition     = contains(["json", "text"], var.cloudwatch_logs.log_format)
    error_message = "cloudwatch_logs.log_format: json or text."
  }
}
