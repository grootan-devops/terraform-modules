locals {
  arn_prefix     = "arn:${module.naming.partition}"
  account_region = "${module.naming.region}:${module.naming.account_id}"
  bus_name       = var.bus.enabled ? module.naming.names.bus : "default"
  bus_arn        = "${local.arn_prefix}:events:${local.account_region}:event-bus/${local.bus_name}"
  own_bus_arn    = var.bus.enabled ? aws_cloudwatch_event_bus.this[0].arn : local.bus_arn
  kms_key_arn    = module.encryption.key_arn
  bus_logging    = var.bus.enabled && var.cloudwatch_logs.enabled
  log_group_name = "/aws/vendedlogs/events/event-bus/${local.bus_name}"
  log_group_arn  = "${local.arn_prefix}:logs:${local.account_region}:log-group:${local.log_group_name}"

  bus_log_types = {
    ERROR = ["ERROR_LOGS"]
    INFO  = ["ERROR_LOGS", "INFO_LOGS"]
    TRACE = ["ERROR_LOGS", "INFO_LOGS", "TRACE_LOGS"]
  }[var.cloudwatch_logs.level]

  log_sources = local.bus_logging ? toset(local.bus_log_types) : toset([])

  targets = merge({}, [
    for rule_key, rule_targets in var.targets : {
      for target_key, target in rule_targets : "${rule_key}/${target_key}" => merge(target, { rule = rule_key, key = target_key })
    }
  ]...)

  schedule_targets = {
    for key, schedule in var.scheduler.schedules : key => merge(schedule.target, {
      arn = schedule.target.type == "event_bus" ? coalesce(schedule.target.arn, local.own_bus_arn) : schedule.target.arn
    })
  }

  schedule_target_arns = {
    for key, t in local.schedule_targets : key => t.type == "batch" ? "${local.arn_prefix}:scheduler:::aws-sdk:batch:submitJob" : t.arn
  }

  schedule_inputs = {
    for key, t in local.schedule_targets : key => t.type != "batch" ? t.input : jsonencode(merge(
      {
        JobName       = coalesce(t.batch.job_name, module.schedule_naming.names["schedule-${key}"])
        JobQueue      = t.arn
        JobDefinition = t.batch.job_definition_arn
      },
      t.batch.array_size == null ? {} : { ArrayProperties = { Size = t.batch.array_size } },
      t.batch.job_attempts == null ? {} : { RetryStrategy = { Attempts = t.batch.job_attempts } }
    ))
  }

  rule_role_types   = ["step_functions", "batch", "ecs", "kinesis", "api_destination", "event_bus"]
  rule_role_targets = { for k, t in local.targets : k => t if contains(local.rule_role_types, t.type) }
  creates_role      = var.iam_role.create && (length(local.rule_role_targets) > 0 || var.scheduler.enabled)
  role_arn          = var.iam_role.create ? try(module.role[0].arn, null) : var.iam_role.arn

  role_users = concat(values(local.rule_role_targets), values(local.schedule_targets))
  by_type    = { for type in ["lambda", "sqs", "step_functions", "batch", "ecs", "kinesis", "api_destination", "event_bus"] : type => [for t in local.role_users : t if t.type == type] }

  job_definitions  = [for t in local.by_type.batch : replace(try(t.batch.job_definition_arn, ""), "/:[0-9]+$/", "")]
  task_definitions = [for t in local.by_type.ecs : replace(try(t.ecs.task_definition_arn, ""), "/:[0-9]+$/", "")]
  pass_role_list   = flatten([for t in local.by_type.ecs : try(t.ecs.pass_role_arns, [])])
  dead_letter_arns = [for t in values(local.schedule_targets) : t.dead_letter_queue.arn if t.dead_letter_queue.enabled]
  queue_key_arns = concat(
    [for t in local.by_type.sqs : t.sqs.kms_key_arn if try(t.sqs.kms_key_arn, null) != null],
    [for t in values(local.schedule_targets) : t.dead_letter_queue.kms_key_arn if t.dead_letter_queue.enabled && t.dead_letter_queue.kms_key_arn != null]
  )

  role_statement_candidates = [
    {
      when = length(local.by_type.lambda) > 0
      statement = {
        Sid      = "InvokeFunctions"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = distinct([for t in local.by_type.lambda : t.arn])
      }
    },
    {
      when = length(local.by_type.sqs) > 0
      statement = {
        Sid      = "SendMessages"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = distinct([for t in local.by_type.sqs : t.arn])
      }
    },
    {
      when = length(local.by_type.step_functions) > 0
      statement = {
        Sid      = "StartExecutions"
        Effect   = "Allow"
        Action   = ["states:StartExecution"]
        Resource = distinct([for t in local.by_type.step_functions : t.arn])
      }
    },
    {
      when = length(local.by_type.batch) > 0
      statement = {
        Sid      = "SubmitJobs"
        Effect   = "Allow"
        Action   = ["batch:SubmitJob"]
        Resource = distinct(concat([for t in local.by_type.batch : t.arn], local.job_definitions, [for d in local.job_definitions : "${d}:*"]))
      }
    },
    {
      when = length(local.by_type.ecs) > 0
      statement = {
        Sid       = "RunTasks"
        Effect    = "Allow"
        Action    = ["ecs:RunTask"]
        Resource  = distinct(concat(local.task_definitions, [for d in local.task_definitions : "${d}:*"]))
        Condition = { ArnEquals = { "ecs:cluster" = distinct([for t in local.by_type.ecs : t.arn]) } }
      }
    },
    {
      when = length(local.by_type.ecs) > 0
      statement = {
        Sid       = "TagTasks"
        Effect    = "Allow"
        Action    = ["ecs:TagResource"]
        Resource  = ["${local.arn_prefix}:ecs:${local.account_region}:task/*"]
        Condition = { StringEquals = { "ecs:CreateAction" = "RunTask" } }
      }
    },
    {
      when = length(local.pass_role_list) > 0
      statement = {
        Sid       = "PassTaskRoles"
        Effect    = "Allow"
        Action    = ["iam:PassRole"]
        Resource  = distinct(local.pass_role_list)
        Condition = { StringLike = { "iam:PassedToService" = "ecs-tasks.${module.naming.dns_suffix}" } }
      }
    },
    {
      when = length(local.by_type.kinesis) > 0
      statement = {
        Sid      = "PutRecords"
        Effect   = "Allow"
        Action   = ["kinesis:PutRecord"]
        Resource = distinct([for t in local.by_type.kinesis : t.arn])
      }
    },
    {
      when = length(local.by_type.kinesis) > 0
      statement = {
        Sid       = "EncryptRecords"
        Effect    = "Allow"
        Action    = ["kms:GenerateDataKey"]
        Resource  = ["*"]
        Condition = { StringEquals = { "kms:ViaService" = "kinesis.${module.naming.region}.${module.naming.dns_suffix}" } }
      }
    },
    {
      when = length(local.by_type.api_destination) > 0
      statement = {
        Sid      = "InvokeApiDestinations"
        Effect   = "Allow"
        Action   = ["events:InvokeApiDestination"]
        Resource = distinct([for t in local.by_type.api_destination : t.arn])
      }
    },
    {
      when = length(local.by_type.event_bus) > 0
      statement = {
        Sid      = "PutEvents"
        Effect   = "Allow"
        Action   = ["events:PutEvents"]
        Resource = distinct([for t in local.by_type.event_bus : t.arn])
      }
    },
    {
      when = length(local.dead_letter_arns) > 0
      statement = {
        Sid      = "SendDeadLetters"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = distinct(local.dead_letter_arns)
      }
    },
    {
      when = length(local.queue_key_arns) > 0
      statement = {
        Sid       = "EncryptMessages"
        Effect    = "Allow"
        Action    = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource  = distinct(local.queue_key_arns)
        Condition = { StringEquals = { "kms:ViaService" = "sqs.${module.naming.region}.${module.naming.dns_suffix}" } }
      }
    },
    {
      when = length(var.scheduler.schedules) > 0 && (var.kms.create || var.kms.key_id != null)
      statement = {
        Sid      = "DecryptSchedulePayloads"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = [local.kms_key_arn]
      }
    }
  ]

  role_statements = [for c in local.role_statement_candidates : c.statement if c.when]

  role_policy_documents = length(local.rule_role_targets) + length(var.scheduler.schedules) > 0 ? [jsonencode({ Version = "2012-10-17", Statement = local.role_statements })] : []

  kms_service_statement_candidates = [
    {
      when = true
      statement = {
        sid        = "AllowEventBridge"
        actions    = ["kms:Decrypt", "kms:GenerateDataKey*", "kms:ReEncrypt*", "kms:DescribeKey"]
        principals = { Service = ["events.${module.naming.dns_suffix}"] }
        conditions = [{ test = "StringEquals", variable = "aws:SourceAccount", values = [module.naming.account_id] }]
      }
    },
    {
      when = local.bus_logging
      statement = {
        sid        = "AllowCloudWatchLogs"
        actions    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
        principals = { Service = ["logs.${module.naming.region}.${module.naming.dns_suffix}"] }
        conditions = [{ test = "ArnLike", variable = "kms:EncryptionContext:aws:logs:arn", values = [local.log_group_arn] }]
      }
    }
  ]

  kms_service_statements = [for c in local.kms_service_statement_candidates : c.statement if c.when]

  log_delivery_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AWSLogDeliveryWrite"
      Effect    = "Allow"
      Principal = { Service = "delivery.logs.${module.naming.dns_suffix}" }
      Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource  = ["${local.log_group_arn}:log-stream:*"]
      Condition = {
        StringEquals = { "aws:SourceAccount" = module.naming.account_id }
        ArnLike      = { "aws:SourceArn" = "${local.arn_prefix}:logs:${local.account_region}:*" }
      }
    }]
  })
}
