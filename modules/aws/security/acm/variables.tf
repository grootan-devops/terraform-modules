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
  description = "Certificate name."
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

variable "domain_name" {
  description = "Certificate domain name."
  type        = string

  validation {
    condition     = can(regex("^(\\*\\.)?([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", var.domain_name))
    error_message = "domain_name: a lower-case domain name, optionally *. prefixed."
  }
}

variable "subject_alternative_names" {
  description = "Additional domain names."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for d in var.subject_alternative_names : can(regex("^(\\*\\.)?([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z]{2,63}$", d))])
    error_message = "subject_alternative_names: lower-case domain names, optionally *. prefixed."
  }
}

variable "key_algorithm" {
  description = "Key algorithm: RSA_2048, EC_prime256v1 or EC_secp384r1."
  type        = string
  default     = "RSA_2048"
  nullable    = false

  validation {
    condition     = contains(["RSA_2048", "EC_prime256v1", "EC_secp384r1"], var.key_algorithm)
    error_message = "key_algorithm: RSA_2048, EC_prime256v1 or EC_secp384r1 (ACM.2)."
  }
}

variable "validation" {
  description = "DNS validation records in a Route 53 zone."
  type = object({
    enabled = optional(bool, true)
    zone_id = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.validation.enabled || var.validation.zone_id != null
    error_message = "validation: set zone_id."
  }
}

variable "region" {
  description = "Certificate Region (us-east-1 for CloudFront). Null: provider Region."
  type        = string
  default     = null
}
