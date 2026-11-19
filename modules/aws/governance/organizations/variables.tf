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

variable "organization" {
  description = "Adopted organization: manage enabled policy types."
  type = object({
    manage                    = optional(bool, false)
    additional_policy_types   = optional(set(string), [])
    allow_policy_type_disable = optional(bool, false)
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for t in var.organization.additional_policy_types : contains(local.provider_policy_types, t)])
    error_message = "organization.additional_policy_types: provider policy types only."
  }
}

variable "trusted_access_service_principals" {
  description = "Service principals to enable trusted access for."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for p in var.trusted_access_service_principals : can(regex("^[a-z0-9][a-z0-9.-]*\\.amazonaws\\.com$", p))])
    error_message = "trusted_access_service_principals: service principals only."
  }

  validation {
    condition     = length(setintersection(var.trusted_access_service_principals, keys(local.service_owned_principals))) == 0
    error_message = "trusted_access_service_principals: principal owned by a service module."
  }
}

variable "delegated_administrators" {
  description = "Delegated administrators by label: account and service principal."
  type = map(object({
    account_id        = string
    service_principal = string
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for d in values(var.delegated_administrators) : can(regex("^[0-9]{12}$", d.account_id)) && can(regex("^[a-z0-9][a-z0-9.-]*\\.amazonaws\\.com$", d.service_principal))])
    error_message = "delegated_administrators: 12-digit account_id and a service principal."
  }

  validation {
    condition     = length(setintersection([for d in values(var.delegated_administrators) : d.service_principal], keys(local.service_owned_principals))) == 0
    error_message = "delegated_administrators: principal owned by a service module."
  }
}

variable "policy_management_delegation" {
  description = "Delegate policy management of policy_types to one member account."
  type = object({
    enabled      = optional(bool, false)
    account_id   = optional(string)
    policy_types = optional(set(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.policy_management_delegation.enabled || (can(regex("^[0-9]{12}$", var.policy_management_delegation.account_id)) && length(var.policy_management_delegation.policy_types) > 0 && alltrue([for t in var.policy_management_delegation.policy_types : contains(local.policy_types, t)]))
    error_message = "policy_management_delegation: 12-digit account_id and supported policy_types."
  }
}

variable "root_access_management" {
  description = "Centralized root access for member accounts."
  type = object({
    enabled  = optional(bool, true)
    features = optional(set(string), ["RootCredentialsManagement", "RootSessions"])
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.root_access_management.enabled || (length(var.root_access_management.features) > 0 && length(setsubtract(var.root_access_management.features, ["RootCredentialsManagement", "RootSessions"])) == 0)
    error_message = "root_access_management.features: RootCredentialsManagement, RootSessions."
  }
}

variable "exempt_principal_arns" {
  description = "Role or user ARN patterns exempt from every SCP."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for a in var.exempt_principal_arns : can(regex("^arn:[a-z*-]+:iam::([0-9]{12}|[*?]+):(role|user)/.+$", a))])
    error_message = "exempt_principal_arns: IAM role or user ARNs."
  }
}

variable "security_admin_role_arns" {
  description = "Role ARN patterns exempt from the security SCPs."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for a in var.security_admin_role_arns : can(regex("^arn:[a-z*-]+:iam::([0-9]{12}|[*?]+):role/.+$", a))])
    error_message = "security_admin_role_arns: IAM role ARNs."
  }
}

variable "network_admin_role_arns" {
  description = "Role ARN patterns exempt from network_guardrails."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for a in var.network_admin_role_arns : can(regex("^arn:[a-z*-]+:iam::([0-9]{12}|[*?]+):role/.+$", a))])
    error_message = "network_admin_role_arns: IAM role ARNs."
  }
}

