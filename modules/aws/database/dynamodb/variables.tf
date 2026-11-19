variable "application" {
  description = "Application name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,23}$", var.application))
    error_message = "application: 2-24 chars, a-z 0-9 -, starts with a letter."
  }
}

variable "environment" {
  description = "Environment name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,11}$", var.environment))
    error_message = "environment: 2-12 chars, a-z 0-9 -, starts with a letter."
  }
}

variable "name" {
  description = "Table name."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,31}$", var.name))
    error_message = "name: 1-32 chars, a-z 0-9 -."
  }
}

variable "tags" {
  description = "Extra tags; governance tags win."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "hash_key" {
  description = "Partition key attribute."
  type        = string

  validation {
    condition     = length(var.hash_key) >= 1 && length(var.hash_key) <= 255
    error_message = "hash_key: 1-255 chars."
  }
}

variable "range_key" {
  description = "Sort key attribute."
  type        = string
  default     = null
}

variable "attributes" {
  description = "Key attribute types by name: S, N or B; unlisted keys are S."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for t in values(var.attributes) : contains(["S", "N", "B"], t)])
    error_message = "attributes: S, N or B."
  }
}

variable "billing_mode" {
  description = "PAY_PER_REQUEST or PROVISIONED."
  type        = string
  default     = "PAY_PER_REQUEST"
  nullable    = false

  validation {
    condition     = contains(["PAY_PER_REQUEST", "PROVISIONED"], var.billing_mode)
    error_message = "billing_mode: PAY_PER_REQUEST or PROVISIONED."
  }
}

