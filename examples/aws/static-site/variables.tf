variable "region" {
  description = "Region."
  type        = string
  default     = "eu-west-1"
}

variable "application" {
  description = "Application name."
  type        = string
  default     = "storefront"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"
}

variable "domain_name" {
  description = "Public DNS zone."
  type        = string
  default     = "storefront.example.com"
}

variable "log_kms" {
  description = "Edge log encryption: create = true stack key, key_id your us-east-1 key, {} service encryption."
  type = object({
    key_id = optional(string)
    create = optional(bool, true)
  })
  default  = {}
  nullable = false
}
