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

variable "vpc_id" {
  description = "VPC ID for the compute environments."
  type        = string
  default     = null

  validation {
    condition     = length(var.compute_environments) == 0 || !var.security_group.create || var.vpc_id != null
    error_message = "vpc_id: required with compute_environments."
  }
}

variable "subnet_ids" {
  description = "Private subnet IDs for the compute environments."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = length(var.compute_environments) == 0 || length(distinct(var.subnet_ids)) >= 2
    error_message = "subnet_ids: at least two subnets with compute_environments."
  }
}

variable "security_group" {
  description = "Compute environment security group: egress and extra groups."
  type = object({
    create                        = optional(bool, true)
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

variable "compute_environments" {
  description = "Managed compute environments by key: FARGATE, FARGATE_SPOT, EC2 or SPOT."
  type = map(object({
    type                = optional(string, "FARGATE")
    max_vcpus           = number
    min_vcpus           = optional(number, 0)
    instance_types      = optional(list(string), ["default_x86_64"])
    allocation_strategy = optional(string)
    root_volume_size    = optional(number, 30)
    state               = optional(string, "ENABLED")
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k in keys(var.compute_environments) : can(regex("^[a-z0-9][a-z0-9-]{0,31}$", k))])
    error_message = "compute_environments keys: 1-32 chars, a-z 0-9 -."
  }

  validation {
    condition     = alltrue([for c in values(var.compute_environments) : contains(["FARGATE", "FARGATE_SPOT", "EC2", "SPOT"], c.type)])
    error_message = "compute_environments[*].type: FARGATE, FARGATE_SPOT, EC2 or SPOT."
  }

  validation {
    condition     = alltrue([for c in values(var.compute_environments) : c.max_vcpus >= 1 && c.min_vcpus >= 0 && c.min_vcpus <= c.max_vcpus])
    error_message = "compute_environments: 0 <= min_vcpus <= max_vcpus, max_vcpus >= 1."
  }

  validation {
    condition     = alltrue([for c in values(var.compute_environments) : contains(["ENABLED", "DISABLED"], c.state)])
    error_message = "compute_environments[*].state: ENABLED or DISABLED."
  }
}

variable "job_queues" {
  description = "Job queues by key: priority and compute environment keys or ARNs in order."
  type = map(object({
    priority              = number
    compute_environments  = list(string)
    state                 = optional(string, "ENABLED")
    scheduling_policy_arn = optional(string)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k in keys(var.job_queues) : can(regex("^[a-z0-9][a-z0-9-]{0,31}$", k))])
    error_message = "job_queues keys: 1-32 chars, a-z 0-9 -."
  }

  validation {
    condition     = alltrue([for q in values(var.job_queues) : length(q.compute_environments) >= 1 && length(q.compute_environments) <= 3])
    error_message = "job_queues[*].compute_environments: 1-3."
  }

  validation {
    condition     = alltrue([for q in values(var.job_queues) : contains(["ENABLED", "DISABLED"], q.state)])
    error_message = "job_queues[*].state: ENABLED or DISABLED."
  }
}

variable "scheduling_policy" {
  description = "Fair-share scheduling policy for every module queue."
  type = object({
    enabled             = optional(bool, false)
    share_decay_seconds = optional(number, 0)
    compute_reservation = optional(number, 0)
    share_distribution = optional(list(object({
      share_identifier = string
      weight_factor    = optional(number, 1)
    })), [])
  })
  default  = {}
  nullable = false
}

variable "readonly_root_filesystem" {
  description = "Read-only root filesystem for job containers."
  type        = bool
  nullable    = false
}

variable "job_definitions" {
  description = "Container job definitions by key."
  type = map(object({
    image                    = string
    platform                 = optional(string, "FARGATE")
    command                  = optional(list(string), [])
    vcpu                     = optional(number, 1)
    memory                   = optional(number, 2048)
    environment              = optional(map(string), {})
    secrets                  = optional(map(string), {})
    user                     = optional(string)
    readonly_root_filesystem = optional(bool)
    writable_paths           = optional(list(string), [])
    parameters               = optional(map(string), {})
    attempts                 = optional(number, 1)
    timeout_seconds          = optional(number)
    evaluate_on_exit = optional(list(object({
      action           = string
      on_exit_code     = optional(string)
      on_reason        = optional(string)
      on_status_reason = optional(string)
    })), [])
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k in keys(var.job_definitions) : can(regex("^[a-z0-9][a-z0-9-]{0,31}$", k))])
    error_message = "job_definitions keys: 1-32 chars, a-z 0-9 -."
  }

  validation {
    condition     = alltrue([for j in values(var.job_definitions) : contains(["FARGATE", "EC2"], j.platform)])
    error_message = "job_definitions[*].platform: FARGATE or EC2."
  }

  validation {
    condition     = alltrue(flatten([for j in values(var.job_definitions) : [for k in keys(j.environment) : !can(regex("(?i)(PASSWORD|PASSWD|SECRET|TOKEN|API_?KEY|ACCESS_?KEY|PRIVATE_?KEY|CREDENTIAL|AUTH_DATA)", k))]]))
    error_message = "job_definitions[*].environment: no credential names; use secrets."
  }

  validation {
    condition     = alltrue([for j in values(var.job_definitions) : j.user == null || !can(regex("^(root|0)(:.*)?$", j.user))])
    error_message = "job_definitions[*].user: not root or 0."
  }

  validation {
    condition     = alltrue([for j in values(var.job_definitions) : j.attempts >= 1 && j.attempts <= 10 && (j.timeout_seconds == null || j.timeout_seconds >= 60)])
    error_message = "job_definitions: attempts 1-10, timeout_seconds 60 or more."
  }
}

variable "iam_role" {
  description = "Job role: extend it or bring your own."
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
  description = "CloudWatch log group for job output."
  type = object({
    enabled                     = optional(bool, true)
    retention_in_days           = optional(number, 365)
    log_group_class             = optional(string, "STANDARD")
    deletion_protection_enabled = optional(bool, true)
    kms_key_arn                 = optional(string)
  })
  default  = {}
  nullable = false
}
