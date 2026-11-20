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
  description = "Instance name."
  type        = string
  default     = null

  validation {
    condition     = var.name == null || can(regex("^[a-z0-9][a-z0-9-]{0,31}$", var.name))
    error_message = "name: 1-32 chars, a-z 0-9 -."
  }
}

variable "tags" {
  description = "Extra tags; governance tags win."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "bus" {
  description = "Custom event bus; disabled: the default bus."
  type = object({
    enabled     = optional(bool, true)
    description = optional(string)
  })
  default  = {}
  nullable = false
}

variable "kms" {
  description = "Bus, archive and schedule encryption: {} AWS owned key, create = true module key, key_id your key (ARN or ID)."
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

variable "cloudwatch_logs" {
  description = "Bus logs to CloudWatch (custom bus only): level and log group."
  type = object({
    enabled                     = optional(bool, true)
    level                       = optional(string, "ERROR")
    include_detail              = optional(string, "NONE")
    retention_in_days           = optional(number, 365)
    log_group_class             = optional(string, "STANDARD")
    deletion_protection_enabled = optional(bool, true)
    kms_key_arn                 = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["ERROR", "INFO", "TRACE"], var.cloudwatch_logs.level) && contains(["NONE", "FULL"], var.cloudwatch_logs.include_detail)
    error_message = "cloudwatch_logs: level ERROR, INFO or TRACE; include_detail NONE or FULL."
  }
}

variable "archive" {
  description = "Event archive on the bus."
  type = object({
    enabled        = optional(bool, false)
    retention_days = optional(number, 365)
    event_pattern  = optional(string)
    description    = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.archive.retention_days >= 1
    error_message = "archive.retention_days: 1 or more."
  }
}

variable "rules" {
  description = "Event pattern rules by key."
  type = map(object({
    description   = optional(string)
    event_pattern = string
    state         = optional(string, "ENABLED")
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k in keys(var.rules) : can(regex("^[a-z0-9][a-z0-9-]{0,31}$", k))])
    error_message = "rules: keys 1-32 chars, a-z 0-9 -."
  }

  validation {
    condition     = alltrue([for r in values(var.rules) : can(keys(jsondecode(r.event_pattern)))])
    error_message = "rules[*].event_pattern: a JSON object."
  }

  validation {
    condition     = alltrue([for r in values(var.rules) : contains(["ENABLED", "DISABLED", "ENABLED_WITH_ALL_CLOUDTRAIL_MANAGEMENT_EVENTS"], r.state)])
    error_message = "rules[*].state: ENABLED, DISABLED or ENABLED_WITH_ALL_CLOUDTRAIL_MANAGEMENT_EVENTS."
  }
}

variable "targets" {
  description = "Targets by rule key, then target key."
  type = map(map(object({
    type       = string
    arn        = optional(string)
    input      = optional(string)
    input_path = optional(string)
    input_transformer = optional(object({
      input_paths    = optional(map(string), {})
      input_template = string
    }))
    dead_letter_queue = optional(object({
      enabled     = optional(bool, true)
      arn         = optional(string)
      kms_key_arn = optional(string)
    }), {})
    retry_policy = optional(object({
      maximum_event_age_in_seconds = optional(number, 86400)
      maximum_retry_attempts       = optional(number, 185)
    }), {})
    sqs = optional(object({
      message_group_id = optional(string)
      kms_key_arn      = optional(string)
    }))
    kinesis = optional(object({
      partition_key_path = optional(string)
      partition_key      = optional(string)
    }))
    batch = optional(object({
      job_definition_arn = string
      job_name           = optional(string)
      array_size         = optional(number)
      job_attempts       = optional(number)
    }))
    ecs = optional(object({
      task_definition_arn     = string
      pass_role_arns          = optional(list(string), [])
      task_count              = optional(number, 1)
      launch_type             = optional(string, "FARGATE")
      platform_version        = optional(string)
      subnet_ids              = optional(list(string), [])
      security_group_ids      = optional(list(string), [])
      assign_public_ip        = optional(bool, false)
      propagate_tags          = optional(string, "TASK_DEFINITION")
      enable_ecs_managed_tags = optional(bool, true)
      enable_execute_command  = optional(bool, false)
    }))
    event_bus = optional(object({
      detail_type = string
      source      = string
    }))
    http = optional(object({
      header_parameters       = optional(map(string), {})
      query_string_parameters = optional(map(string), {})
      path_parameter_values   = optional(list(string), [])
    }))
  })))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k in keys(var.targets) : contains(keys(var.rules), k)])
    error_message = "targets: keys must be rule keys."
  }

  validation {
    condition     = alltrue(flatten([for ts in values(var.targets) : [for k in keys(ts) : can(regex("^[a-zA-Z0-9._-]{1,64}$", k))]]))
    error_message = "targets[*]: keys 1-64 chars, a-z A-Z 0-9 . _ -."
  }

  validation {
    condition     = alltrue(flatten([for ts in values(var.targets) : [for t in values(ts) : contains(["lambda", "sqs", "step_functions", "batch", "ecs", "kinesis", "api_destination", "event_bus"], t.type)]]))
    error_message = "targets[*][*].type: lambda, sqs, step_functions, batch, ecs, kinesis, api_destination or event_bus."
  }

  validation {
    condition     = alltrue(flatten([for ts in values(var.targets) : [for t in values(ts) : t.arn != null]]))
    error_message = "targets[*][*].arn: required."
  }

  validation {
    condition     = alltrue(flatten([for ts in values(var.targets) : [for t in values(ts) : (t.type != "batch" || t.batch != null) && (t.type != "ecs" || t.ecs != null)]]))
    error_message = "targets: batch and ecs targets need their block."
  }

  validation {
    condition     = alltrue(flatten([for ts in values(var.targets) : [for t in values(ts) : t.event_bus == null && try(t.kinesis.partition_key, null) == null && try(t.sqs.kms_key_arn, null) == null && t.dead_letter_queue.kms_key_arn == null]]))
    error_message = "targets[*][*]: event_bus, kinesis.partition_key and kms_key_arn are for schedules."
  }

  validation {
    condition     = alltrue(flatten([for ts in values(var.targets) : [for t in values(ts) : !t.dead_letter_queue.enabled || t.dead_letter_queue.arn != null]]))
    error_message = "targets[*][*].dead_letter_queue: set arn or enabled = false."
  }

  validation {
    condition     = alltrue(flatten([for ts in values(var.targets) : [for t in values(ts) : t.retry_policy.maximum_event_age_in_seconds >= 60 && t.retry_policy.maximum_event_age_in_seconds <= 86400 && t.retry_policy.maximum_retry_attempts >= 0 && t.retry_policy.maximum_retry_attempts <= 185]]))
    error_message = "targets[*][*].retry_policy: event age 60-86400, attempts 0-185."
  }

  validation {
    condition     = alltrue(flatten([for ts in values(var.targets) : [for t in values(ts) : t.ecs == null || (contains(["FARGATE", "EC2", "EXTERNAL"], try(t.ecs.launch_type, "")) && (try(t.ecs.launch_type, "") != "FARGATE" || length(try(t.ecs.subnet_ids, [])) > 0))]]))
    error_message = "targets[*][*].ecs: launch_type FARGATE, EC2 or EXTERNAL; FARGATE needs subnet_ids."
  }
}

