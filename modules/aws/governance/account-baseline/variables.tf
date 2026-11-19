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
  description = "Regions for per-Region settings. Empty: provider Region."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for r in var.regions : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", r))])
    error_message = "regions: Region codes."
  }
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary for the module roles."
  type        = string
  default     = null
}

variable "password_policy" {
  description = "IAM account password policy."
  type = object({
    enabled                        = optional(bool, true)
    minimum_password_length        = optional(number, 14)
    password_reuse_prevention      = optional(number, 24)
    max_password_age               = optional(number, 90)
    allow_users_to_change_password = optional(bool, true)
    hard_expiry                    = optional(bool, false)
  })
  default  = {}
  nullable = false

  validation {
    condition = (
      floor(var.password_policy.minimum_password_length) == var.password_policy.minimum_password_length &&
      var.password_policy.minimum_password_length >= 6 && var.password_policy.minimum_password_length <= 128 &&
      floor(var.password_policy.password_reuse_prevention) == var.password_policy.password_reuse_prevention &&
      var.password_policy.password_reuse_prevention >= 0 && var.password_policy.password_reuse_prevention <= 24 &&
      floor(var.password_policy.max_password_age) == var.password_policy.max_password_age &&
      var.password_policy.max_password_age >= 0 && var.password_policy.max_password_age <= 1095
    )
    error_message = "password_policy: length 6-128, reuse 0-24, age 0-1095."
  }
}

