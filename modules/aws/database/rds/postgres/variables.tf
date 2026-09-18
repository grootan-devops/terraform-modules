# ==============================================================================
# Base Configuration
# ==============================================================================

variable "name" {
  description = "The name of the RDS instance"
  type        = string
  default     = null
}

variable "application" {
  description = "The name of the product"
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

variable "engine_version" {
  description = "The engine version to use. Default is 18."
  type        = string
}

variable "instance_class" {
  description = "The instance type of the RDS instance"
  type        = string
}

variable "multi_az" {
  description = "Specifies if the RDS instance is multi-AZ"
  type        = bool
}

variable "parameters" {
  description = "A list of DB parameters (map) to apply"
  type        = list(map(string))
  default     = []
}

# ==============================================================================
# Storage
# ==============================================================================

variable "storage" {
  description = "Storage configuration for the RDS instance."
  type = object({
    allocated_storage     = optional(number, 20)
    max_allocated_storage = optional(number, 1000)
    storage_type          = optional(string, "gp3")
    iops                  = optional(number, null)
    storage_throughput    = optional(number, null)
  })
  default = {}
}

# ==============================================================================
# Credentials & Database Identity
# ==============================================================================

variable "credential" {
  description = "Credentials for the master DB user."
  type = object({
    username = string
    password = string
  })
  sensitive = true
}

# ==============================================================================
# Network & Security
# ==============================================================================

variable "vpc_id" {
  description = "The VPC ID where the RDS instance will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "A list of VPC subnet IDs to deploy the RDS instance"
  type        = list(string)
}

variable "availability_zone" {
  description = "The AZ for the RDS instance. Only use if multi_az is false."
  type        = string
  default     = null
}

variable "publicly_accessible" {
  description = "Bool to control if instance is publicly accessible."
  type        = bool
  default     = false
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the database"
  type        = list(string)
  default     = []
}

variable "egress_cidr_blocks" {
  description = "List of CIDR blocks allowed for outbound traffic from the database"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ==============================================================================
# Encryption
# ==============================================================================

variable "kms_key_id" {
  description = "The ARN for the KMS encryption key. Must be provided if storage_encrypted is true."
  type        = string
}

variable "enable_automated_backup_replication" {
  description = "Whether to enable automated backup replication to the secondary region."
  type        = bool
  default     = true
}

variable "automated_backup_replication_kms_key_arn" {
  description = "KMS Key ARN in the destination region for automated backup replication. Must be provided if enable_automated_backup_replication is true."
  type        = string
  default     = null
}

# ==============================================================================
# Backup & Maintenance
# ==============================================================================

variable "backup_retention_period" {
  description = "The days to retain backups for. Must be between 1 and 35."
  type        = number
}

# ==============================================================================
# Monitoring & Logging
# ==============================================================================

variable "monitoring_interval" {
  description = "The interval, in seconds, between points when Enhanced Monitoring metrics are collected. Valid Values: 0, 1, 5, 10, 15, 30, 60."
  type        = number
}

variable "performance_insights_retention_period" {
  description = "The amount of time in days to retain Performance Insights data. Valid values are 7, 731 (2 years) or a multiple of 31."
  type        = number
}

variable "cloudwatch_logs" {
  description = "CloudWatch logs configuration for RDS PostgreSQL."
  type = object({
    retention_in_days = object({
      postgresql        = number
      upgrade           = number
      iam-db-auth-error = number
    })
    exports                     = optional(set(string), ["postgresql", "upgrade"])
    kms_key_arn                 = string
    deletion_protection_enabled = optional(bool, true)
  })

  validation {
    condition = length(setsubtract(
      var.cloudwatch_logs.exports,
      ["postgresql", "upgrade", "iam-db-auth-error"]
    )) == 0
    error_message = "For RDS PostgreSQL, cloudwatch_logs_exports may only contain: postgresql, upgrade, iam-db-auth-error. Verify iam-db-auth-error support before enabling it."
  }
}

variable "tags" {
  type        = map(string)
  description = "Additional tags to apply to all resources"
  default     = {}
}