variable "provisioned_capacity" {
  description = "PROVISIONED read and write units; the autoscaling minimum."
  type = object({
    read  = optional(number, 5)
    write = optional(number, 5)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.provisioned_capacity.read >= 1 && var.provisioned_capacity.write >= 1
    error_message = "provisioned_capacity: at least 1."
  }
}

variable "autoscaling" {
  description = "Target tracking for PROVISIONED tables and indexes."
  type = object({
    enabled            = optional(bool, true)
    max_read_capacity  = optional(number, 100)
    max_write_capacity = optional(number, 100)
    target_utilization = optional(number, 70)
    scale_in_cooldown  = optional(number, 60)
    scale_out_cooldown = optional(number, 60)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.autoscaling.target_utilization >= 20 && var.autoscaling.target_utilization <= 90
    error_message = "autoscaling.target_utilization: 20-90."
  }

  validation {
    condition = alltrue(concat(
      [var.autoscaling.max_read_capacity >= var.provisioned_capacity.read, var.autoscaling.max_write_capacity >= var.provisioned_capacity.write],
      [for i in values(var.global_secondary_indexes) : var.autoscaling.max_read_capacity >= coalesce(i.read_capacity, var.provisioned_capacity.read) && var.autoscaling.max_write_capacity >= coalesce(i.write_capacity, var.provisioned_capacity.write)]
    ))
    error_message = "autoscaling: max capacity below the provisioned capacity."
  }
}

variable "table_class" {
  description = "STANDARD or STANDARD_INFREQUENT_ACCESS."
  type        = string
  default     = "STANDARD"
  nullable    = false

  validation {
    condition     = contains(["STANDARD", "STANDARD_INFREQUENT_ACCESS"], var.table_class)
    error_message = "table_class: STANDARD or STANDARD_INFREQUENT_ACCESS."
  }
}

variable "point_in_time_recovery_days" {
  description = "Point-in-time recovery period in days."
  type        = number
  default     = 35
  nullable    = false

  validation {
    condition     = var.point_in_time_recovery_days >= 1 && var.point_in_time_recovery_days <= 35
    error_message = "point_in_time_recovery_days: 1-35."
  }
}

variable "deletion_protection" {
  description = "Block deletion of the table and replicas."
  type        = bool
  default     = true
  nullable    = false
}

variable "stream" {
  description = "DynamoDB Streams."
  type = object({
    enabled   = optional(bool, false)
    view_type = optional(string, "NEW_AND_OLD_IMAGES")
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["KEYS_ONLY", "NEW_IMAGE", "OLD_IMAGE", "NEW_AND_OLD_IMAGES"], var.stream.view_type)
    error_message = "stream.view_type: KEYS_ONLY, NEW_IMAGE, OLD_IMAGE or NEW_AND_OLD_IMAGES."
  }
}

variable "global_secondary_indexes" {
  description = "Global secondary indexes by name."
  type = map(object({
    hash_key           = string
    range_key          = optional(string)
    projection_type    = optional(string, "ALL")
    non_key_attributes = optional(list(string), [])
    read_capacity      = optional(number)
    write_capacity     = optional(number)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for i in values(var.global_secondary_indexes) : contains(["ALL", "KEYS_ONLY", "INCLUDE"], i.projection_type)])
    error_message = "global_secondary_indexes[*].projection_type: ALL, KEYS_ONLY or INCLUDE."
  }
}

variable "local_secondary_indexes" {
  description = "Local secondary indexes by name; set at creation only."
  type = map(object({
    range_key          = string
    projection_type    = optional(string, "ALL")
    non_key_attributes = optional(list(string), [])
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for i in values(var.local_secondary_indexes) : contains(["ALL", "KEYS_ONLY", "INCLUDE"], i.projection_type)])
    error_message = "local_secondary_indexes[*].projection_type: ALL, KEYS_ONLY or INCLUDE."
  }
}

variable "on_demand_throughput" {
  description = "PAY_PER_REQUEST maximum read and write request units."
  type = object({
    max_read_request_units  = optional(number)
    max_write_request_units = optional(number)
  })
  default  = {}
  nullable = false
}

variable "warm_throughput" {
  description = "Warm throughput in read and write units per second."
  type = object({
    read_units_per_second  = optional(number)
    write_units_per_second = optional(number)
  })
  default  = {}
  nullable = false
}

variable "kms" {
  description = "Encryption: {} AWS managed key, create = true module key, key_id your key (ARN or ID)."
  type = object({
    key_id                  = optional(string)
    create                  = optional(bool, false)
    deletion_window_in_days = optional(number, 30)
    policy_statements = optional(list(object({
      sid        = optional(string)
      effect     = optional(string, "Allow")
      actions    = list(string)
      resources  = optional(list(string))
      principals = optional(map(list(string)), {})
      conditions = optional(list(object({
        test     = string
        variable = string
        values   = list(string)
      })), [])
    })), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = !(var.kms.create && var.kms.key_id != null)
    error_message = "kms: set create or key_id, not both."
  }

  validation {
    condition     = var.kms.key_id == null || can(regex("^(arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/)?(mrk-[a-f0-9]{32}|[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})$", var.kms.key_id))
    error_message = "kms.key_id: a KMS key ARN or key ID."
  }
}

variable "replicas" {
  description = "Global table replicas by key: Region, key ARN, consistency mode."
  type = map(object({
    region_name      = string
    kms_key_arn      = optional(string)
    consistency_mode = optional(string)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = length(var.replicas) == 0 || (var.stream.enabled && var.stream.view_type == "NEW_AND_OLD_IMAGES")
    error_message = "replicas: need stream NEW_AND_OLD_IMAGES."
  }

  validation {
    condition     = !(var.kms.create || var.kms.key_id != null) || alltrue([for r in values(var.replicas) : r.kms_key_arn != null])
    error_message = "replicas: set kms_key_arn with a customer managed key."
  }

  validation {
    condition     = alltrue([for r in values(var.replicas) : contains(["EVENTUAL", "STRONG"], coalesce(r.consistency_mode, "EVENTUAL"))])
    error_message = "replicas[*].consistency_mode: EVENTUAL or STRONG."
  }
}

variable "witness_region" {
  description = "Witness Region for strong consistency."
  type        = string
  default     = null

  validation {
    condition     = var.witness_region == null || (length(var.replicas) == 1 && alltrue([for r in values(var.replicas) : r.consistency_mode == "STRONG"]))
    error_message = "witness_region: needs one STRONG replica."
  }
}

variable "contributor_insights" {
  description = "Contributor Insights on the table and listed indexes."
  type = object({
    enabled     = optional(bool, false)
    mode        = optional(string, "ACCESSED_AND_THROTTLED_KEYS")
    index_names = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["ACCESSED_AND_THROTTLED_KEYS", "THROTTLED_KEYS"], var.contributor_insights.mode)
    error_message = "contributor_insights.mode: ACCESSED_AND_THROTTLED_KEYS or THROTTLED_KEYS."
  }

  validation {
    condition     = alltrue([for n in var.contributor_insights.index_names : contains(keys(var.global_secondary_indexes), n)])
    error_message = "contributor_insights.index_names: global secondary index names."
  }
}

variable "alarms" {
  description = "Built-in CloudWatch alarms: switch, topics by severity, per-alarm overrides."
  type = object({
    enabled    = optional(bool, true)
    topic_arns = optional(map(string), {})
    overrides = optional(object({
      read_throttles          = optional(object({ enabled = optional(bool), threshold = optional(number), evaluation_periods = optional(number), datapoints_to_alarm = optional(number), period = optional(number), severity = optional(string) }), {})
      write_throttles         = optional(object({ enabled = optional(bool), threshold = optional(number), evaluation_periods = optional(number), datapoints_to_alarm = optional(number), period = optional(number), severity = optional(string) }), {})
      system_errors           = optional(object({ enabled = optional(bool), threshold = optional(number), evaluation_periods = optional(number), datapoints_to_alarm = optional(number), period = optional(number), severity = optional(string) }), {})
      consumed_read_capacity  = optional(object({ enabled = optional(bool), threshold = optional(number), evaluation_periods = optional(number), datapoints_to_alarm = optional(number), period = optional(number), severity = optional(string) }), {})
      consumed_write_capacity = optional(object({ enabled = optional(bool), threshold = optional(number), evaluation_periods = optional(number), datapoints_to_alarm = optional(number), period = optional(number), severity = optional(string) }), {})
    }), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for s, arn in var.alarms.topic_arns : can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]+$", arn))])
    error_message = "alarms.topic_arns: SNS topic ARNs by severity."
  }
}
