variable "statements" {
  description = "Typed policy statements."
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

  validation {
    condition     = alltrue([for s in var.statements : contains(["Allow", "Deny"], s.effect)])
    error_message = "effect: Allow or Deny."
  }

  validation {
    condition     = alltrue([for s in var.statements : length(s.actions) > 0])
    error_message = "actions: must not be empty."
  }

  validation {
    condition     = alltrue([for s in var.statements : alltrue([for k in keys(s.principals) : contains(["AWS", "Service", "Federated", "CanonicalUser"], k)])])
    error_message = "principals: AWS, Service, Federated or CanonicalUser."
  }

  validation {
    condition     = alltrue([for s in var.statements : s.resources != null || length(var.default_resources) > 0])
    error_message = "Set resources or default_resources."
  }

  validation {
    condition = var.allow_public || alltrue([
      for s in var.statements : !(s.effect == "Allow" && length(s.conditions) == 0 && contains(flatten(values(s.principals)), "*"))
    ])
    error_message = "Allow for principal * needs a condition."
  }
}

variable "default_resources" {
  description = "Resources for statements without resources."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "source_documents" {
  description = "Policy JSON documents placed first."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for d in var.source_documents : can(jsondecode(d).Statement)])
    error_message = "source_documents: policy JSON with Statement."
  }
}

variable "allow_public" {
  description = "Allow principal * without a condition."
  type        = bool
  default     = false
  nullable    = false
}
