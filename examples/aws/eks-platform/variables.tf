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