variable "support_role" {
  description = "AWS Support role (IAM.18) and who may assume it (empty: this account)."
  type = object({
    enabled                = optional(bool, true)
    trusted_principal_arns = optional(list(string), [])
    require_mfa            = optional(bool, false)
    max_session_duration   = optional(number, 3600)
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for a in var.support_role.trusted_principal_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:(root|role/.+|user/.+)$", a))])
    error_message = "support_role.trusted_principal_arns: IAM principal ARNs."
  }
}

variable "alternate_contacts" {
  description = "Alternate contacts; security is required (Account.1)."
  type = object({
    enabled    = optional(bool, true)
    account_id = optional(string)
    security = optional(object({
      name          = string
      title         = string
      email_address = string
      phone_number  = string
    }))
    billing = optional(object({
      name          = string
      title         = string
      email_address = string
      phone_number  = string
    }))
    operations = optional(object({
      name          = string
      title         = string
      email_address = string
      phone_number  = string
    }))
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.alternate_contacts.enabled || var.alternate_contacts.security != null
    error_message = "alternate_contacts.security is required."
  }

  validation {
    condition     = var.alternate_contacts.account_id == null || can(regex("^[0-9]{12}$", var.alternate_contacts.account_id))
    error_message = "alternate_contacts.account_id: 12 digits."
  }

  validation {
    condition = var.alternate_contacts.account_id == null || !anytrue([
      var.password_policy.enabled, var.support_role.enabled, var.ebs_default_encryption.enabled,
      var.s3_account_public_access_block.enabled, var.instance_metadata_defaults.enabled,
      var.ebs_snapshot_block_public_access.enabled, var.ami_block_public_access.enabled,
      var.serial_console_access_block.enabled, var.vpc_block_public_access.enabled, var.api_gateway_logging.enabled,
      var.ecr_registry_scanning.enabled, var.ecr_replication.enabled, length(var.ecr_pull_through_cache_rules) > 0,
    ])
    error_message = "alternate_contacts.account_id: disable every other setting."
  }
}

variable "ebs_default_encryption" {
  description = "EBS encryption by default; kms_key_arns sets a default key per Region."
  type = object({
    enabled      = optional(bool, true)
    kms_key_arns = optional(map(string), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for r, a in var.ebs_default_encryption.kms_key_arns : can(regex("^arn:aws[a-z-]*:kms:${r}:[0-9]{12}:key/[A-Za-z0-9-]+$", a))])
    error_message = "ebs_default_encryption.kms_key_arns: key ARNs in their Region."
  }
}

variable "s3_account_public_access_block" {
  description = "Account S3 Block Public Access (S3.1)."
  type = object({
    enabled = optional(bool, true)
  })
  default  = {}
  nullable = false
}

variable "instance_metadata_defaults" {
  description = "EC2 instance metadata defaults: IMDSv2 required (EC2.8)."
  type = object({
    enabled                     = optional(bool, true)
    http_put_response_hop_limit = optional(number, 2)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.instance_metadata_defaults.http_put_response_hop_limit >= 1 && var.instance_metadata_defaults.http_put_response_hop_limit <= 64
    error_message = "instance_metadata_defaults.http_put_response_hop_limit: 1-64."
  }
}

variable "ebs_snapshot_block_public_access" {
  description = "EBS snapshot block public access (EC2.182)."
  type = object({
    enabled = optional(bool, true)
    state   = optional(string, "block-all-sharing")
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["block-all-sharing", "block-new-sharing"], var.ebs_snapshot_block_public_access.state)
    error_message = "ebs_snapshot_block_public_access.state: block-all-sharing or block-new-sharing."
  }
}

variable "ami_block_public_access" {
  description = "AMI block public access."
  type = object({
    enabled = optional(bool, true)
  })
  default  = {}
  nullable = false
}

variable "serial_console_access_block" {
  description = "Keep EC2 serial console access off."
  type = object({
    enabled = optional(bool, true)
  })
  default  = {}
  nullable = false
}

variable "vpc_block_public_access" {
  description = "VPC block public access (EC2.172)."
  type = object({
    enabled = optional(bool, false)
    mode    = optional(string, "block-ingress")
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["block-ingress", "block-bidirectional"], var.vpc_block_public_access.mode)
    error_message = "vpc_block_public_access.mode: block-ingress or block-bidirectional."
  }
}

variable "api_gateway_logging" {
  description = "API Gateway account CloudWatch Logs role."
  type = object({
    enabled = optional(bool, true)
  })
  default  = {}
  nullable = false
}

variable "ecr_registry_scanning" {
  description = "ECR registry scanning (ECR.1); ENHANCED uses Amazon Inspector."
  type = object({
    enabled = optional(bool, true)
    type    = optional(string, "ENHANCED")
    rules = optional(list(object({
      scan_frequency = string
      filters        = optional(list(string), ["*"])
    })), [{ scan_frequency = "CONTINUOUS_SCAN" }])
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["ENHANCED", "BASIC"], var.ecr_registry_scanning.type) && alltrue([for r in var.ecr_registry_scanning.rules : contains(var.ecr_registry_scanning.type == "ENHANCED" ? ["SCAN_ON_PUSH", "CONTINUOUS_SCAN"] : ["SCAN_ON_PUSH", "MANUAL"], r.scan_frequency) && length(r.filters) > 0])
    error_message = "ecr_registry_scanning: ENHANCED or BASIC with matching frequencies."
  }
}

variable "ecr_replication" {
  description = "ECR replication rules, applied from every Region."
  type = object({
    enabled = optional(bool, false)
    rules = optional(list(object({
      destinations = list(object({
        region      = string
        registry_id = optional(string)
      }))
      repository_prefixes = optional(list(string), [])
    })), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.ecr_replication.enabled || (length(var.ecr_replication.rules) > 0 && length(var.ecr_replication.rules) <= 10)
    error_message = "ecr_replication.rules: 1-10 rules."
  }

  validation {
    condition     = alltrue(flatten([for r in var.ecr_replication.rules : [for d in r.destinations : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", d.region)) && (d.registry_id == null || can(regex("^[0-9]{12}$", d.registry_id)))]]))
    error_message = "ecr_replication destinations: Region code and 12-digit registry_id."
  }
}

variable "ecr_pull_through_cache_rules" {
  description = "ECR pull through cache rules by repository prefix."
  type = map(object({
    upstream_registry_url      = string
    upstream_repository_prefix = optional(string)
    credential_arn             = optional(string)
    custom_role_arn            = optional(string)
    region                     = optional(string)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k in keys(var.ecr_pull_through_cache_rules) : can(regex("^[a-z0-9]+(?:[._-][a-z0-9]+)*$", k)) && length(k) >= 2 && length(k) <= 30])
    error_message = "ecr_pull_through_cache_rules keys: 2-30 chars a-z 0-9 . _ -."
  }

  validation {
    condition     = alltrue([for r in values(var.ecr_pull_through_cache_rules) : r.region == null || contains(var.regions, coalesce(r.region, "-"))])
    error_message = "ecr_pull_through_cache_rules region: one of regions."
  }
}
