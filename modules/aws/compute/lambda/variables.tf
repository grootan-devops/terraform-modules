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
  description = "Function name."
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

variable "description" {
  description = "Function description."
  type        = string
  default     = null
}

variable "package" {
  description = "Code: Zip (runtime, handler, s3_bucket/s3_key or filename; none deploys a placeholder) or Image (image_uri)."
  type = object({
    type               = optional(string, "Zip")
    runtime            = optional(string, "python3.14")
    handler            = optional(string)
    filename           = optional(string)
    s3_bucket          = optional(string)
    s3_key             = optional(string)
    image_uri          = optional(string)
    source_kms_key_arn = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["Zip", "Image"], var.package.type)
    error_message = "package.type: Zip or Image."
  }

  validation {
    condition     = var.package.type == "Image" || contains(["dotnet10", "java25", "java21", "java17.al2023", "java11.al2023", "java8.al2023", "nodejs24.x", "nodejs22.x", "python3.14", "python3.13", "python3.12", "ruby4.0", "ruby3.4", "provided.al2023"], var.package.runtime)
    error_message = "package.runtime: a supported Lambda runtime (Lambda.2)."
  }

  validation {
    condition     = var.package.type == "Zip" || var.package.image_uri != null
    error_message = "package.image_uri is required for Image."
  }

  validation {
    condition     = (var.package.s3_bucket == null) == (var.package.s3_key == null) && !(var.package.filename != null && var.package.s3_bucket != null)
    error_message = "package: set filename, or s3_bucket with s3_key."
  }
}

variable "architecture" {
  description = "x86_64 or arm64."
  type        = string
  default     = "x86_64"
  nullable    = false

  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "architecture: x86_64 or arm64."
  }
}

variable "memory_size" {
  description = "Memory in MB (128-10240)."
  type        = number
  default     = 128
  nullable    = false

  validation {
    condition     = var.memory_size >= 128 && var.memory_size <= 10240
    error_message = "memory_size: 128-10240."
  }
}

variable "timeout" {
  description = "Timeout in seconds (1-900)."
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition     = var.timeout >= 1 && var.timeout <= 900
    error_message = "timeout: 1-900."
  }
}

variable "ephemeral_storage_size" {
  description = "/tmp size in MB (512-10240)."
  type        = number
  default     = 512
  nullable    = false

  validation {
    condition     = var.ephemeral_storage_size >= 512 && var.ephemeral_storage_size <= 10240
    error_message = "ephemeral_storage_size: 512-10240."
  }
}

variable "concurrency" {
  description = "Reserved concurrency (null: unreserved) and provisioned concurrency on the alias (0: none)."
  type = object({
    reserved    = optional(number)
    provisioned = optional(number, 0)
  })
  default  = {}
  nullable = false

  validation {
    condition     = (var.concurrency.reserved == null || var.concurrency.reserved >= 0) && var.concurrency.provisioned >= 0
    error_message = "concurrency: values must be 0 or more."
  }
}

variable "alias_name" {
  description = "Alias that triggers, URLs and provisioned concurrency use."
  type        = string
  default     = "live"
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,128}$", var.alias_name)) && !can(regex("^[0-9]+$", var.alias_name))
    error_message = "alias_name: 1-128 chars of a-z A-Z 0-9 - _, not only digits."
  }
}

variable "environment_variables" {
  description = "Environment variables. No credentials: use secret_arns."
  type        = map(string)
  default     = {}
  nullable    = false
  sensitive   = true

  validation {
    condition     = alltrue([for k in keys(var.environment_variables) : !can(regex("(?i)(PASSWORD|PASSWD|SECRET|TOKEN|API_?KEY|ACCESS_?KEY|PRIVATE_?KEY|CREDENTIAL)", k))])
    error_message = "environment_variables: no credential names; use secret_arns."
  }
}

