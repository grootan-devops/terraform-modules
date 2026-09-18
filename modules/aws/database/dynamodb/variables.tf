variable "name" {
  description = "The name of the table"
  type        = string
}

variable "billing_mode" {
  description = "Controls how you are charged for read and write throughput and how you manage capacity. Valid values are PROVISIONED and PAY_PER_REQUEST."
  type        = string
}

variable "hash_key" {
  description = "The attribute to use as the hash (partition) key. Must also be defined as an attribute."
  type        = string
}

variable "range_key" {
  description = "The attribute to use as the range (sort) key. Must also be defined as an attribute."
  type        = string
  default     = null
}

variable "attributes" {
  description = "List of nested attribute definitions. Only required for hash_key and range_key attributes."
  type = list(object({
    name = string
    type = string
  }))
  default = []
}

variable "read_capacity" {
  description = "Number of read units for this table. If the billing_mode is PROVISIONED, this field is required."
  type        = number
  default     = null
}

variable "write_capacity" {
  description = "Number of write units for this table. If the billing_mode is PROVISIONED, this field is required."
  type        = number
  default     = null
}

variable "table_class" {
  description = "The storage class of the table. Valid values are STANDARD and STANDARD_INFREQUENT_ACCESS."
  type        = string
}

variable "on_demand_throughput" {
  description = "Sets the maximum number of read and write units for the specified on-demand table."
  type = object({
    max_read_request_units  = number
    max_write_request_units = number
  })
  default = null
}

variable "warm_throughput" {
  description = "Provides visibility into the warm throughput configuration of the table."
  type = object({
    read_units_per_second  = number
    write_units_per_second = number
  })
  default = null
}

variable "global_table_witness" {
  description = "Witness Region in a Multi-Region Strong Consistency deployment."
  type = object({
    consistency_mode = string
  })
  default = null
}

variable "kms_key_arn" {
  description = "ARN of the KMS key for server-side encryption."
  type        = string
}

variable "pitr_recovery_period_in_days" {
  description = "Number of days to keep point-in-time recovery data."
  type        = number
}

variable "stream" {
  description = "Stream options."
  type = object({
    enabled   = bool
    view_type = string
  })
  default = {
    enabled   = false
    view_type = null
  }
}

variable "global_secondary_indexes" {
  description = "Describe a GSI for the table"
  type = list(object({
    name               = string
    hash_key           = string
    range_key          = optional(string)
    write_capacity     = optional(number)
    read_capacity      = optional(number)
    projection_type    = string
    non_key_attributes = optional(list(string))
  }))
  default = []
}

variable "local_secondary_indexes" {
  description = "Describe an LSI on the table; these can only be allocated at creation."
  type = list(object({
    name               = string
    range_key          = string
    projection_type    = string
    non_key_attributes = optional(list(string))
  }))
  default = []
}

variable "replicas" {
  description = "Configuration for aws_dynamodb_table_replica resources."
  type = map(object({
    region_name                 = string
    kms_key_arn                 = optional(string)
    point_in_time_recovery      = optional(bool)
    deletion_protection_enabled = optional(bool, true)
    consistency_mode            = optional(string)
  }))
  default = {}
}

variable "enable_contributor_insights" {
  description = "Enable CloudWatch contributor insights for the table"
  type        = bool
}

variable "contributor_insights_index_name" {
  description = "The global secondary index name for contributor insights, if applicable"
  type        = string
  default     = null
}

variable "application" {
  description = "Name of the product"
  type        = string
}

variable "deletion_protection_enabled" {
  description = "Enable deletion protection on the DynamoDB table"
  type        = bool
  default     = true
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
  type        = map(string)
  description = "Additional tags to apply to all resources"
  default     = {}
}
