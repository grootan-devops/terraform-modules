variable "region" {
  description = "Region."
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  description = "Account environment."
  type        = string
  default     = "prod"
}

variable "regions" {
  description = "Regions in use."
  type        = list(string)
  default     = ["eu-west-1", "us-east-1"]
}