variable "secret_arns" {
  description = "Secrets Manager secrets the function may read."
  type        = list(string)
  default     = []
  nullable    = false
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

variable "iam_role" {
  description = "Execution role: extend it or bring your own."
  type = object({
    create                   = optional(bool, true)
    arn                      = optional(string)
    name                     = optional(string)
    path                     = optional(string, "/")
    permissions_boundary_arn = optional(string)
    managed_policy_arns      = optional(list(string), [])
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
    condition     = var.iam_role.create || var.iam_role.arn != null
    error_message = "iam_role: set arn when create = false."
  }
}

variable "cloudwatch_logs" {
  description = "CloudWatch log group and log levels."
  type = object({
    retention_in_days           = optional(number, 365)
    log_group_class             = optional(string, "STANDARD")
    deletion_protection_enabled = optional(bool, true)
    kms_key_arn                 = optional(string)
    application_log_level       = optional(string, "INFO")
    system_log_level            = optional(string, "INFO")
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["TRACE", "DEBUG", "INFO", "WARN", "ERROR", "FATAL"], var.cloudwatch_logs.application_log_level) && contains(["DEBUG", "INFO", "WARN"], var.cloudwatch_logs.system_log_level)
    error_message = "cloudwatch_logs: invalid log level."
  }
}

variable "tracing" {
  description = "X-Ray tracing mode: Active or PassThrough."
  type        = string
  default     = "Active"
  nullable    = false

  validation {
    condition     = contains(["Active", "PassThrough"], var.tracing)
    error_message = "tracing: Active or PassThrough."
  }
}

variable "lambda_insights" {
  description = "Lambda Insights extension: layer ARN for this Region and architecture."
  type = object({
    enabled   = optional(bool, false)
    layer_arn = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = !var.lambda_insights.enabled || can(regex("^arn:aws[a-z-]*:lambda:[a-z0-9-]+:[0-9]{12}:layer:LambdaInsightsExtension(-Arm64)?:[0-9]+$", var.lambda_insights.layer_arn))
    error_message = "lambda_insights.layer_arn: a LambdaInsightsExtension layer version ARN."
  }
}

variable "layers" {
  description = "Layer ARNs."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "vpc_id" {
  description = "VPC ID; with subnet_ids the function runs in the VPC."
  type        = string
  default     = null
}

variable "subnet_ids" {
  description = "Private subnet IDs. Empty: no VPC."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = length(var.subnet_ids) == 0 || length(distinct(var.subnet_ids)) >= 2
    error_message = "subnet_ids: at least two subnets (Lambda.5)."
  }

  validation {
    condition     = length(var.subnet_ids) == 0 || var.vpc_id != null
    error_message = "subnet_ids needs vpc_id."
  }
}

variable "security_group" {
  description = "Security group in the VPC: egress and extra groups."
  type = object({
    create                        = optional(bool, true)
    egress_cidr_blocks            = optional(list(string), ["0.0.0.0/0"])
    egress_prefix_list_ids        = optional(list(string), [])
    egress_security_group_ids     = optional(list(string), [])
    additional_security_group_ids = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.security_group.create || length(var.security_group.additional_security_group_ids) > 0
    error_message = "security_group: set additional_security_group_ids when create = false."
  }
}

variable "event_sources" {
  description = "Event source mappings by key: SQS, Kinesis or DynamoDB stream ARNs."
  type = map(object({
    arn                                = string
    type                               = string
    batch_size                         = optional(number)
    maximum_batching_window_in_seconds = optional(number, 0)
    maximum_concurrency                = optional(number)
    starting_position                  = optional(string, "LATEST")
    filter_patterns                    = optional(list(string), [])
    on_failure_destination_arn         = optional(string)
    maximum_retry_attempts             = optional(number)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for s in values(var.event_sources) : contains(["sqs", "kinesis", "dynamodb"], s.type)])
    error_message = "event_sources[*].type: sqs, kinesis or dynamodb."
  }
}

variable "allowed_triggers" {
  description = "Services allowed to invoke the alias, by key: principal and source ARN or account."
  type = map(object({
    principal      = string
    source_arn     = optional(string)
    source_account = optional(string)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for t in values(var.allowed_triggers) : t.source_arn != null || t.source_account != null])
    error_message = "allowed_triggers: set source_arn or source_account (Lambda.1)."
  }
}

variable "function_url" {
  description = "Function URL on the alias; IAM auth only."
  type = object({
    enabled     = optional(bool, false)
    invoke_mode = optional(string, "BUFFERED")
    cors = optional(object({
      allow_origins     = list(string)
      allow_methods     = optional(list(string), ["GET"])
      allow_headers     = optional(list(string), [])
      expose_headers    = optional(list(string), [])
      allow_credentials = optional(bool, false)
      max_age           = optional(number, 0)
    }))
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["BUFFERED", "RESPONSE_STREAM"], var.function_url.invoke_mode)
    error_message = "function_url.invoke_mode: BUFFERED or RESPONSE_STREAM."
  }
}

variable "async_invoke" {
  description = "Asynchronous invocation: retries, max event age and destinations."
  type = object({
    enabled                      = optional(bool, false)
    maximum_retry_attempts       = optional(number, 2)
    maximum_event_age_in_seconds = optional(number, 21600)
    on_success_destination_arn   = optional(string)
    on_failure_destination_arn   = optional(string)
  })
  default  = {}
  nullable = false
}

variable "dead_letter_target_arn" {
  description = "SQS queue or SNS topic for failed async events."
  type        = string
  default     = null
}

variable "code_signing_config_arn" {
  description = "Code signing config ARN (Lambda.6)."
  type        = string
  default     = null
}

variable "runtime_update_mode" {
  description = "Runtime updates: Auto, FunctionUpdate or Manual."
  type        = string
  default     = "Auto"
  nullable    = false

  validation {
    condition     = contains(["Auto", "FunctionUpdate", "Manual"], var.runtime_update_mode)
    error_message = "runtime_update_mode: Auto, FunctionUpdate or Manual."
  }
}

variable "durable_execution" {
  description = "Durable execution: execution timeout and retention in seconds."
  type = object({
    enabled           = optional(bool, false)
    execution_timeout = optional(number, 900)
    retention_period  = optional(number)
  })
  default  = {}
  nullable = false
}
