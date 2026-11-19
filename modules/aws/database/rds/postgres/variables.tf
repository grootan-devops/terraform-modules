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
  description = "PostgreSQL version: major or major.minor."
  type        = string

  validation {
    condition     = can(regex("^[1-9][0-9]+(\\.[0-9]+)?$", var.engine_version)) && try(tonumber(split(".", var.engine_version)[0]) >= 15, false)
    error_message = "engine_version: 15 or later, major or major.minor."
  }
}

variable "instance_class" {
  description = "Instance class."
  type        = string
  default     = "db.t4g.medium"
  nullable    = false

  validation {
    condition     = startswith(var.instance_class, "db.")
    error_message = "instance_class: db.*."
  }
}

variable "multi_az" {
  description = "Multi-AZ standby."
  type        = bool
  default     = true
  nullable    = false
}

variable "storage" {
  description = "Storage: size, autoscaling limit (0: off), type, IOPS, throughput."
  type = object({
    allocated_storage     = optional(number, 20)
    max_allocated_storage = optional(number, 1000)
    type                  = optional(string, "gp3")
    iops                  = optional(number)
    throughput            = optional(number)
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.storage.type)
    error_message = "storage.type: gp2, gp3, io1 or io2."
  }

  validation {
    condition     = var.storage.allocated_storage >= 20 && (var.storage.max_allocated_storage == 0 || var.storage.max_allocated_storage >= var.storage.allocated_storage)
    error_message = "storage: at least 20 GiB; max_allocated_storage 0 or at least allocated_storage."
  }
}

variable "parameters" {
  description = "DB parameters by name; rds.force_ssl is fixed at 1."
  type = map(object({
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default  = {}
  nullable = false

  validation {
    condition     = !contains(keys(var.parameters), "rds.force_ssl")
    error_message = "parameters: rds.force_ssl is fixed at 1."
  }

  validation {
    condition     = alltrue([for p in values(var.parameters) : contains(["immediate", "pending-reboot"], p.apply_method)])
    error_message = "parameters[*].apply_method: immediate or pending-reboot."
  }
}

variable "credential" {
  description = "Master user; password managed in Secrets Manager unless password_wo is set."
  type = object({
    username                    = optional(string, "dbadmin")
    manage_master_user_password = optional(bool, true)
    kms_key_arn                 = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,62}$", var.credential.username))
    error_message = "credential.username: 1-63 chars, a-z A-Z 0-9 _, starts with a letter."
  }

  validation {
    condition     = !contains(["postgres", "admin", "root", "administrator", "rdsadmin", "master", "sa", "user"], lower(var.credential.username))
    error_message = "credential.username: not a default admin name (RDS.25)."
  }
}

variable "password_wo" {
  description = "Write-only master password."
  type        = string
  default     = null
  sensitive   = true
  ephemeral   = true

  validation {
    condition     = (var.password_wo == null) == var.credential.manage_master_user_password
    error_message = "Set password_wo or credential.manage_master_user_password, not both or neither."
  }
}

variable "password_wo_version" {
  description = "Master password version; change it to send a new password."
  type        = number
  default     = null

  validation {
    condition     = var.password_wo == null || var.password_wo_version != null
    error_message = "password_wo needs password_wo_version."
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

variable "port" {
  description = "Database port."
  type        = number
  default     = 5432
  nullable    = false

  validation {
    condition     = var.port >= 1150 && var.port <= 65535
    error_message = "port: 1150-65535."
  }
}

variable "security_group" {
  description = "Security group: ingress sources, egress and extra groups."
  type = object({
    create                        = optional(bool, true)
    ingress_security_group_ids    = optional(list(string), [])
    ingress_cidr_blocks           = optional(list(string), [])
    ingress_prefix_list_ids       = optional(list(string), [])
    egress_cidr_blocks            = optional(list(string), [])
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

variable "extended_support" {
  description = "Enrol in paid RDS Extended Support after standard support ends."
  type        = bool
  default     = false
  nullable    = false
}

variable "deletion_protection" {
  description = "Block deletion of the instance."
  type        = bool
  default     = true
  nullable    = false
}

variable "backup_retention_period" {
  description = "Automated backup retention in days."
  type        = number
  default     = 14
  nullable    = false

  validation {
    condition     = var.backup_retention_period >= 7 && var.backup_retention_period <= 35
    error_message = "backup_retention_period: 7-35."
  }
}

variable "backup_replication" {
  description = "Automated backup replication to another Region with a key there."
  type = object({
    enabled     = optional(bool, false)
    region      = optional(string)
    kms_key_arn = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.backup_replication.enabled || (var.backup_replication.region != null && var.backup_replication.kms_key_arn != null)
    error_message = "backup_replication: set region and kms_key_arn."
  }

  validation {
    condition     = var.backup_replication.region == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", coalesce(var.backup_replication.region, "x")))
    error_message = "backup_replication.region: a Region name."
  }
}

variable "monitoring_interval" {
  description = "Enhanced Monitoring interval in seconds."
  type        = number
  default     = 60
  nullable    = false

  validation {
    condition     = contains([1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval: 1, 5, 10, 15, 30 or 60."
  }
}

variable "iam_role" {
  description = "Enhanced Monitoring role: extend it or bring your own."
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

variable "performance_insights_retention_period" {
  description = "Performance Insights retention in days: 7, 731 or a multiple of 31."
  type        = number
  default     = 7
  nullable    = false

  validation {
    condition     = contains(concat([7, 731], [for m in range(1, 24) : m * 31]), var.performance_insights_retention_period)
    error_message = "performance_insights_retention_period: 7, 731 or a multiple of 31."
  }
}

variable "cloudwatch_logs" {
  description = "Log exports and their log groups."
  type = object({
    exports                     = optional(list(string), ["postgresql", "upgrade"])
    retention_in_days           = optional(number, 365)
    log_group_class             = optional(string, "STANDARD")
    deletion_protection_enabled = optional(bool, true)
    kms_key_arn                 = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(var.cloudwatch_logs.exports, "postgresql") && alltrue([for e in var.cloudwatch_logs.exports : contains(["postgresql", "upgrade", "iam-db-auth-error"], e)])
    error_message = "cloudwatch_logs.exports: postgresql plus upgrade or iam-db-auth-error (RDS.9)."
  }
}

variable "event_subscription" {
  description = "RDS event notifications to an SNS topic."
  type = object({
    enabled          = optional(bool, false)
    sns_topic_arn    = optional(string)
    event_categories = optional(list(string), ["availability", "configuration change", "deletion", "failover", "failure", "low storage", "maintenance", "notification", "recovery"])
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.event_subscription.enabled || var.event_subscription.sns_topic_arn != null
    error_message = "event_subscription: set sns_topic_arn."
  }

  validation {
    condition     = length(setsubtract(["configuration change", "failure", "maintenance"], var.event_subscription.event_categories)) == 0
    error_message = "event_subscription.event_categories: include configuration change, failure and maintenance (RDS.20)."
  }
}
