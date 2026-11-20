variable "application" {
  description = "Application name."
  type        = string
  default     = "platform"
  nullable    = false

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

variable "tags" {
  description = "Extra tags; governance tags win."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "regions" {
  description = "Regions to manage. Empty: provider Region."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for r in var.regions : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", r))])
    error_message = "regions: AWS Region codes."
  }
}

variable "vault" {
  description = "Backup vault, role and audit resources; name sets an exact vault name."
  type = object({
    enabled = optional(bool, true)
    name    = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.vault.name == null || can(regex("^[a-zA-Z0-9_-]{2,50}$", var.vault.name))
    error_message = "vault.name: 2-50 chars, a-z A-Z 0-9 - _."
  }
}

variable "deletion_protection" {
  description = "Keep recovery points when the vault is destroyed."
  type        = bool
  default     = true
  nullable    = false
}

variable "kms" {
  description = "Encryption: {} AWS managed key, create = true module key per Region, key_id your key (ARN or ID)."
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

  validation {
    condition     = length(distinct(var.regions)) <= 1 || var.kms.key_id == null || can(regex("^mrk-[a-f0-9]{32}$", var.kms.key_id))
    error_message = "kms.key_id: a bare mrk- key ID for several regions."
  }
}

variable "vault_admin_role_arns" {
  description = "Principal ARNs exempt from the recovery point deletion deny."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for arn in var.vault_admin_role_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(role/.+|user/.+|root)$", arn))])
    error_message = "vault_admin_role_arns: IAM role, user or root ARNs."
  }

  validation {
    condition     = !var.vault.enabled || length(var.vault_admin_role_arns) > 0
    error_message = "vault_admin_role_arns: at least one ARN."
  }

  validation {
    condition     = !var.vault.enabled || !var.audit_framework.enabled || contains(var.audit_framework.disabled_controls, "BACKUP_RECOVERY_POINT_MANUAL_DELETION_DISABLED") || length(var.vault_admin_role_arns) <= 5
    error_message = "vault_admin_role_arns: at most 5 with the manual deletion control."
  }
}

variable "copy_into_vault" {
  description = "Accounts or organization allowed to copy recovery points in."
  type = object({
    account_ids     = optional(list(string), [])
    organization_id = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for id in var.copy_into_vault.account_ids : can(regex("^[0-9]{12}$", id))]) && (var.copy_into_vault.organization_id == null || can(regex("^o-[a-z0-9]{10,32}$", var.copy_into_vault.organization_id)))
    error_message = "copy_into_vault: 12-digit account IDs, o- organization ID."
  }
}

variable "vault_lock" {
  description = "Vault Lock: GOVERNANCE or COMPLIANCE (irreversible), retention range in days."
  type = object({
    enabled             = optional(bool, false)
    mode                = optional(string, "GOVERNANCE")
    min_retention_days  = optional(number, 7)
    max_retention_days  = optional(number)
    changeable_for_days = optional(number, 3)
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["GOVERNANCE", "COMPLIANCE"], var.vault_lock.mode)
    error_message = "vault_lock.mode: GOVERNANCE or COMPLIANCE."
  }

  validation {
    condition     = var.vault_lock.min_retention_days >= 1 && var.vault_lock.min_retention_days <= coalesce(var.vault_lock.max_retention_days, 36500) && coalesce(var.vault_lock.max_retention_days, 36500) <= 36500 && var.vault_lock.changeable_for_days >= 3 && var.vault_lock.changeable_for_days <= 36500
    error_message = "vault_lock: 1 <= min <= max <= 36500, changeable_for_days 3-36500."
  }

  validation {
    condition     = !var.vault_lock.enabled || !var.plan.enabled || alltrue([for rule in values(var.rules) : rule.delete_after >= var.vault_lock.min_retention_days && rule.delete_after <= coalesce(var.vault_lock.max_retention_days, 36500)])
    error_message = "rules[*].delete_after: inside the vault_lock retention range."
  }
}

