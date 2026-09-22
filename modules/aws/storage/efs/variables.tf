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
  description = "Optional additional identifier appended to the resource name."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "A map of additional tags to apply to all resources created by this module."
  default     = {}
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the EFS mount targets and security groups are provisioned."
}

variable "subnet_ids" {
  type        = list(string)
  description = "List of private subnet IDs to create mount targets in."
}

variable "kms_key_arn" {
  type        = string
  description = "ARN of the customer-managed KMS key used to encrypt the EFS file system at rest."
  validation {
    condition     = can(regex("^arn:aws[a-z0-9-]*:kms:[a-z0-9-]+:[0-9]{12}:(key/[a-f0-9-]+|alias/.+)$", var.kms_key_arn))
    error_message = "kms_key_arn must be a valid AWS KMS key or alias ARN."
  }
}

variable "performance_mode" {
  type        = string
  default     = "generalPurpose"
  description = "EFS performance mode: generalPurpose or maxIO."
  validation {
    condition     = contains(["generalPurpose", "maxIO"], var.performance_mode)
    error_message = "performance_mode must be either generalPurpose or maxIO."
  }
}

variable "throughput_mode" {
  type        = string
  default     = "elastic"
  description = "EFS throughput mode: elastic, bursting, or provisioned."
  validation {
    condition     = contains(["elastic", "bursting", "provisioned"], var.throughput_mode)
    error_message = "throughput_mode must be one of: elastic, bursting, provisioned."
  }
}

variable "provisioned_throughput_in_mibps" {
  type        = number
  default     = null
  description = "Provisioned throughput in MiB/s; only used when throughput_mode is provisioned."
}

variable "transition_to_ia" {
  type        = string
  default     = "AFTER_7_DAYS"
  description = "Number of days before transitioning files to Infrequent Access storage."
}

variable "transition_to_archive" {
  type        = string
  default     = "AFTER_30_DAYS"
  description = "Number of days before transitioning files to Archive storage class (null to disable)."
}

variable "enable_backup" {
  type        = bool
  default     = true
  description = "Whether to enable AWS Backup automatic policy for EFS."
}

variable "security_group_ids" {
  type        = list(string)
  default     = []
  description = "Optional list of existing security group IDs to associate with mount targets. If empty, a default SG is created."
}

variable "allowed_security_group_ids" {
  type        = list(string)
  default     = []
  description = "List of security group IDs permitted to connect to EFS on port 2049."
}

variable "allowed_cidr_blocks" {
  type        = list(string)
  default     = []
  description = "List of CIDR blocks permitted to connect to EFS on port 2049."
}

variable "allowed_client_role_arns" {
  type        = list(string)
  default     = []
  description = "List of IAM role ARNs allowed to mount and write to the file system."
}

variable "access_points" {
  type = map(object({
    posix_user = optional(object({
      gid            = number
      uid            = number
      secondary_gids = optional(list(number))
    }))
    root_directory = optional(object({
      path = optional(string)
      creation_info = optional(object({
        owner_gid   = number
        owner_uid   = number
        permissions = string
      }))
    }))
  }))
  default     = {}
  description = "Map of access point configurations to create for this file system."
}
