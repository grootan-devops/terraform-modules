variable "region" {
  description = "Region."
  type        = string
  default     = "eu-west-1"
}

variable "application" {
  description = "Application name."
  type        = string
  default     = "shop"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"
}

variable "domain_name" {
  description = "Public DNS zone."
  type        = string
  default     = "shop.example.com"
}

variable "partner_principal_arn" {
  description = "Principal allowed to connect to the endpoint service."
  type        = string
  default     = "arn:aws:iam::210987654321:root"
}

variable "cache_token_version" {
  description = "Cache AUTH token version; increment to rotate."
  type        = number
  default     = 1
}
