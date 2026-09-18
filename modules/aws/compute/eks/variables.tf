variable "application" {
  type        = string
  description = "Logical application or product name used for resource naming and tagging."
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.application))
    error_message = "Application name must contain only lowercase alphanumeric characters and hyphens."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment name (e.g. dev, staging, prod) used for isolation and tagging."
  validation {
    condition     = contains(["dev", "development", "staging", "uat", "pre-prod", "prod", "production"], lower(var.environment))
    error_message = "Environment must be one of: dev, development, staging, uat, pre-prod, prod, production."
  }
}

variable "name" {
  type        = string
  description = "Optional additional identifier appended to the cluster name."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "A map of additional tags to apply to all resources created by this module."
  default     = {}
}

variable "kms_key_arn" {
  type        = string
  description = "ARN of the customer-managed KMS key used for Kubernetes secrets envelope encryption and EBS root volume encryption."
  validation {
    condition     = can(regex("^arn:aws[a-z0-9-]*:kms:[a-z0-9-]+:[0-9]{12}:(key/[a-f0-9-]+|alias/.+)$", var.kms_key_arn))
    error_message = "kms_key_arn must be a valid AWS KMS key or alias ARN."
  }
}

variable "cluster_version" {
  type        = string
  default     = "1.30"
  description = "Kubernetes version for the EKS cluster control plane."
}

variable "control_plane_subnet_ids" {
  type        = list(string)
  description = "List of private subnet IDs for the EKS control plane ENIs."
}

variable "security_group_ids" {
  type        = list(string)
  default     = []
  description = "Additional security group IDs to associate with the cluster control plane."
}

variable "endpoint_public_access" {
  type        = bool
  default     = false
  description = "Whether the Amazon EKS public API server endpoint is enabled. Defaults to false for enterprise security baseline."
}

variable "public_access_cidrs" {
  type        = list(string)
  default     = []
  description = "List of CIDR blocks permitted to access the public API server endpoint when endpoint_public_access is true."
}

variable "node_groups" {
  type = map(object({
    subnet_ids          = list(string)
    instance_types      = list(string)
    ami_type            = optional(string)
    capacity_type       = optional(string)
    ami_release_version = optional(string)
    labels              = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
    scaling_config = object({
      min_size     = number
      max_size     = number
      desired_size = number
    })
    root_volume = optional(object({
      size       = optional(number, 50)
      iops       = optional(number)
      throughput = optional(number)
    }), {})
  }))
  default     = {}
  description = "Configuration map of managed node groups to create."
}
