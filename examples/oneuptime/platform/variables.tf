variable "application" {
  description = "Application name."
  type        = string
  default     = "shop"
}

variable "oneuptime_url" {
  description = "OneUptime instance URL."
  type        = string
}

variable "base_domain" {
  description = "Domain the shop answers on."
  type        = string
  default     = "example.com"
}

variable "teams_webhook_url" {
  description = "Teams webhook for the standard notifications."
  type        = string
  sensitive   = true
}

variable "major_incident_webhook_url" {
  description = "Teams webhook for the major incident bridge."
  type        = string
  sensitive   = true
}

variable "status_page_teams_webhook_url" {
  description = "Teams webhook subscribed to the internal status page."
  type        = string
  sensitive   = true
}

variable "status_page_owner_user_ids" {
  description = "User IDs that own the internal status page."
  type        = set(string)
  default     = []
}

variable "internal_status_page_cidrs" {
  description = "Networks allowed to open the internal status page."
  type        = list(string)
  default     = ["10.0.0.0/8"]
}
