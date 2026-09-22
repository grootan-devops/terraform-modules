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
  description = "ARN of the customer-managed KMS key used for Kubernetes secrets envelope encryption and CloudWatch log group encryption."
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

variable "subnet_ids" {
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

variable "log_types" {
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  description = "Control plane log types to enable for auditing and operational observability."
}

variable "log_retention_in_days" {
  type        = number
  default     = 90
  description = "Number of days to retain EKS control plane logs in CloudWatch."
}

variable "deletion_protection" {
  type        = bool
  default     = true
  description = "Whether to enable deletion protection on the EKS cluster."
}

variable "authentication_mode" {
  type        = string
  default     = "API_AND_CONFIG_MAP"
  description = "Authentication mode for the cluster (API, CONFIG_MAP, or API_AND_CONFIG_MAP)."
}

variable "bootstrap_cluster_creator_admin_permissions" {
  type        = bool
  default     = false
  description = "Whether to grant the IAM entity that creates the cluster administrative permissions."
}

variable "upgrade_support_type" {
  type        = string
  default     = "STANDARD"
  description = "Support type for the cluster upgrade policy (STANDARD or EXTENDED)."
}

variable "enable_default_addons" {
  type        = bool
  default     = true
  description = "Whether to install standard managed add-ons (VPC CNI, CoreDNS, Kube-Proxy, EBS CSI, EFS CSI)."
}

variable "enable_lb_controller_role" {
  type        = bool
  default     = true
  description = "Whether to create IAM role and policy for AWS Load Balancer Controller."
}

variable "addon_versions" {
  type = object({
    snapshot_controller = optional(string, null)
    pod_identity_agent  = optional(string, null)
    ebs_csi_driver      = optional(string, null)
    vpc_cni             = optional(string, null)
    coredns             = optional(string, null)
    kube_proxy          = optional(string, null)
    efs_csi_driver      = optional(string, null)
  })
  default     = {}
  description = "Explicit versions for EKS addons. When null, AWS default compatible versions are resolved."
}
