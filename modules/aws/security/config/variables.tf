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

variable "recorder" {
  description = "Configuration recorder, delivery channel and retention in every Region."
  type = object({
    enabled                = optional(bool, true)
    name                   = optional(string, "default")
    delivery_channel_name  = optional(string, "default")
    global_resource_region = optional(string)
    recording_frequency    = optional(string, "CONTINUOUS")
    recording_mode_override = optional(object({
      enabled             = optional(bool, false)
      description         = optional(string)
      recording_frequency = optional(string, "DAILY")
      resource_types      = optional(list(string), [])
    }), {})
    snapshot_delivery_frequency = optional(string, "TwentyFour_Hours")
    retention_period_in_days    = optional(number, 2557)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.recorder.retention_period_in_days >= 30 && var.recorder.retention_period_in_days <= 2557
    error_message = "recorder.retention_period_in_days: 30-2557."
  }

  validation {
    condition     = contains(["CONTINUOUS", "DAILY"], var.recorder.recording_frequency) && contains(["CONTINUOUS", "DAILY"], var.recorder.recording_mode_override.recording_frequency)
    error_message = "recorder: recording_frequency CONTINUOUS or DAILY."
  }

  validation {
    condition     = !var.recorder.recording_mode_override.enabled || length(var.recorder.recording_mode_override.resource_types) > 0
    error_message = "recorder.recording_mode_override.resource_types: required when enabled."
  }
}

variable "service_linked_role" {
  description = "Create AWSServiceRoleForConfig."
  type = object({
    enabled = optional(bool, false)
  })
  default  = {}
  nullable = false
}

variable "bucket" {
  description = "Delivery bucket: create it (enabled) or name an existing one."
  type = object({
    enabled             = optional(bool, true)
    name                = optional(string)
    key_prefix          = optional(string)
    allowed_account_ids = optional(list(string), [])
    organization_id     = optional(string)
    lifecycle = optional(object({
      expiration_days                        = optional(number, 2557)
      noncurrent_version_expiration_days     = optional(number, 90)
      abort_incomplete_multipart_upload_days = optional(number, 7)
      transitions = optional(list(object({
        days          = number
        storage_class = string
      })), [])
    }), {})
    access_logs = optional(object({
      enabled = optional(bool, false)
      bucket  = optional(string)
      prefix  = optional(string)
    }), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.bucket.enabled || !var.recorder.enabled || var.bucket.name != null
    error_message = "bucket.name: required when bucket.enabled = false."
  }

  validation {
    condition     = var.bucket.name == null || can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket.name))
    error_message = "bucket.name: a valid S3 bucket name."
  }

  validation {
    condition     = alltrue([for account_id in var.bucket.allowed_account_ids : can(regex("^[0-9]{12}$", account_id))])
    error_message = "bucket.allowed_account_ids: 12-digit account IDs."
  }

  validation {
    condition     = var.bucket.organization_id == null || can(regex("^o-[a-z0-9]{10,32}$", var.bucket.organization_id))
    error_message = "bucket.organization_id: an organization ID (o-...)."
  }

  validation {
    condition     = !var.bucket.access_logs.enabled || var.bucket.access_logs.bucket != null
    error_message = "bucket.access_logs.bucket: required when enabled."
  }
}

variable "aggregator" {
  description = "Organization configuration aggregator."
  type = object({
    enabled                  = optional(bool, false)
    all_regions              = optional(bool, true)
    regions                  = optional(list(string), [])
    region                   = optional(string)
    permissions_boundary_arn = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.aggregator.enabled || var.aggregator.all_regions || length(var.aggregator.regions) > 0
    error_message = "aggregator.regions: required when all_regions = false."
  }
}

variable "organization_rules" {
  description = "Managed rule set as organization rules; its tuning also shapes account_rules."
  type = object({
    enabled                  = optional(bool, false)
    regions                  = optional(list(string))
    excluded_accounts        = optional(list(string), [])
    disabled_rules           = optional(list(string), [])
    rule_parameter_overrides = optional(map(map(string)), {})
    required_tag_keys        = optional(list(string), ["Application", "Environment", "Name", "ManagedBy"])
    required_tag_values      = optional(map(string), {})
    additional_rules = optional(map(object({
      rule_identifier             = string
      description                 = optional(string)
      input_parameters            = optional(map(string), {})
      maximum_execution_frequency = optional(string)
      resource_types_scope        = optional(list(string))
      resource_id_scope           = optional(string)
      tag_key_scope               = optional(string)
      tag_value_scope             = optional(string)
      excluded_accounts           = optional(list(string))
      regions                     = optional(list(string))
    })), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for reference in concat(var.organization_rules.disabled_rules, keys(var.organization_rules.rule_parameter_overrides)) : contains(local.managed_rule_references, reference)])
    error_message = "organization_rules: unknown rule key or identifier."
  }

  validation {
    condition     = length(var.organization_rules.required_tag_keys) >= 1 && length(var.organization_rules.required_tag_keys) <= 6
    error_message = "organization_rules.required_tag_keys: 1-6 keys."
  }

  validation {
    condition     = alltrue([for key in keys(var.organization_rules.additional_rules) : can(regex("^[a-z0-9][a-z0-9-]{0,47}$", key))])
    error_message = "organization_rules.additional_rules: keys of 1-48 chars, a-z 0-9 -."
  }
}

variable "account_rules" {
  description = "Managed rule set as account rules in this account."
  type = object({
    enabled = optional(bool, false)
    regions = optional(list(string))
  })
  default  = {}
  nullable = false

  validation {
    condition     = !(var.account_rules.enabled && var.organization_rules.enabled)
    error_message = "account_rules: not with organization_rules."
  }
}

variable "conformance_packs" {
  description = "Organization conformance packs by key."
  type = map(object({
    template_body          = optional(string)
    template_s3_uri        = optional(string)
    input_parameters       = optional(map(string), {})
    excluded_accounts      = optional(list(string), [])
    delivery_s3_bucket     = optional(string)
    delivery_s3_key_prefix = optional(string)
    regions                = optional(list(string))
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for pack in values(var.conformance_packs) : (pack.template_body != null) != (pack.template_s3_uri != null)])
    error_message = "conformance_packs: set template_body or template_s3_uri."
  }

  validation {
    condition     = alltrue([for key in keys(var.conformance_packs) : can(regex("^[a-z0-9][a-z0-9-]{0,47}$", key))])
    error_message = "conformance_packs: keys of 1-48 chars, a-z 0-9 -."
  }
}

variable "remediations" {
  description = "Remediation configurations for rules in this account, by key."
  type = map(object({
    config_rule_name           = string
    target_id                  = string
    target_type                = optional(string, "SSM_DOCUMENT")
    target_version             = optional(string)
    resource_type              = optional(string)
    automatic                  = optional(bool, false)
    maximum_automatic_attempts = optional(number)
    retry_attempt_seconds      = optional(number)
    region                     = optional(string)
    parameters = optional(map(object({
      static_value   = optional(string)
      static_values  = optional(list(string))
      resource_value = optional(string)
    })), {})
    execution_controls = optional(object({
      concurrent_execution_rate_percentage = optional(number)
      error_percentage                     = optional(number)
    }))
  }))
  default  = {}
  nullable = false
}

variable "allow_automatic_remediation" {
  description = "Allow remediations with automatic = true."
  type        = bool
  default     = false
  nullable    = false
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
}