variable "service_control_policies" {
  description = "SCP library; a policy exists only while it has targets."
  type = object({
    deny_leave_organization = optional(object({
      targets = optional(list(string), [])
    }), {})
    region_restriction = optional(object({
      targets                   = optional(list(string), [])
      allowed_regions           = optional(list(string), [])
      additional_global_actions = optional(list(string), [])
    }), {})
    root_user_restriction = optional(object({
      targets = optional(list(string), [])
    }), {})
    protect_security_services = optional(object({
      targets  = optional(list(string), [])
      services = optional(set(string), ["access-analyzer", "cloudtrail", "config", "guardduty", "inspector2", "macie2", "securityhub"])
    }), {})
    protect_security_kms_keys = optional(object({
      targets              = optional(list(string), [])
      protection_tag_key   = optional(string, "SecurityProtection")
      protection_tag_value = optional(string, "true")
    }), {})
    protect_audit_buckets = optional(object({
      targets     = optional(list(string), [])
      bucket_arns = optional(list(string), [])
    }), {})
    ec2_guardrails = optional(object({
      targets                             = optional(list(string), [])
      require_imdsv2                      = optional(bool, true)
      require_encrypted_volumes           = optional(bool, true)
      deny_disable_ebs_default_encryption = optional(bool, true)
      deny_public_ip                      = optional(bool, false)
      allowed_instance_types              = optional(list(string), [])
    }), {})
    network_guardrails = optional(object({
      targets = optional(list(string), [])
    }), {})
    restrict_iam_user_credentials = optional(object({
      targets                = optional(list(string), [])
      allowed_principal_arns = optional(list(string), [])
    }), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue(flatten([for p in values(var.service_control_policies) : [for t in p.targets : can(regex(local.target_pattern, t))]]))
    error_message = "service_control_policies targets: root, OU IDs or account IDs."
  }

  validation {
    condition     = length(var.service_control_policies.region_restriction.targets) == 0 || (length(var.service_control_policies.region_restriction.allowed_regions) > 0 && alltrue([for r in var.service_control_policies.region_restriction.allowed_regions : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", r))]))
    error_message = "region_restriction.allowed_regions: Region codes."
  }

  validation {
    condition     = length(setsubtract(var.service_control_policies.protect_security_services.services, ["access-analyzer", "cloudtrail", "config", "guardduty", "inspector2", "macie2", "securityhub"])) == 0
    error_message = "protect_security_services.services: unsupported service."
  }

  validation {
    condition     = (length(var.service_control_policies.protect_audit_buckets.targets) == 0 || length(var.service_control_policies.protect_audit_buckets.bucket_arns) > 0) && alltrue([for a in var.service_control_policies.protect_audit_buckets.bucket_arns : can(regex("^arn:[a-z-]+:s3:::[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", a))])
    error_message = "protect_audit_buckets.bucket_arns: S3 bucket ARNs."
  }

  validation {
    condition     = alltrue([for a in var.service_control_policies.restrict_iam_user_credentials.allowed_principal_arns : can(regex("^arn:[a-z*-]+:iam::([0-9]{12}|[*?]+):(role|user)/.+$", a))])
    error_message = "restrict_iam_user_credentials.allowed_principal_arns: IAM role or user ARNs."
  }
}

variable "resource_control_policies" {
  description = "RCP library; a policy exists only while it has targets."
  type = object({
    transport_security = optional(object({
      targets  = optional(list(string), [])
      services = optional(list(string), ["s3", "sqs", "kms", "secretsmanager", "sts"])
    }), {})
    identity_perimeter = optional(object({
      targets             = optional(list(string), [])
      services            = optional(list(string), ["s3", "sqs", "kms", "secretsmanager", "sts"])
      trusted_account_ids = optional(list(string), [])
    }), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue(flatten([for p in values(var.resource_control_policies) : [for t in p.targets : can(regex(local.target_pattern, t))]]))
    error_message = "resource_control_policies targets: root, OU IDs or account IDs."
  }

  validation {
    condition     = alltrue([for p in values(var.resource_control_policies) : length(p.services) > 0 && alltrue([for s in p.services : contains(local.rcp_supported_service_prefixes, s)])])
    error_message = "resource_control_policies services: RCP-supported prefixes."
  }

  validation {
    condition     = alltrue([for a in var.resource_control_policies.identity_perimeter.trusted_account_ids : can(regex("^[0-9]{12}$", a))])
    error_message = "identity_perimeter.trusted_account_ids: 12-digit account IDs."
  }
}

variable "declarative_policies" {
  description = "Declarative, tag and AI opt-out policies; each exists only while it has targets."
  type = object({
    ec2 = optional(object({
      targets                      = optional(list(string), [])
      http_put_response_hop_limit  = optional(number, 2)
      http_tokens_enforced         = optional(string, "no_preference")
      snapshot_block_public_access = optional(string, "block_all_sharing")
      image_block_public_access    = optional(string, "block_new_sharing")
      serial_console_access        = optional(string, "disabled")
      vpc_block_public_access = optional(object({
        enabled            = optional(bool, false)
        mode               = optional(string, "block_ingress")
        exclusions_allowed = optional(string, "enabled")
      }), {})
      allowed_images_settings = optional(object({
        enabled = optional(bool, false)
        state   = optional(string, "audit_mode")
        criteria = optional(list(object({
          allowed_image_providers       = optional(list(string))
          image_names                   = optional(list(string))
          marketplace_product_codes     = optional(list(string))
          maximum_days_since_created    = optional(number)
          maximum_days_since_deprecated = optional(number)
        })), [{ allowed_image_providers = ["amazon"] }])
      }), {})
      exception_message = optional(string)
    }), {})
    s3 = optional(object({
      targets = optional(list(string), [])
    }), {})
    tag_policy = optional(object({
      targets = optional(list(string), [])
      tag_keys = optional(map(object({
        allowed_values = optional(list(string))
        })), {
        Application = {}
        Environment = {}
        Name        = {}
        ManagedBy   = { allowed_values = ["Terraform"] }
      })
      enforced_for = optional(list(string), [])
    }), {})
    ai_services_opt_out = optional(object({
      targets           = optional(list(string), [])
      default_policy    = optional(string, "optOut")
      service_overrides = optional(map(string), {})
    }), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue(flatten([for p in values(var.declarative_policies) : [for t in p.targets : can(regex(local.target_pattern, t))]]))
    error_message = "declarative_policies targets: root, OU IDs or account IDs."
  }

  validation {
    condition = (
      contains(["no_preference", "enabled", "disabled"], var.declarative_policies.ec2.http_tokens_enforced) &&
      var.declarative_policies.ec2.http_put_response_hop_limit >= 1 && var.declarative_policies.ec2.http_put_response_hop_limit <= 64 &&
      contains(["block_all_sharing", "block_new_sharing", "unblocked"], var.declarative_policies.ec2.snapshot_block_public_access) &&
      contains(["block_new_sharing", "unblocked"], var.declarative_policies.ec2.image_block_public_access) &&
      contains(["enabled", "disabled"], var.declarative_policies.ec2.serial_console_access) &&
      contains(["off", "block_ingress", "block_bidirectional"], var.declarative_policies.ec2.vpc_block_public_access.mode) &&
      contains(["enabled", "disabled"], var.declarative_policies.ec2.vpc_block_public_access.exclusions_allowed) &&
      contains(["enabled", "disabled", "audit_mode"], var.declarative_policies.ec2.allowed_images_settings.state) &&
      length(var.declarative_policies.ec2.allowed_images_settings.criteria) <= 10
    )
    error_message = "declarative_policies.ec2: value outside the EC2 policy syntax."
  }

  validation {
    condition     = alltrue([for e in var.declarative_policies.tag_policy.enforced_for : can(regex("^[a-z0-9-]+:([a-zA-Z0-9-]+|ALL_SUPPORTED)$", e))]) && alltrue([for k in keys(var.declarative_policies.tag_policy.tag_keys) : length(k) > 0 && length(k) <= 128])
    error_message = "tag_policy: enforced_for service:resource; tag keys 1-128 chars."
  }

  validation {
    condition     = contains(["optIn", "optOut"], var.declarative_policies.ai_services_opt_out.default_policy) && alltrue([for v in values(var.declarative_policies.ai_services_opt_out.service_overrides) : contains(["optIn", "optOut"], v)]) && !contains(keys(var.declarative_policies.ai_services_opt_out.service_overrides), "default")
    error_message = "ai_services_opt_out: optIn or optOut; no default override."
  }
}

variable "custom_policies" {
  description = "Extra policies by key: type, description, content, targets."
  type = map(object({
    type        = string
    description = optional(string)
    content     = string
    targets     = list(string)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for p in values(var.custom_policies) : contains(local.policy_types, p.type)])
    error_message = "custom_policies type: supported policy type."
  }

  validation {
    condition     = alltrue([for k in keys(var.custom_policies) : can(regex("^[a-z0-9][a-z0-9-]{0,47}$", k)) && !contains([for l in local.library_policy_keys : replace(l, "_", "-")], k)])
    error_message = "custom_policies keys: 1-48 chars a-z 0-9 -, not a library key."
  }

  validation {
    condition     = alltrue([for p in values(var.custom_policies) : can(jsondecode(p.content))])
    error_message = "custom_policies content: valid JSON."
  }

  validation {
    condition     = alltrue([for p in values(var.custom_policies) : length(p.targets) > 0 && alltrue([for t in p.targets : can(regex(local.target_pattern, t))])])
    error_message = "custom_policies targets: root, OU IDs or account IDs."
  }
}
