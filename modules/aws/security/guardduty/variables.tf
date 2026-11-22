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
    condition     = alltrue([for region in var.regions : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", region))])
    error_message = "regions: AWS Region codes."
  }
}

variable "kms" {
  description = "Export key: create = true module key, key_id your key (ARN or ID)."
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

variable "detector" {
  description = "Detector; off for the management account call."
  type = object({
    enabled                      = optional(bool, true)
    finding_publishing_frequency = optional(string, "FIFTEEN_MINUTES")
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["FIFTEEN_MINUTES", "ONE_HOUR", "SIX_HOURS"], var.detector.finding_publishing_frequency)
    error_message = "detector.finding_publishing_frequency: FIFTEEN_MINUTES, ONE_HOUR or SIX_HOURS."
  }
}

variable "organization_configuration" {
  description = "Organization auto-enable; off for account-only mode."
  type = object({
    enabled             = optional(bool, true)
    auto_enable_members = optional(string, "ALL")
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["ALL", "NEW", "NONE"], var.organization_configuration.auto_enable_members)
    error_message = "organization_configuration.auto_enable_members: ALL, NEW or NONE."
  }
}

variable "features" {
  description = "Protection plans; all on."
  type = object({
    s3_data_events               = optional(bool, true)
    eks_audit_logs               = optional(bool, true)
    ebs_malware_protection       = optional(bool, true)
    rds_login_events             = optional(bool, true)
    rds_data_risk                = optional(bool, true)
    lambda_network_logs          = optional(bool, true)
    runtime_monitoring           = optional(bool, true)
    eks_addon_management         = optional(bool, true)
    ecs_fargate_agent_management = optional(bool, true)
    ec2_agent_management         = optional(bool, true)
    ai_protection                = optional(bool, true)
  })
  default  = {}
  nullable = false
}

variable "publishing_destination" {
  description = "Findings export to S3; policies_only skips the export."
  type = object({
    enabled       = optional(bool, false)
    bucket_arn    = optional(string)
    prefix        = optional(string)
    policies_only = optional(bool, false)
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.publishing_destination.enabled || can(regex("^arn:aws[a-z-]*:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.publishing_destination.bucket_arn))
    error_message = "publishing_destination.bucket_arn: an S3 bucket ARN."
  }

  validation {
    condition     = !var.publishing_destination.enabled || var.detector.enabled
    error_message = "publishing_destination: needs detector.enabled."
  }

  validation {
    condition     = !var.publishing_destination.enabled || var.kms.create || var.kms.key_id != null
    error_message = "publishing_destination: needs kms.create or kms.key_id."
  }
}

variable "filters" {
  description = "Suppression rules and saved filters by key."
  type = map(object({
    description = optional(string)
    action      = optional(string, "ARCHIVE")
    rank        = optional(number)
    criteria = map(object({
      equals                = optional(list(string))
      not_equals            = optional(list(string))
      matches               = optional(list(string))
      not_matches           = optional(list(string))
      greater_than          = optional(string)
      greater_than_or_equal = optional(string)
      less_than             = optional(string)
      less_than_or_equal    = optional(string)
    }))
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for key in keys(var.filters) : can(regex("^[a-z0-9][a-z0-9-]{0,47}$", key))])
    error_message = "filters keys: 1-48 chars, a-z 0-9 -."
  }

  validation {
    condition     = alltrue([for filter in values(var.filters) : contains(["ARCHIVE", "NOOP"], filter.action)])
    error_message = "filters[*].action: ARCHIVE or NOOP."
  }

  validation {
    condition = alltrue([
      for filter in values(var.filters) : length(filter.criteria) > 0 && alltrue([
        for condition in values(filter.criteria) : anytrue([
          try(length(condition.equals) > 0, false),
          try(length(condition.not_equals) > 0, false),
          try(length(condition.matches) > 0, false),
          try(length(condition.not_matches) > 0, false),
          condition.greater_than != null,
          condition.greater_than_or_equal != null,
          condition.less_than != null,
          condition.less_than_or_equal != null,
        ])
      ])
    ])
    error_message = "filters: each criterion needs an operator."
  }

  validation {
    condition     = alltrue([for filter in values(var.filters) : filter.rank == null || (try(filter.rank >= 1 && filter.rank <= 100 && floor(filter.rank) == filter.rank, false))])
    error_message = "filters[*].rank: 1-100."
  }

  validation {
    condition     = length(var.filters) == 0 || var.detector.enabled
    error_message = "filters: needs detector.enabled."
  }
}

variable "organization_admin" {
  description = "Management account call: trusted access and delegated administrator."
  type = object({
    enabled               = optional(bool, false)
    account_id            = optional(string)
    manage_trusted_access = optional(bool, true)
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.organization_admin.enabled || can(regex("^[0-9]{12}$", var.organization_admin.account_id))
    error_message = "organization_admin.account_id: 12 digits."
  }

  validation {
    condition     = !var.organization_admin.enabled || !var.detector.enabled
    error_message = "organization_admin: set detector.enabled = false."
  }
}
