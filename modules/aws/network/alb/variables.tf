variable "name" {
  description = "Name prefix for the ALB. If not provided, will be derived from application and environment."
  type        = string
  default     = null
}

variable "application" {
  description = "Logical application or product name used for resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Deployment environment name (e.g. dev, staging, prod)."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "The environment name must contain only lowercase alphanumeric characters and hyphens."
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "vpc_id" {
  description = "VPC ID where the ALB and Target Groups will be deployed"
  type        = string
}

variable "subnets" {
  description = "List of public subnets for the ALB"
  type        = list(string)
}

variable "internal" {
  description = "If true, the ALB will be internal"
  type        = bool
  default     = false
}

variable "idle_timeout" {
  description = "ALB idle timeout in seconds (how long a request can stay open). AWS default is 60."
  type        = number
  default     = 60
}

variable "security_groups" {
  description = "A list of security group IDs to assign to the ALB. If empty, a default security group will be created."
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks" {
  description = "Allowed CIDR blocks for ingress to the ALB (only used if default security group is created)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "listener_port" {
  description = "The port for the default HTTP/HTTPS listener"
  type        = number
  default     = 80
}

variable "listener_protocol" {
  description = "The protocol for the default HTTP/HTTPS listener"
  type        = string
  default     = "HTTP"
}

variable "default_target_group_name" {
  description = "The name suffix of the default target group"
  type        = string
  default     = "gateway"
}

variable "default_target_group_port" {
  description = "The port of the default target group"
  type        = number
  default     = 8000
}

variable "default_target_group_protocol" {
  description = "The protocol of the default target group"
  type        = string
  default     = "HTTP"
}

variable "default_target_group_target_type" {
  description = "The target type of the default target group (instance, ip, or lambda)"
  type        = string
  default     = "ip"
}

variable "default_health_check_path" {
  description = "Health check path for the default target group"
  type        = string
  default     = "/health"
}

variable "default_health_check_matcher" {
  description = "HTTP status code matcher for the default target group health check"
  type        = string
  default     = "200"
}

variable "default_health_check_interval" {
  description = "Health check interval in seconds for the default target group"
  type        = number
  default     = 30
}

variable "default_health_check_timeout" {
  description = "Health check timeout in seconds for the default target group"
  type        = number
  default     = 5
}

variable "default_health_check_healthy_threshold" {
  description = "Healthy threshold count for the default target group health check"
  type        = number
  default     = 2
}

variable "default_health_check_unhealthy_threshold" {
  description = "Unhealthy threshold count for the default target group health check"
  type        = number
  default     = 3
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS listener. When set, HTTP listener redirects to HTTPS."
  type        = string
  default     = null
}

variable "extra_routes" {
  description = "A map of additional routes/services to configure target groups and listener rules for"
  type = map(object({
    port              = number
    priority          = number
    paths             = list(string)
    health_check_path = optional(string, "/health")
    target_type       = optional(string, "ip")
  }))
  default = {}
}

variable "deletion_protection_enabled" {
  description = "Enable deletion protection on the ALB"
  type        = bool
  default     = true
}

variable "cloudwatch_logs" {
  description = "CloudWatch logs configuration for the ALB log group."
  type = object({
    retention_in_days           = number
    kms_key_arn                 = optional(string, null)
    deletion_protection_enabled = optional(bool, false)
  })
  default = null
}

variable "kms_key_arn" {
  description = "KMS Key ARN used for encrypting ALB access logs and CloudWatch logs. Strictly required."
  type        = string
}
