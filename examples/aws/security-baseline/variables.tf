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

variable "workload_account_ids" {
  description = "Member accounts that receive Identity Center assignments."
  type        = list(string)
  default     = ["111122223333"]
}
