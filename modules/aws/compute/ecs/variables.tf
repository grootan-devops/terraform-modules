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
  description = "Cluster name."
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

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs for the tasks."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(distinct(var.subnet_ids)) >= 2
    error_message = "subnet_ids: at least two subnets."
  }
}

variable "security_group" {
  description = "Task security group: ingress sources on the service ports, egress and extra groups."
  type = object({
    create                        = optional(bool, true)
    ingress_security_group_ids    = optional(list(string), [])
    ingress_cidr_blocks           = optional(list(string), [])
    ingress_prefix_list_ids       = optional(list(string), [])
    egress_cidr_blocks            = optional(list(string), ["0.0.0.0/0"])
    egress_prefix_list_ids        = optional(list(string), [])
    egress_security_group_ids     = optional(list(string), [])
    additional_security_group_ids = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.security_group.create || length(var.security_group.additional_security_group_ids) > 0
    error_message = "security_group: set additional_security_group_ids when create = false."
  }

  validation {
    condition     = !contains(var.security_group.ingress_cidr_blocks, "0.0.0.0/0") && !contains(var.security_group.ingress_cidr_blocks, "::/0")
    error_message = "security_group.ingress_cidr_blocks: no 0.0.0.0/0 or ::/0."
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

variable "iam_role" {
  description = "Task roles: extend every service role or bring one shared role."
  type = object({
    create                   = optional(bool, true)
    arn                      = optional(string)
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
  description = "Service and ECS Exec log groups."
  type = object({
    retention_in_days           = optional(number, 365)
    log_group_class             = optional(string, "STANDARD")
    deletion_protection_enabled = optional(bool, true)
    kms_key_arn                 = optional(string)
  })
  default  = {}
  nullable = false
}

variable "container_insights" {
  description = "Container Insights: enhanced, enabled or disabled."
  type        = string
  default     = "enhanced"
  nullable    = false

  validation {
    condition     = contains(["enhanced", "enabled", "disabled"], var.container_insights)
    error_message = "container_insights: enhanced, enabled or disabled."
  }
}

variable "tracing" {
  description = "X-Ray permissions on the task roles."
  type = object({
    enabled = optional(bool, false)
  })
  default  = {}
  nullable = false
}

variable "service_discovery_namespace" {
  description = "Private DNS namespace name. Null: <application>-<environment>.local."
  type        = string
  default     = null
}

variable "readonly_root_filesystem" {
  description = "Read-only root filesystem for containers."
  type        = bool
  nullable    = false
}

variable "services" {
  description = "Fargate services by key."
  type = map(object({
    image                             = string
    container_port                    = number
    cpu                               = optional(number, 256)
    memory                            = optional(number, 512)
    desired_count                     = optional(number, 1)
    cpu_architecture                  = optional(string, "X86_64")
    command                           = optional(list(string), [])
    environment                       = optional(map(string), {})
    secrets                           = optional(map(string), {})
    user                              = optional(string)
    readonly_root_filesystem          = optional(bool)
    writable_paths                    = optional(list(string), [])
    target_group_arns                 = optional(list(string), [])
    health_check_grace_period_seconds = optional(number, 60)
    execute_command                   = optional(bool, false)
    service_discovery                 = optional(bool, false)
    service_connect = optional(object({
      enabled           = optional(bool, false)
      discovery_name    = optional(string)
      client_alias_port = optional(number)
      client_alias_dns  = optional(string)
    }), {})
    deployment_circuit_breaker = optional(object({
      enabled  = optional(bool, true)
      rollback = optional(bool, true)
    }), {})
    autoscaling = optional(object({
      enabled       = optional(bool, false)
      min_capacity  = optional(number)
      max_capacity  = optional(number, 6)
      cpu_target    = optional(number, 60)
      memory_target = optional(number)
    }), {})
    task_role = optional(object({
      create              = optional(bool, true)
      arn                 = optional(string)
      managed_policy_arns = optional(list(string), [])
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
    }), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k in keys(var.services) : can(regex("^[a-z][a-z0-9-]{0,26}$", k))])
    error_message = "services keys: 1-27 chars, a-z 0-9 -, starts with a letter."
  }

  validation {
    condition     = alltrue([for s in values(var.services) : s.container_port >= 1 && s.container_port <= 65535 && s.desired_count >= 0])
    error_message = "services: container_port 1-65535, desired_count 0 or more."
  }

  validation {
    condition     = alltrue([for s in values(var.services) : contains(["X86_64", "ARM64"], s.cpu_architecture)])
    error_message = "services[*].cpu_architecture: X86_64 or ARM64."
  }

  validation {
    condition     = alltrue(flatten([for s in values(var.services) : [for k in keys(s.environment) : !can(regex("(?i)(PASSWORD|PASSWD|SECRET|TOKEN|API_?KEY|ACCESS_?KEY|PRIVATE_?KEY|CREDENTIAL|AUTH_DATA)", k))]]))
    error_message = "services[*].environment: no credential names; use secrets (ECS.8)."
  }

  validation {
    condition     = alltrue([for s in values(var.services) : s.user == null || !can(regex("^(root|0)(:.*)?$", s.user))])
    error_message = "services[*].user: not root or 0 (ECS.20)."
  }

  validation {
    condition     = alltrue([for s in values(var.services) : !s.autoscaling.enabled || (coalesce(s.autoscaling.min_capacity, s.desired_count) <= s.autoscaling.max_capacity && s.autoscaling.cpu_target > 0 && s.autoscaling.cpu_target <= 100)])
    error_message = "services[*].autoscaling: min_capacity <= max_capacity, cpu_target 1-100."
  }

  validation {
    condition     = alltrue([for s in values(var.services) : !(s.service_discovery && s.service_connect.enabled)])
    error_message = "services[*]: service_discovery or service_connect, not both."
  }

  validation {
    condition     = alltrue([for s in values(var.services) : s.task_role.create || s.task_role.arn != null || !var.iam_role.create])
    error_message = "services[*].task_role: set arn when create = false."
  }
}