variable "vault_notifications" {
  description = "Vault events to an SNS topic per Region."
  type = object({
    enabled        = optional(bool, false)
    sns_topic_arns = optional(map(string), {})
    events = optional(list(string), [
      "BACKUP_JOB_FAILED",
      "BACKUP_JOB_EXPIRED",
      "COPY_JOB_FAILED",
      "RESTORE_JOB_FAILED",
      "CONTINUOUS_BACKUP_INTERRUPTED",
      "RECOVERY_POINT_MODIFIED",
    ])
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.vault_notifications.enabled || length(var.vault_notifications.sns_topic_arns) > 0
    error_message = "vault_notifications.sns_topic_arns: one topic ARN per Region."
  }
}

variable "plan" {
  description = "Backup plan and selection; off when an organization backup policy plans."
  type = object({
    enabled = optional(bool, true)
  })
  default  = {}
  nullable = false
}

variable "rules" {
  description = "Plan rules by name: cron schedule, retention, cold storage, continuous backup, copies."
  type = map(object({
    schedule                                  = optional(string)
    schedule_expression_timezone              = optional(string, "Etc/UTC")
    start_window                              = optional(number, 60)
    completion_window                         = optional(number, 10080)
    enable_continuous_backup                  = optional(bool, false)
    delete_after                              = number
    cold_storage_after                        = optional(number)
    opt_in_to_archive_for_supported_resources = optional(bool)
    copy_to = optional(list(object({
      destination_vault_arn = string
      delete_after          = optional(number)
      cold_storage_after    = optional(number)
    })), [])
  }))
  default = {
    daily = {
      schedule     = "cron(0 5 ? * * *)"
      delete_after = 35
    }
    monthly = {
      schedule     = "cron(0 5 1 * ? *)"
      delete_after = 365
    }
  }
  nullable = false

  validation {
    condition     = length(var.rules) > 0 && alltrue([for name in keys(var.rules) : can(regex("^[a-zA-Z0-9._-]{1,50}$", name))])
    error_message = "rules: at least one, names 1-50 chars a-z A-Z 0-9 . _ -."
  }

  validation {
    condition     = alltrue([for rule in values(var.rules) : rule.start_window >= 60 && rule.completion_window >= 60 && rule.delete_after >= 1])
    error_message = "rules: windows >= 60 minutes, delete_after >= 1 day."
  }

  validation {
    condition = alltrue(concat(
      [for rule in values(var.rules) : rule.delete_after >= coalesce(rule.cold_storage_after, -90) + 90],
      flatten([for rule in values(var.rules) : [for copy in rule.copy_to : coalesce(copy.delete_after, rule.delete_after) >= coalesce(copy.cold_storage_after, -90) + 90]]),
    ))
    error_message = "rules: delete_after >= cold_storage_after + 90."
  }

  validation {
    condition     = alltrue([for rule in values(var.rules) : !rule.enable_continuous_backup || (rule.delete_after <= 35 && rule.cold_storage_after == null)])
    error_message = "rules: continuous backup needs delete_after <= 35, no cold storage."
  }

  validation {
    condition     = alltrue(flatten([for rule in values(var.rules) : [for copy in rule.copy_to : can(regex("^arn:aws[a-z-]*:backup:[a-z0-9-]+:[0-9]{12}:backup-vault:.+$", copy.destination_vault_arn))]]))
    error_message = "rules[*].copy_to: backup vault ARNs."
  }
}

variable "resource_types" {
  description = "Types selected account-wide: dynamodb, ebs, ec2, efs, rds, s3."
  type        = list(string)
  default     = ["dynamodb", "ebs", "efs", "rds"]
  nullable    = false

  validation {
    condition     = alltrue([for t in var.resource_types : contains(["dynamodb", "ebs", "ec2", "efs", "rds", "s3"], t)])
    error_message = "resource_types: dynamodb, ebs, ec2, efs, rds or s3."
  }

  validation {
    condition     = length(var.resource_types) > 0 || length(var.additional_resources) > 0
    error_message = "resource_types or additional_resources: at least one."
  }
}

variable "additional_resources" {
  description = "Extra resource ARNs or wildcard patterns to select."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "not_resources" {
  description = "Resource ARNs or wildcard patterns to exclude."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "selection_tags" {
  description = "Tag conditions (AND) that narrow the selection."
  type = list(object({
    operator = optional(string, "string_equals")
    key      = string
    value    = string
  }))
  default  = []
  nullable = false

  validation {
    condition     = length(var.selection_tags) <= 30 && alltrue([for tag in var.selection_tags : contains(["string_equals", "string_like", "string_not_equals", "string_not_like"], tag.operator)])
    error_message = "selection_tags: at most 30, operator string_[not_]equals or string_[not_]like."
  }
}

variable "iam_role" {
  description = "Backup service role: extend it or bring your own."
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

variable "region_settings" {
  description = "Account-wide Region settings: service opt-in and full management."
  type = object({
    enabled                             = optional(bool, false)
    resource_type_opt_in_preference     = optional(map(bool), {})
    resource_type_management_preference = optional(map(bool))
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.region_settings.enabled || length(var.region_settings.resource_type_opt_in_preference) > 0
    error_message = "region_settings.resource_type_opt_in_preference: list every type."
  }
}

variable "audit_framework" {
  description = "Backup Audit Manager framework and control parameters."
  type = object({
    enabled                  = optional(bool, true)
    required_retention_days  = optional(number, 35)
    required_frequency_unit  = optional(string, "hours")
    required_frequency_value = optional(number, 24)
    recovery_point_age_unit  = optional(string, "days")
    recovery_point_age_value = optional(number, 1)
    disabled_controls        = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([for control in var.audit_framework.disabled_controls : contains([
      "BACKUP_RECOVERY_POINT_ENCRYPTED",
      "BACKUP_PLAN_MIN_FREQUENCY_AND_MIN_RETENTION_CHECK",
      "BACKUP_RECOVERY_POINT_MINIMUM_RETENTION_CHECK",
      "BACKUP_RESOURCES_PROTECTED_BY_BACKUP_PLAN",
      "BACKUP_RECOVERY_POINT_MANUAL_DELETION_DISABLED",
      "BACKUP_LAST_RECOVERY_POINT_CREATED",
      "BACKUP_RESOURCES_PROTECTED_BY_BACKUP_VAULT_LOCK",
    ], control)])
    error_message = "audit_framework.disabled_controls: controls of this module only."
  }
}

variable "report_plan" {
  description = "Audit Manager report plan to a caller bucket."
  type = object({
    enabled         = optional(bool, false)
    s3_bucket_name  = optional(string)
    s3_key_prefix   = optional(string)
    formats         = optional(list(string), ["CSV", "JSON"])
    report_template = optional(string, "RESOURCE_COMPLIANCE_REPORT")
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.report_plan.enabled || try(length(var.report_plan.s3_bucket_name) > 0, false)
    error_message = "report_plan.s3_bucket_name: required."
  }

  validation {
    condition     = !var.report_plan.enabled || !contains(["RESOURCE_COMPLIANCE_REPORT", "CONTROL_COMPLIANCE_REPORT"], var.report_plan.report_template) || var.audit_framework.enabled
    error_message = "report_plan: compliance reports need audit_framework.enabled."
  }
}

variable "organization_admin" {
  description = "Management account call: trusted access, delegated administrator, global settings."
  type = object({
    enabled               = optional(bool, false)
    account_id            = optional(string)
    manage_trusted_access = optional(bool, true)
    global_settings = optional(object({
      enabled                 = optional(bool, false)
      cross_account_backup    = optional(bool, true)
      delegated_administrator = optional(bool, true)
      multi_party_approval    = optional(bool, false)
    }), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.organization_admin.enabled || can(regex("^[0-9]{12}$", var.organization_admin.account_id))
    error_message = "organization_admin.account_id: 12 digits."
  }

  validation {
    condition     = !var.organization_admin.enabled || !var.vault.enabled
    error_message = "organization_admin: set vault.enabled = false."
  }
}
