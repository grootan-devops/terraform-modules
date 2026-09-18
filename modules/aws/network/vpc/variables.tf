variable "name" {
  type        = string
  description = "Name for the VPC. If not provided, will be derived from application and environment."
  default     = null
}

variable "tags" {
  type        = map(string)
  description = "Additional tags to apply to all resources"
  default     = {}
}

variable "application" {
  type        = string
  description = "Logical application or product name used for resource naming and tagging"
}

variable "environment" {
  description = "Deployment environment name (e.g. dev, staging, prod)."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "The environment name must contain only lowercase alphanumeric characters and hyphens."
  }
}

variable "cidr_block" {
  type        = string
  description = "CIDR block for the VPC (e.g. 172.31.0.0/16)"

  validation {
    condition     = can(cidrnetmask(var.cidr_block))
    error_message = "cidr_block must be a valid IPv4 CIDR block notation (e.g. 10.0.0.0/16)."
  }
}

variable "aws_availability_zone_names" {
  type        = list(string)
  description = "List of AWS availability zone names to distribute subnets across"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for public subnets, one per availability zone"
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for private subnets with outbound internet access via NAT Gateway"
}

variable "intra_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for intra subnets with no outbound internet access"
}

variable "private_subnet_internet_gateway" {
  type        = bool
  description = "If true, routes 0.0.0.0/0 in private subnets to the Internet Gateway instead of a NAT Gateway (requires instances to have public IPs)."
  default     = false
}

variable "intra_subnet_internet_gateway" {
  type        = bool
  description = "If true, routes 0.0.0.0/0 in intra subnets to the Internet Gateway."
  default     = false
}

variable "dns" {
  type = object({
    enable_dns_support   = optional(bool, true)
    enable_dns_hostnames = optional(bool, true)
  })
  default = {}
}

variable "nat" {
  type = object({
    enabled            = optional(bool, true)
    mode               = optional(string, "regional")
    eip_allocation_ids = optional(map(string), {})
  })
  default = {}
  validation {
    condition     = contains(["regional", "single_az", "per_az", "none"], var.nat.mode)
    error_message = "nat.mode must be one of: regional, single_az, per_az, none."
  }
}

variable "dhcp_options" {
  type = object({
    enabled              = optional(bool, false)
    domain_name          = optional(string, null)
    domain_name_servers  = optional(list(string), ["AmazonProvidedDNS"])
    ntp_servers          = optional(list(string), [])
    netbios_name_servers = optional(list(string), [])
    netbios_node_type    = optional(number, null)
  })
  default = {}
}

variable "cloudwatch_logs" {
  type = object({
    enabled           = optional(bool, true)
    exports           = optional(list(string), ["vpc_flow"])
    retention_in_days = optional(map(number), { vpc_flow = 90 })
    kms_key_arn       = optional(string, null)
  })
  default = {
    enabled           = true
    exports           = ["vpc_flow"]
    retention_in_days = { vpc_flow = 90 }
  }
}

variable "vpc_endpoints" {
  type = object({
    enabled                   = optional(bool, false)
    services                  = optional(list(string), [])
    gateway_route_table_tiers = optional(list(string), ["public", "private", "intra"])
    interface_subnet_tier     = optional(string, "private")
    private_dns_enabled       = optional(bool, true)
    policies                  = optional(map(string), {})
    s3_buckets                = optional(list(string), [])
    dynamodb_gateway          = optional(bool, false)
    subnet_indices            = optional(list(number), null)
  })
  default = {}
}

variable "nacl" {
  type = object({
    public  = optional(list(any), [])
    private = optional(list(any), [])
    intra   = optional(list(any), [])
  })
  default = {}
}

variable "additional_routes" {
  type = object({
    public  = optional(list(any), [])
    private = optional(list(any), [])
    intra   = optional(list(any), [])
  })
  default = {}
}

variable "kms_key_arn" {
  description = "KMS Key ARN used for encrypting VPC Flow Logs in CloudWatch. Strictly required."
  type        = string
}
