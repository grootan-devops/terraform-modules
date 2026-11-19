variable "application" {
  description = "Application name."
  type        = string
  default     = "platform"

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
  description = "Regions to baseline. Empty: provider Region."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for region in var.regions : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", region))])
    error_message = "regions: Region codes."
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

  validation {
    condition     = var.kms.key_id == null || length(var.regions) <= 1 || startswith(var.kms.key_id, "mrk-")
    error_message = "kms.key_id: an mrk- key ID for several Regions."
  }
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary ARN for the module roles."
  type        = string
  default     = null
}

variable "cloudwatch_logs" {
  description = "Automation and session log groups."
  type = object({
    retention_in_days           = optional(number, 365)
    log_group_class             = optional(string, "STANDARD")
    deletion_protection_enabled = optional(bool, true)
  })
  default  = {}
  nullable = false
}

variable "account_settings" {
  description = "Service settings: block public document sharing, Automation logging, Default Host Management."
  type = object({
    enabled                       = optional(bool, true)
    block_public_document_sharing = optional(bool, true)
    automation_logging = optional(object({
      enabled = optional(bool, true)
    }), {})
    default_host_management = optional(object({
      enabled = optional(bool, true)
    }), {})
  })
  default  = {}
  nullable = false
}

variable "session_manager" {
  description = "Session Manager preferences and session logs."
  type = object({
    enabled                      = optional(bool, true)
    cloudwatch_streaming_enabled = optional(bool, true)
    idle_session_timeout         = optional(number, 20)
    max_session_duration         = optional(number, 60)
    run_as_enabled               = optional(bool, false)
    run_as_default_user          = optional(string, "")
    shell_profile = optional(object({
      linux   = optional(string, "")
      windows = optional(string, "")
    }), {})
    s3_logs = optional(object({
      enabled     = optional(bool, false)
      bucket      = optional(string)
      prefix      = optional(string, "")
      kms_key_arn = optional(string)
    }), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.session_manager.idle_session_timeout >= 1 && var.session_manager.idle_session_timeout <= 60 && floor(var.session_manager.idle_session_timeout) == var.session_manager.idle_session_timeout
    error_message = "session_manager.idle_session_timeout: 1-60."
  }

  validation {
    condition     = var.session_manager.max_session_duration >= 1 && var.session_manager.max_session_duration <= 1440 && floor(var.session_manager.max_session_duration) == var.session_manager.max_session_duration
    error_message = "session_manager.max_session_duration: 1-1440."
  }

  validation {
    condition     = !var.session_manager.run_as_enabled || var.session_manager.run_as_default_user != ""
    error_message = "session_manager.run_as_default_user is required with run_as_enabled."
  }

  validation {
    condition     = !var.session_manager.s3_logs.enabled || var.session_manager.s3_logs.bucket != null
    error_message = "session_manager.s3_logs.bucket is required when enabled."
  }
}

variable "patching" {
  description = "Quick Setup patch policy."
  type = object({
    enabled          = optional(bool, true)
    operation        = optional(string, "ScanAndInstall")
    scan_schedule    = optional(string, "cron(0 1 * * ? *)")
    install_schedule = optional(string, "cron(0 2 ? * SUN *)")
    reboot_option    = optional(string, "RebootIfNeeded")
    baselines = optional(object({
      use_default = optional(bool, true)
      custom = optional(map(object({
        operating_system        = string
        description             = optional(string)
        approve_after_days      = optional(number)
        patch_filters           = optional(map(list(string)))
        compliance_level        = optional(string, "HIGH")
        enable_non_security     = optional(bool, false)
        rejected_patches        = optional(list(string), [])
        rejected_patches_action = optional(string, "BLOCK")
      })), {})
    }), {})
    target = optional(object({
      type                = optional(string, "*")
      tag_key             = optional(string)
      tag_value           = optional(string)
      resource_group_name = optional(string)
      instance_ids        = optional(list(string), [])
    }), {})
    target_organizational_units = optional(list(string), [])
    output_logs = optional(object({
      enabled = optional(bool, false)
      bucket  = optional(string)
      prefix  = optional(string, "")
    }), {})
    attach_instance_policies = optional(bool, false)
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["Scan", "ScanAndInstall"], var.patching.operation)
    error_message = "patching.operation: Scan or ScanAndInstall."
  }

  validation {
    condition     = alltrue([for schedule in [var.patching.scan_schedule, var.patching.install_schedule] : can(regex("^cron\\(.+\\)$", schedule))])
    error_message = "patching: schedules are cron() expressions."
  }

  validation {
    condition     = contains(["RebootIfNeeded", "NoReboot"], var.patching.reboot_option)
    error_message = "patching.reboot_option: RebootIfNeeded or NoReboot."
  }

  validation {
    condition     = var.patching.baselines.use_default == (length(var.patching.baselines.custom) == 0)
    error_message = "patching.baselines: custom only with use_default = false."
  }

  validation {
    condition     = alltrue([for key in keys(var.patching.baselines.custom) : can(regex("^[a-z0-9][a-z0-9-]{0,31}$", key))])
    error_message = "patching.baselines.custom keys: 1-32 chars, a-z 0-9 -."
  }

  validation {
    condition     = length(distinct([for baseline in values(var.patching.baselines.custom) : baseline.operating_system])) == length(var.patching.baselines.custom)
    error_message = "patching.baselines.custom: one baseline per operating_system."
  }

  validation {
    condition = alltrue([
      for baseline in values(var.patching.baselines.custom) :
      baseline.patch_filters != null || contains(["AMAZON_LINUX_2", "AMAZON_LINUX_2023", "REDHAT_ENTERPRISE_LINUX", "ROCKY_LINUX", "ALMA_LINUX", "SUSE", "UBUNTU", "DEBIAN", "WINDOWS"], baseline.operating_system)
    ])
    error_message = "patching.baselines.custom: set patch_filters for this operating system."
  }

  validation {
    condition = alltrue([
      for baseline in values(var.patching.baselines.custom) :
      baseline.approve_after_days == null || (
        try(baseline.approve_after_days >= 0 && baseline.approve_after_days <= 360, false) &&
        (!contains(["UBUNTU", "DEBIAN"], baseline.operating_system) || baseline.approve_after_days == 0)
      )
    ])
    error_message = "patching.baselines.custom[*].approve_after_days: 0-360, 0 for UBUNTU and DEBIAN."
  }

  validation {
    condition     = contains(["*", "Tags", "ResourceGroups", "InstanceIds"], var.patching.target.type)
    error_message = "patching.target.type: *, Tags, ResourceGroups or InstanceIds."
  }

  validation {
    condition     = var.patching.target.type != "Tags" || (try(length(var.patching.target.tag_key) > 0, false) && try(length(var.patching.target.tag_value) > 0, false))
    error_message = "patching.target: tag_key and tag_value for Tags."
  }

  validation {
    condition     = var.patching.target.type != "ResourceGroups" || (try(length(var.patching.target.resource_group_name) > 0, false) && length(var.patching.target_organizational_units) == 0)
    error_message = "patching.target: resource_group_name for ResourceGroups, single account only."
  }

  validation {
    condition = var.patching.target.type != "InstanceIds" || (
      length(var.patching.target.instance_ids) >= 1 && length(var.patching.target.instance_ids) <= 25 &&
      alltrue([for id in var.patching.target.instance_ids : can(regex("^i-[0-9a-f]{8,17}$", id))])
    )
    error_message = "patching.target.instance_ids: 1-25 EC2 instance IDs for InstanceIds."
  }

  validation {
    condition     = alltrue([for ou in var.patching.target_organizational_units : can(regex("^(r-[0-9a-z]{4,32}|ou-[0-9a-z]{4,32}-[0-9a-z]{8,32})$", ou))])
    error_message = "patching.target_organizational_units: r- or ou- IDs."
  }

  validation {
    condition     = !var.patching.output_logs.enabled || var.patching.output_logs.bucket != null
    error_message = "patching.output_logs.bucket is required when enabled."
  }
}

variable "inventory" {
  description = "Inventory association and resource data sync."
  type = object({
    enabled             = optional(bool, true)
    schedule_expression = optional(string, "rate(1 day)")
    parameters          = optional(map(string), {})
    resource_data_sync = optional(object({
      enabled       = optional(bool, false)
      bucket_name   = optional(string)
      bucket_region = optional(string)
      kms_key_arn   = optional(string)
      prefix        = optional(string, "inventory")
      organization  = optional(bool, false)
    }), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.inventory.enabled || !var.inventory.resource_data_sync.enabled || var.inventory_bucket.enabled || var.inventory.resource_data_sync.bucket_name != null
    error_message = "inventory.resource_data_sync.bucket_name is required without inventory_bucket."
  }
}

variable "inventory_bucket" {
  description = "Central inventory bucket for resource data syncs."
  type = object({
    enabled             = optional(bool, false)
    allowed_account_ids = optional(list(string), [])
    organization_id     = optional(string)
    lifecycle = optional(object({
      expiration_days                        = optional(number)
      noncurrent_version_expiration_days     = optional(number, 90)
      abort_incomplete_multipart_upload_days = optional(number, 7)
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
    condition     = alltrue([for account_id in var.inventory_bucket.allowed_account_ids : can(regex("^[0-9]{12}$", account_id))])
    error_message = "inventory_bucket.allowed_account_ids: 12-digit account IDs."
  }

  validation {
    condition     = var.inventory_bucket.organization_id == null || can(regex("^o-[a-z0-9]{10,32}$", var.inventory_bucket.organization_id))
    error_message = "inventory_bucket.organization_id: an o- organization ID."
  }

  validation {
    condition     = !var.inventory_bucket.access_logs.enabled || var.inventory_bucket.access_logs.bucket != null
    error_message = "inventory_bucket.access_logs.bucket is required when enabled."
  }
}

variable "agent_update" {
  description = "SSM Agent update association."
  type = object({
    enabled             = optional(bool, true)
    schedule_expression = optional(string, "cron(0 2 ? * SUN *)")
    version             = optional(string)
    max_concurrency     = optional(string, "10%")
    max_errors          = optional(string, "10%")
  })
  default  = {}
  nullable = false
}

variable "quick_setup_host_management" {
  description = "Organization-wide Quick Setup host management."
  type = object({
    enabled                     = optional(bool, false)
    target_organizational_units = optional(list(string), [])
    target_regions              = optional(list(string))
    update_ssm_agent            = optional(bool, true)
    collect_inventory           = optional(bool, true)
    scan_instances              = optional(bool, true)
    update_ec2_launch_agent     = optional(bool, false)
    install_cloudwatch_agent    = optional(bool, false)
    update_cloudwatch_agent     = optional(bool, false)
    is_policy_attach_allowed    = optional(bool, false)
  })
  default  = {}
  nullable = false

  validation {
    condition = !var.quick_setup_host_management.enabled || (
      length(var.quick_setup_host_management.target_organizational_units) > 0 &&
      alltrue([for ou in var.quick_setup_host_management.target_organizational_units : can(regex("^(r-[0-9a-z]{4,32}|ou-[0-9a-z]{4,32}-[0-9a-z]{8,32})$", ou))])
    )
    error_message = "quick_setup_host_management.target_organizational_units: r- or ou- IDs."
  }

  validation {
    condition     = !var.quick_setup_host_management.enabled || !(var.inventory.enabled || var.agent_update.enabled)
    error_message = "quick_setup_host_management: disable inventory and agent_update."
  }
}

variable "organization_admin" {
  description = "Trusted access and delegated administrator for Systems Manager."
  type = object({
    enabled               = optional(bool, false)
    account_id            = optional(string)
    manage_trusted_access = optional(bool, true)
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.organization_admin.enabled || can(regex("^[0-9]{12}$", var.organization_admin.account_id))
    error_message = "organization_admin.account_id: a 12-digit account ID."
  }

  validation {
    condition = !var.organization_admin.enabled || !anytrue([
      var.account_settings.enabled,
      var.session_manager.enabled,
      var.patching.enabled && length(var.patching.target_organizational_units) == 0,
      var.inventory.enabled,
      var.inventory_bucket.enabled,
      var.agent_update.enabled,
    ])
    error_message = "organization_admin: disable every account feature in this call."
  }
}