variable "scheduler" {
  description = "EventBridge Scheduler: schedule group and schedules by key."
  type = object({
    enabled = optional(bool, false)
    schedules = optional(map(object({
      description             = optional(string)
      expression              = string
      timezone                = optional(string, "UTC")
      start_date              = optional(string)
      end_date                = optional(string)
      state                   = optional(string, "ENABLED")
      flexible_window_minutes = optional(number)
      action_after_completion = optional(string, "NONE")
      target = object({
        type       = string
        arn        = optional(string)
        input      = optional(string)
        input_path = optional(string)
        input_transformer = optional(object({
          input_paths    = optional(map(string), {})
          input_template = string
        }))
        dead_letter_queue = optional(object({
          enabled     = optional(bool, true)
          arn         = optional(string)
          kms_key_arn = optional(string)
        }), {})
        retry_policy = optional(object({
          maximum_event_age_in_seconds = optional(number, 86400)
          maximum_retry_attempts       = optional(number, 185)
        }), {})
        sqs = optional(object({
          message_group_id = optional(string)
          kms_key_arn      = optional(string)
        }))
        kinesis = optional(object({
          partition_key_path = optional(string)
          partition_key      = optional(string)
        }))
        batch = optional(object({
          job_definition_arn = string
          job_name           = optional(string)
          array_size         = optional(number)
          job_attempts       = optional(number)
        }))
        ecs = optional(object({
          task_definition_arn     = string
          pass_role_arns          = optional(list(string), [])
          task_count              = optional(number, 1)
          launch_type             = optional(string, "FARGATE")
          platform_version        = optional(string)
          subnet_ids              = optional(list(string), [])
          security_group_ids      = optional(list(string), [])
          assign_public_ip        = optional(bool, false)
          propagate_tags          = optional(string, "TASK_DEFINITION")
          enable_ecs_managed_tags = optional(bool, true)
          enable_execute_command  = optional(bool, false)
        }))
        event_bus = optional(object({
          detail_type = string
          source      = string
        }))
        http = optional(object({
          header_parameters       = optional(map(string), {})
          query_string_parameters = optional(map(string), {})
          path_parameter_values   = optional(list(string), [])
        }))
      })
    })), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.scheduler.enabled || length(var.scheduler.schedules) == 0
    error_message = "scheduler: schedules need enabled = true."
  }

  validation {
    condition     = alltrue([for k in keys(var.scheduler.schedules) : can(regex("^[a-z0-9][a-z0-9-]{0,31}$", k))])
    error_message = "scheduler.schedules: keys 1-32 chars, a-z 0-9 -."
  }

  validation {
    condition     = alltrue([for s in values(var.scheduler.schedules) : can(regex("^(cron|rate|at)\\(.+\\)$", s.expression))])
    error_message = "scheduler.schedules[*].expression: cron(...), rate(...) or at(...)."
  }

  validation {
    condition     = alltrue([for s in values(var.scheduler.schedules) : contains(["ENABLED", "DISABLED"], s.state) && contains(["NONE", "DELETE"], s.action_after_completion)])
    error_message = "scheduler.schedules[*]: state ENABLED or DISABLED; action_after_completion NONE or DELETE."
  }

  validation {
    condition     = alltrue([for s in values(var.scheduler.schedules) : s.flexible_window_minutes == null || (s.flexible_window_minutes >= 1 && s.flexible_window_minutes <= 1440)])
    error_message = "scheduler.schedules[*].flexible_window_minutes: 1-1440."
  }

  validation {
    condition     = alltrue([for s in values(var.scheduler.schedules) : contains(["lambda", "sqs", "step_functions", "ecs", "kinesis", "batch", "event_bus"], s.target.type)])
    error_message = "scheduler.schedules[*].target.type: lambda, sqs, step_functions, ecs, kinesis, batch or event_bus."
  }

  validation {
    condition     = alltrue([for s in values(var.scheduler.schedules) : s.target.arn != null || (s.target.type == "event_bus" && var.bus.enabled)])
    error_message = "scheduler.schedules[*].target.arn: required; event_bus defaults to the custom bus."
  }

  validation {
    condition     = alltrue([for s in values(var.scheduler.schedules) : s.target.input_path == null && s.target.input_transformer == null && s.target.http == null && try(s.target.kinesis.partition_key_path, null) == null && (s.target.type != "batch" || s.target.input == null)])
    error_message = "scheduler.schedules[*].target: no input_path, input_transformer, http or kinesis.partition_key_path; batch takes no input."
  }

  validation {
    condition     = alltrue([for s in values(var.scheduler.schedules) : (s.target.type != "batch" || s.target.batch != null) && (s.target.type != "ecs" || s.target.ecs != null) && (s.target.type != "event_bus" || s.target.event_bus != null) && (s.target.type != "kinesis" || try(s.target.kinesis.partition_key, null) != null)])
    error_message = "scheduler.schedules[*].target: batch, ecs and event_bus need their block; kinesis needs kinesis.partition_key."
  }

  validation {
    condition     = alltrue([for s in values(var.scheduler.schedules) : !s.target.dead_letter_queue.enabled || s.target.dead_letter_queue.arn != null])
    error_message = "scheduler.schedules[*].target.dead_letter_queue: set arn or enabled = false."
  }

  validation {
    condition     = alltrue([for s in values(var.scheduler.schedules) : s.target.retry_policy.maximum_event_age_in_seconds >= 60 && s.target.retry_policy.maximum_event_age_in_seconds <= 86400 && s.target.retry_policy.maximum_retry_attempts >= 0 && s.target.retry_policy.maximum_retry_attempts <= 185])
    error_message = "scheduler.schedules[*].target.retry_policy: event age 60-86400, attempts 0-185."
  }

  validation {
    condition     = alltrue([for s in values(var.scheduler.schedules) : s.target.ecs == null || (contains(["FARGATE", "EC2", "EXTERNAL"], try(s.target.ecs.launch_type, "")) && (try(s.target.ecs.launch_type, "") != "FARGATE" || length(try(s.target.ecs.subnet_ids, [])) > 0))])
    error_message = "scheduler.schedules[*].target.ecs: launch_type FARGATE, EC2 or EXTERNAL; FARGATE needs subnet_ids."
  }
}

variable "iam_role" {
  description = "Target role: extend it or bring your own."
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

variable "policy_statements" {
  description = "Bus policy statements; resources default to the bus."
  type = list(object({
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
  }))
  default  = []
  nullable = false
}

variable "alarms" {
  description = "Built-in CloudWatch alarms: switch, topics by severity, per-alarm overrides."
  type = object({
    enabled    = optional(bool, true)
    topic_arns = optional(map(string), {})
    overrides = optional(object({
      rules = optional(object({
        failed_invocations        = optional(object({ enabled = optional(bool), threshold = optional(number), evaluation_periods = optional(number), datapoints_to_alarm = optional(number), period = optional(number), severity = optional(string) }), {})
        throttled_rules           = optional(object({ enabled = optional(bool), threshold = optional(number), evaluation_periods = optional(number), datapoints_to_alarm = optional(number), period = optional(number), severity = optional(string) }), {})
        invocations_failed_to_dlq = optional(object({ enabled = optional(bool), threshold = optional(number), evaluation_periods = optional(number), datapoints_to_alarm = optional(number), period = optional(number), severity = optional(string) }), {})
      }), {})
      schedules = optional(object({
        target_errors             = optional(object({ enabled = optional(bool), threshold = optional(number), evaluation_periods = optional(number), datapoints_to_alarm = optional(number), period = optional(number), severity = optional(string) }), {})
        invocations_dropped       = optional(object({ enabled = optional(bool), threshold = optional(number), evaluation_periods = optional(number), datapoints_to_alarm = optional(number), period = optional(number), severity = optional(string) }), {})
        invocations_failed_to_dlq = optional(object({ enabled = optional(bool), threshold = optional(number), evaluation_periods = optional(number), datapoints_to_alarm = optional(number), period = optional(number), severity = optional(string) }), {})
      }), {})
    }), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for s, arn in var.alarms.topic_arns : can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]+$", arn))])
    error_message = "alarms.topic_arns: SNS topic ARNs by severity."
  }
}
