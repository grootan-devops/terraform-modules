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
  description = "Account-only mode: more Regions for the hub and standards."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for region in var.regions : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", region))])
    error_message = "regions: AWS Region codes."
  }

  validation {
    condition     = length(var.regions) == 0 || !var.organization_configuration.enabled
    error_message = "regions: needs organization_configuration.enabled = false."
  }
}

variable "hub" {
  description = "Hub, aggregator and standards in this account."
  type = object({
    enabled = optional(bool, true)
  })
  default  = {}
  nullable = false
}

variable "organization_admin" {
  description = "Management account call: delegated administrator."
  type = object({
    enabled    = optional(bool, false)
    account_id = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.organization_admin.enabled || can(regex("^[0-9]{12}$", var.organization_admin.account_id))
    error_message = "organization_admin.account_id: 12 digits."
  }

  validation {
    condition     = !var.organization_admin.enabled || !(var.hub.enabled && var.organization_configuration.enabled)
    error_message = "organization_admin: set hub.enabled = false."
  }
}

variable "finding_aggregator" {
  description = "Cross-Region aggregation into the provider Region."
  type = object({
    linking_mode      = optional(string, "ALL_REGIONS")
    specified_regions = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["ALL_REGIONS", "ALL_REGIONS_EXCEPT_SPECIFIED", "SPECIFIED_REGIONS", "NO_REGIONS"], var.finding_aggregator.linking_mode)
    error_message = "finding_aggregator.linking_mode: ALL_REGIONS, ALL_REGIONS_EXCEPT_SPECIFIED, SPECIFIED_REGIONS or NO_REGIONS."
  }

  validation {
    condition     = contains(["ALL_REGIONS_EXCEPT_SPECIFIED", "SPECIFIED_REGIONS"], var.finding_aggregator.linking_mode) == (length(var.finding_aggregator.specified_regions) > 0)
    error_message = "finding_aggregator.specified_regions: only and always with the *SPECIFIED* modes."
  }
}

variable "organization_configuration" {
  description = "Central configuration: policies and associations; off for account-only mode."
  type = object({
    enabled = optional(bool, true)
  })
  default  = {}
  nullable = false
}

variable "standards" {
  description = "Standards on or off by key, over the defaults; policies override."
  type        = map(bool)
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for standard in keys(var.standards) : contains(keys(local.standard_defaults), standard)])
    error_message = "standards: unknown standard key."
  }
}

variable "configuration_policies" {
  description = "Configuration policies by key; created only with targets."
  type = map(object({
    description                  = optional(string)
    service_enabled              = optional(bool, true)
    standards                    = optional(map(bool), {})
    additional_standard_arns     = optional(list(string), [])
    disabled_control_identifiers = optional(list(string), [])
    enabled_control_identifiers  = optional(list(string))
    custom_parameters = optional(list(object({
      security_control_id = string
      parameters = list(object({
        name        = string
        value_type  = optional(string, "CUSTOM")
        bool        = optional(bool)
        double      = optional(number)
        enum        = optional(string)
        enum_list   = optional(list(string))
        int         = optional(number)
        int_list    = optional(list(number))
        string      = optional(string)
        string_list = optional(list(string))
      }))
    })), [])
    targets = optional(list(string), [])
  }))
  default = {
    baseline = {}
  }
  nullable = false

  validation {
    condition     = length(var.configuration_policies) <= 20 && alltrue([for key in keys(var.configuration_policies) : can(regex("^[a-z0-9][a-z0-9-]{0,47}$", key))])
    error_message = "configuration_policies: at most 20, keys 1-48 chars a-z 0-9 -."
  }

  validation {
    condition     = alltrue(flatten([for policy in values(var.configuration_policies) : [for standard in keys(policy.standards) : contains(keys(local.standard_defaults), standard)]]))
    error_message = "configuration_policies[*].standards: unknown standard key."
  }

  validation {
    condition = alltrue(flatten([
      for policy in values(var.configuration_policies) : [
        for arn in policy.additional_standard_arns :
        can(regex("^arn:aws[a-z-]*:securityhub:[a-z0-9-]*::(standards|ruleset)/[A-Za-z0-9._/-]+$", arn)) && !strcontains(arn, "/service-managed-")
      ]
    ]))
    error_message = "additional_standard_arns: standards ARNs, not service-managed."
  }

  validation {
    condition = alltrue([
      for policy in values(var.configuration_policies) :
      policy.enabled_control_identifiers == null || (try(length(policy.enabled_control_identifiers), 0) > 0 && length(policy.disabled_control_identifiers) == 0)
    ])
    error_message = "configuration_policies: non-empty enabled_control_identifiers or disabled_control_identifiers, not both."
  }

  validation {
    condition     = alltrue(flatten([for policy in values(var.configuration_policies) : [for target in policy.targets : can(regex("^(r-[a-z0-9]{4,32}|ou-[a-z0-9]{4,32}-[a-z0-9]{8,32}|[0-9]{12})$", target))]]))
    error_message = "configuration_policies[*].targets: root, OU or account IDs."
  }

  validation {
    condition     = length(concat(flatten([for policy in values(var.configuration_policies) : policy.targets]), var.self_managed_targets)) == length(distinct(concat(flatten([for policy in values(var.configuration_policies) : policy.targets]), var.self_managed_targets)))
    error_message = "targets: each target once across policies and self_managed_targets."
  }

  validation {
    condition     = var.organization_configuration.enabled || alltrue([for policy in values(var.configuration_policies) : length(policy.targets) == 0])
    error_message = "configuration_policies: targets need organization_configuration.enabled."
  }
}

variable "self_managed_targets" {
  description = "Root, OU or account IDs set to self-managed."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for target in var.self_managed_targets : can(regex("^(r-[a-z0-9]{4,32}|ou-[a-z0-9]{4,32}-[a-z0-9]{8,32}|[0-9]{12})$", target))])
    error_message = "self_managed_targets: root, OU or account IDs."
  }

  validation {
    condition     = var.organization_configuration.enabled || length(var.self_managed_targets) == 0
    error_message = "self_managed_targets: needs organization_configuration.enabled."
  }
}

variable "cri_profile" {
  description = "CRI Profile v2.2 and its StandardsArn; off leaves CRI out."
  type = object({
    enabled      = optional(bool, false)
    standard_arn = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.cri_profile.enabled || can(regex("^arn:aws[a-z-]*:securityhub:[a-z0-9-]*::standards/[A-Za-z0-9._/-]+$", var.cri_profile.standard_arn))
    error_message = "cri_profile.standard_arn: a standards ARN."
  }
}

variable "product_subscriptions" {
  description = "Third-party product ARNs to accept findings from."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for arn in var.product_subscriptions : can(regex("^arn:aws[a-z-]*:securityhub:[a-z0-9-]+:([0-9]{12})?:product/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$", arn))])
    error_message = "product_subscriptions: Security Hub product ARNs."
  }
}
