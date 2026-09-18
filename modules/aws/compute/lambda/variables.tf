variable "name" {
  description = "Name of the Lambda function"
  type        = string
  default     = null
}

variable "application" {
  description = "Name of the product"
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

variable "durable_config" {
  description = "Configuration for durable execution (if applicable in this provider)."
  type = object({
    execution_timeout = number
    retention_period  = number
  })
  default = null
}


variable "architectures" {
  description = "Instruction set architecture for your Lambda function. Valid values are [\"x86_64\"] and [\"arm64\"]."
  type        = list(string)
  default     = ["x86_64"]

  validation {
    condition = (
      length(var.architectures) == 1 &&
      contains(["x86_64", "arm64"], var.architectures[0])
    )
    error_message = "architectures must contain exactly one value: x86_64 or arm64."
  }
}

variable "package_type" {
  description = "Lambda deployment package type. Valid values are Zip and Image."
  type        = string
  default     = "Zip"
  validation {
    condition     = contains(["Zip", "Image"], var.package_type)
    error_message = "package_type must be Zip or Image."
  }
}

variable "image_uri" {
  description = "URI of a container image in the ECR registry when package_type is Image."
  type        = string
  default     = null
}

variable "runtime" {
  description = "Identifier of the function runtime (Node.js 22.x or Python 3.12 LTS)."
  type        = string
  default     = null
  validation {
    condition     = var.package_type == "Image" || try(contains(["nodejs22.x", "python3.12"], var.runtime), false)
    error_message = "Runtime must be nodejs22.x or python3.12 when package_type is Zip."
  }
}

variable "handler" {
  description = "Function entrypoint in your code. Defaults to the generated bootstrap handler for the selected runtime."
  type        = string
  default     = null
}

variable "bootstrap_message" {
  description = "Message returned by the generated bootstrap package when filename and S3 package inputs are omitted."
  type        = string
  default     = "Code not deployed"
}

variable "memory_size" {
  description = "Amount of memory in MB your Lambda Function can use at runtime."
  type        = number
  default     = 128
}

variable "timeout" {
  description = "Amount of time your Lambda Function has to run in seconds."
  type        = number
  default     = 60
}

variable "reserved_concurrent_executions" {
  description = "Amount of reserved concurrent executions for this lambda function. A value of 0 disables lambda from being triggered and -1 removes any concurrency limitations."
  type        = number
  default     = -1
}

variable "provisioned_concurrency" {
  description = "Provisioned concurrency allocated to the stable Lambda alias. Null disables provisioned concurrency."
  type        = number
  default     = null

  validation {
    condition     = try(var.provisioned_concurrency == null || var.provisioned_concurrency >= 1, true)
    error_message = "provisioned_concurrency must be null or at least 1."
  }
}

variable "alias_name" {
  description = "Stable alias used by API Gateway and other synchronous consumers."
  type        = string
  default     = "live"
}

variable "environment_variables" {
  description = "A map that defines environment variables for the Lambda function."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "A map of tags to assign to resources."
  type        = map(string)
  default     = {}
}

variable "vpc_config" {
  description = "VPC configuration for the Lambda function"
  type = object({
    subnet_ids         = list(string)
    security_group_ids = list(string)
  })
  default = null
}

variable "tracing_config_mode" {
  description = "Tracing mode for X-Ray. Valid values are Active and PassThrough."
  type        = string
  default     = "PassThrough"
}

variable "kms_key_arn" {
  description = "KMS Key ARN used to encrypt environment variables at rest and CloudWatch logs. Strictly required."
  type        = string
}

variable "secret_arns" {
  description = "Secrets Manager secret ARNs the function execution role is allowed to read"
  type        = list(string)
  default     = []
}

variable "source_kms_key_arn" {
  description = "KMS key ARN used for Lambda snap start, filtering, etc."
  type        = string
  default     = null
}

variable "s3_bucket" {
  description = "S3 bucket location containing the function's deployment package."
  type        = string
  default     = null
}

variable "s3_key" {
  description = "S3 key of an object containing the function's deployment package."
  type        = string
  default     = null
}

variable "filename" {
  description = "Path to the function's deployment package within the local filesystem. Overridden by s3_bucket/s3_key if provided."
  type        = string
  default     = null
}

variable "dead_letter_config_target_arn" {
  description = "ARN of an SNS topic or SQS queue to notify when an invocation fails."
  type        = string
  default     = null
}

variable "sqs_event_sources" {
  description = "Map of SQS ARNs to their respective mapping configurations (e.g., batch_size, filter_criteria_pattern)"
  type = map(object({
    arn                     = string
    batch_size              = optional(number, 10)
    maximum_concurrency     = optional(number, 2)
    filter_criteria_pattern = optional(string, null)
    kms_key_arn             = optional(string, null)
  }))
  default = {}
}

variable "async_invoke_config" {
  description = "Configuration for async invocation behavior and destinations."
  type = object({
    maximum_event_age_in_seconds = optional(number, 21600)
    maximum_retry_attempts       = optional(number, 2)
    on_success_destination_arn   = optional(string, null)
    on_failure_destination_arn   = optional(string, null)
  })
  default = null
}

variable "cloudwatch_logs" {
  description = "CloudWatch Logs configuration for the Lambda log group."

  type = object({
    retention_in_days           = optional(number, 14)
    kms_key_id                  = optional(string, null)
    deletion_protection_enabled = optional(bool, true)
  })

  default = {}
}

variable "additional_layers" {
  description = "Lambda layer version ARNs to attach to the function."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.additional_layers) <= 5
    error_message = "A Lambda function can use at most five layers."
  }
}

variable "custom_iam_policies" {
  description = "List of IAM policy ARNs to attach to the Lambda Execution Role."
  type        = list(string)
  default     = []
}

variable "create_deployer_role" {
  description = "Whether to create a least-privilege role for external Lambda code deployments."
  type        = bool
  default     = false
}

variable "deployer_role_name" {
  description = "Optional name for the Lambda deployer role and policy."
  type        = string
  default     = null
}

variable "deployer_principal_arn_patterns" {
  description = "IAM principal ARN patterns allowed to assume the Lambda deployer role."
  type        = list(string)
  default     = []
}

variable "artifact_bucket_arn" {
  description = "ARN of the S3 bucket used by external Lambda deployments."
  type        = string
  default     = null
}

variable "artifact_prefix" {
  description = "S3 object prefix used by external Lambda deployments. Defaults to the Lambda service name."
  type        = string
  default     = null
}

variable "runtime_management_config" {
  description = "Runtime management configuration for the Lambda function. Valid values are Auto and FunctionUpdate."
  type        = string
  default     = "Auto"

  validation {
    condition     = contains(["Auto", "FunctionUpdate"], var.runtime_management_config)
    error_message = "runtime_management_config must be either Auto or FunctionUpdate."
  }
}

variable "enable_application_signals" {
  description = "Enable CloudWatch Application Signals."
  type        = bool
  default     = false
}

variable "enable_lambda_insights" {
  description = "Enable CloudWatch Lambda Insights."
  type        = bool
  default     = false
}

variable "bootstrap_status_code" {
  description = "HTTP status code returned by the bootstrap placeholder handler before actual application code is deployed."
  type        = number
  default     = 200
}
