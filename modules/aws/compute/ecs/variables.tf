variable "name" {
  description = "Name prefix for the ECS Cluster. If not provided, will be derived from application and environment."
  type        = string
  default     = null
}

variable "application" {
  description = "Logical application or product name used for resource naming and tagging"
  type        = string
  default     = ""
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
  description = "VPC ID where services are deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for ECS services tasks"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs to assign to ECS services. If empty, a default service security group with intra-mesh and ALB access rules will be created."
  type        = list(string)
  default     = []
}

variable "alb_security_group_id" {
  description = "The security group ID of the ALB (required if default service security group is created)"
  type        = string
  default     = null
}

variable "service_discovery_namespace" {
  description = "The name of the private DNS namespace for service discovery. If null, a default namespace using the name will be auto-generated. If empty string '', service discovery is disabled."
  type        = string
  default     = null
}

variable "image_tag" {
  description = "Default container image tag to reference if not specified in service"
  type        = string
  default     = "latest"
}

variable "task_execution_role_arn" {
  description = "The ARN of the task execution role. If not provided, a default role will be created."
  type        = string
  default     = null
}

variable "task_role_arn" {
  description = "The ARN of the task role. If not provided, a default role will be created."
  type        = string
  default     = null
}



variable "enable_autoscaling" {
  description = "Whether to enable CPU target-tracking autoscaling for services"
  type        = bool
  default     = false
}

variable "autoscaling_max_capacity" {
  description = "Max task count per service when autoscaling is enabled"
  type        = number
  default     = 6
}

variable "autoscaling_cpu_target" {
  description = "Target average CPU utilization (%) for autoscaling"
  type        = number
  default     = 60
}

variable "create_alb_ingress_rule" {
  description = "Whether to create the ingress rule from the ALB to the ECS services"
  type        = bool
  default     = true
}

variable "secret_arns" {
  description = "Secrets Manager secret ARNs the task execution role is allowed to read"
  type        = list(string)
  default     = []
}

variable "kms_key_arn" {
  description = "KMS Key ARN used to decrypt secrets and encrypt CloudWatch log groups. Strictly required."
  type        = string
}

variable "services" {
  description = "A map of services to deploy in the ECS cluster"
  type = map(object({
    container_port                    = number
    image                             = string
    cpu                               = optional(number, 256)
    memory                            = optional(number, 512)
    desired_count                     = optional(number, 1)
    environment                       = optional(map(string), null)
    secrets                           = optional(map(string), null)
    load_balancer_target_group_arn    = optional(string, null)
    task_role_arn                     = optional(string, null)
    task_role_policy_json             = optional(string, null)
    enable_deployment_circuit_breaker = optional(bool, false)
    rollback_on_failure               = optional(bool, false)
    enable_execute_command            = optional(bool, false)
    enable_service_connect            = optional(bool, false)
    service_connect_port_name         = optional(string, null)
    service_connect_discovery_name    = optional(string, null)
    service_connect_client_alias_port = optional(number, null)
    service_connect_client_alias_dns  = optional(string, null)
  }))
}
