variable "name" {
  description = "The name of the Valkey cluster"
  type        = string
  default     = null
}

variable "application" {
  description = "The name of the product/application"
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
  description = "A mapping of tags to assign to the resources"
  type        = map(string)
  default     = {}
}

variable "engine_version" {
  description = "The version number of the cache engine to be used"
  type        = string
  default     = "9.0"
}

variable "node_type" {
  description = "The compute and memory capacity of the nodes"
  type        = string
  default     = "cache.t4g.micro"
}

variable "num_cache_clusters" {
  description = "The number of cache clusters (primary and replicas) this replication group will have"
  type        = number
  default     = 1
}

variable "parameter_group_family" {
  description = "The family of the ElastiCache parameter group"
  type        = string
  default     = "valkey9"
}

variable "parameters" {
  description = "A list of ElastiCache parameters to apply to the parameter group"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "subnet_ids" {
  description = "A list of VPC subnet IDs for the cache subnet group"
  type        = list(string)
}

variable "vpc_id" {
  description = "The VPC ID where the security group should be created"
  type        = string
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access the Valkey cluster"
  type        = list(string)
  default     = []
}

variable "egress_cidr_blocks" {
  description = "List of CIDR blocks allowed for outbound traffic from the Valkey cluster"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "port" {
  description = "The port number on which each of the cache nodes accepts connections"
  type        = number
  default     = 6379
}

variable "kms_key_id" {
  description = "The ARN of the KMS key to use for encrypting data at rest"
  type        = string
}
