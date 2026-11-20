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
  description = "File system name."
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

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnet IDs, one mount target each."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.subnet_ids) > 0
    error_message = "subnet_ids: at least one subnet."
  }
}

variable "security_group" {
  description = "Mount target security group: NFS sources and extra groups."
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
    condition     = var.security_group.create || length(var.security_group.additional_security_group_ids) > 0
    error_message = "security_group: set additional_security_group_ids when create = false."
  }

  validation {
    condition     = !anytrue([for c in var.security_group.ingress_cidr_blocks : contains(["0.0.0.0/0", "::/0"], c)])
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

variable "performance_mode" {
  description = "generalPurpose or maxIO."
  type        = string
  default     = "generalPurpose"
  nullable    = false

  validation {
    condition     = contains(["generalPurpose", "maxIO"], var.performance_mode)
    error_message = "performance_mode: generalPurpose or maxIO."
  }
}

variable "throughput" {
  description = "Throughput mode and provisioned MiB/s."
  type = object({
    mode              = optional(string, "elastic")
    provisioned_mibps = optional(number)
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["elastic", "bursting", "provisioned"], var.throughput.mode)
    error_message = "throughput.mode: elastic, bursting or provisioned."
  }

  validation {
    condition     = (var.throughput.mode == "provisioned") == (var.throughput.provisioned_mibps != null)
    error_message = "throughput.provisioned_mibps: set only with provisioned."
  }
}

variable "lifecycle_policy" {
  description = "Storage class transitions; NONE turns one off."
  type = object({
    transition_to_ia                    = optional(string, "AFTER_7_DAYS")
    transition_to_archive               = optional(string, "AFTER_30_DAYS")
    transition_to_primary_storage_class = optional(string, "AFTER_1_ACCESS")
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for v in [var.lifecycle_policy.transition_to_ia, var.lifecycle_policy.transition_to_archive] : can(regex("^(NONE|AFTER_1_DAY|AFTER_(7|14|30|60|90|180|270|365)_DAYS)$", v))])
    error_message = "lifecycle_policy: AFTER_<n>_DAYS or NONE."
  }

  validation {
    condition     = contains(["AFTER_1_ACCESS", "NONE"], var.lifecycle_policy.transition_to_primary_storage_class)
    error_message = "lifecycle_policy.transition_to_primary_storage_class: AFTER_1_ACCESS or NONE."
  }
}

variable "backup" {
  description = "EFS automatic backups; storage/backup owns backups."
  type = object({
    enabled = optional(bool, false)
  })
  default  = {}
  nullable = false
}

variable "client_access" {
  description = "Mount target clients: principals, read only, root access."
  type = object({
    principal_arns = optional(list(string), [])
    read_only      = optional(bool, false)
    root_access    = optional(bool, false)
  })
  default  = {}
  nullable = false
}

variable "policy_statements" {
  description = "Extra file system policy statements; resources default to the file system."
  type = list(object({
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
  }))
  default  = []
  nullable = false
}

variable "access_points" {
  description = "Access points by key with an enforced POSIX user and root directory (EFS.3, EFS.4)."
  type = map(object({
    uid            = number
    gid            = number
    secondary_gids = optional(list(number), [])
    path           = string
    permissions    = optional(string, "0750")
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for ap in values(var.access_points) : can(regex("^/[^/].*$", ap.path))])
    error_message = "access_points: path starts with / and is not /."
  }

  validation {
    condition     = alltrue([for ap in values(var.access_points) : can(regex("^[0-7]{3,4}$", ap.permissions))])
    error_message = "access_points: permissions in octal."
  }
}
