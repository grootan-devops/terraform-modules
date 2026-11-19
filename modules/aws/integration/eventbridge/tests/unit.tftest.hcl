mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "eu-west-1"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/core-prod-events-eu-west-1"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    }
  }

  mock_resource "aws_cloudwatch_event_bus" {
    defaults = {
      arn = "arn:aws:events:eu-west-1:123456789012:event-bus/core-prod"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-west-1:123456789012:log-group:/aws/vendedlogs/events/event-bus/core-prod"
    }
  }

  mock_resource "aws_cloudwatch_log_delivery_destination" {
    defaults = {
      arn = "arn:aws:logs:eu-west-1:123456789012:delivery-destination:core-prod-logs"
    }
  }

  mock_resource "aws_scheduler_schedule_group" {
    defaults = {
      arn = "arn:aws:scheduler:eu-west-1:123456789012:schedule-group/core-prod"
    }
  }

  mock_resource "aws_scheduler_schedule" {
    defaults = {
      arn = "arn:aws:scheduler:eu-west-1:123456789012:schedule/core-prod/schedule"
    }
  }
}

variables {
  application = "core"
  environment = "prod"
  tags        = { Team = "payments" }
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = aws_cloudwatch_event_bus.this[0].name == "core-prod" && aws_cloudwatch_event_bus.this[0].kms_key_identifier == null && output.kms_key_arn == null
    error_message = "A custom bus <application>-<environment> with the AWS owned key by default."
  }

  assert {
    condition     = aws_cloudwatch_event_bus.this[0].log_config[0].level == "ERROR" && aws_cloudwatch_event_bus.this[0].log_config[0].include_detail == "NONE"
    error_message = "Bus logging is on at ERROR without event detail."
  }

  assert {
    condition     = module.log_group[0].name == "/aws/vendedlogs/events/event-bus/core-prod" && module.log_group[0].retention_in_days == 365 && module.log_group[0].kms_key_arn == null
    error_message = "Bus logs go to /aws/vendedlogs/events/event-bus/<bus>, 365 days."
  }

  assert {
    condition     = keys(aws_cloudwatch_log_delivery_source.this) == ["ERROR_LOGS"] && length(aws_cloudwatch_log_delivery.error) == 1 && length(aws_cloudwatch_log_delivery.info) + length(aws_cloudwatch_log_delivery.trace) == 0 && aws_cloudwatch_log_delivery_source.this["ERROR_LOGS"].name == "core-prod-error-logs"
    error_message = "ERROR level delivers only error logs."
  }

  assert {
    condition     = length(module.role) + length(aws_cloudwatch_event_archive.this) + length(aws_cloudwatch_event_bus_policy.this) + length(aws_cloudwatch_event_rule.this) == 0 && output.role_arn == null
    error_message = "No role, archive, bus policy or rule by default."
  }

  assert {
    condition     = length(aws_scheduler_schedule_group.this) + length(aws_scheduler_schedule.this) == 0 && output.schedule_group_name == null && output.schedule_group_arn == null && output.schedule_arns == {}
    error_message = "The scheduler is off by default: no group and no schedules."
  }

  assert {
    condition     = aws_cloudwatch_event_bus.this[0].tags["Name"] == "core-prod" && aws_cloudwatch_event_bus.this[0].tags["Team"] == "payments" && aws_cloudwatch_event_bus.this[0].tags["ManagedBy"] == "Terraform"
    error_message = "Caller and governance tags must be applied (EventBridge.2)."
  }
}

run "log_delivery_policy" {
  command = apply

  assert {
    condition     = length(jsondecode(aws_cloudwatch_log_resource_policy.this[0].policy_document).Statement) == 1 && jsondecode(aws_cloudwatch_log_resource_policy.this[0].policy_document).Statement[0].Principal.Service == "delivery.logs.amazonaws.com" && aws_cloudwatch_log_resource_policy.this[0].policy_name == "core-prod-log-delivery"
    error_message = "The log resource policy grants only log delivery."
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_log_resource_policy.this[0].policy_document).Statement[0].Resource == ["arn:aws:logs:eu-west-1:123456789012:log-group:/aws/vendedlogs/events/event-bus/core-prod:log-stream:*"] && jsondecode(aws_cloudwatch_log_resource_policy.this[0].policy_document).Statement[0].Condition.StringEquals["aws:SourceAccount"] == "123456789012"
    error_message = "Log delivery is limited to the bus log group and this account."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.this["ERROR_LOGS"].resource_arn == "arn:aws:events:eu-west-1:123456789012:event-bus/core-prod" && aws_cloudwatch_log_delivery_destination.this[0].delivery_destination_configuration[0].destination_resource_arn == output.log_group_arn
    error_message = "The bus must deliver to the module log group."
  }
}

run "named_instance" {
  command   = plan
  state_key = "named"

  variables {
    name            = "orders"
    cloudwatch_logs = { level = "TRACE", include_detail = "FULL" }
  }

  assert {
    condition     = aws_cloudwatch_event_bus.this[0].name == "core-prod-orders" && module.log_group[0].name == "/aws/vendedlogs/events/event-bus/core-prod-orders"
    error_message = "name is appended to the bus name."
  }

  assert {
    condition     = length(aws_cloudwatch_log_delivery_source.this) == 3 && length(aws_cloudwatch_log_delivery.info) == 1 && length(aws_cloudwatch_log_delivery.trace) == 1 && aws_cloudwatch_event_bus.this[0].log_config[0].include_detail == "FULL"
    error_message = "TRACE level delivers error, info and trace logs."
  }
}

run "rules_and_targets" {
  command = apply

  variables {
    rules = {
      orders = { event_pattern = "{\"source\":[\"core.orders\"]}" }
      jobs   = { event_pattern = "{\"source\":[\"core.jobs\"]}" }
    }
    targets = {
      orders = {
        worker = { type = "lambda", arn = "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-worker:live", dead_letter_queue = { arn = "arn:aws:sqs:eu-west-1:123456789012:core-prod-events-dlq" } }
        queue  = { type = "sqs", arn = "arn:aws:sqs:eu-west-1:123456789012:core-prod-orders.fifo", sqs = { message_group_id = "orders" }, dead_letter_queue = { enabled = false } }
        flow   = { type = "step_functions", arn = "arn:aws:states:eu-west-1:123456789012:stateMachine:core-prod-flow", dead_letter_queue = { enabled = false }, retry_policy = { maximum_retry_attempts = 3, maximum_event_age_in_seconds = 3600 } }
        stream = { type = "kinesis", arn = "arn:aws:kinesis:eu-west-1:123456789012:stream/core-prod-clicks", kinesis = { partition_key_path = "$.id" }, dead_letter_queue = { enabled = false } }
      }
      jobs = {
        job = { type = "batch", arn = "arn:aws:batch:eu-west-1:123456789012:job-queue/core-prod", batch = { job_definition_arn = "arn:aws:batch:eu-west-1:123456789012:job-definition/core-prod-report:3" }, dead_letter_queue = { enabled = false } }
        task = {
          type              = "ecs"
          arn               = "arn:aws:ecs:eu-west-1:123456789012:cluster/core-prod"
          dead_letter_queue = { enabled = false }
          ecs = {
            task_definition_arn = "arn:aws:ecs:eu-west-1:123456789012:task-definition/core-prod-sync:7"
            pass_role_arns      = ["arn:aws:iam::123456789012:role/core-prod-sync-task", "arn:aws:iam::123456789012:role/core-prod-sync-exec"]
            subnet_ids          = ["subnet-0123456789abcdef0"]
            security_group_ids  = ["sg-0aaaaaaaaaaaaaaaa"]
          }
        }
        hook    = { type = "api_destination", arn = "arn:aws:events:eu-west-1:123456789012:api-destination/core-prod-hook/abcd", http = { header_parameters = { X-Source = "events" } }, dead_letter_queue = { enabled = false } }
        forward = { type = "event_bus", arn = "arn:aws:events:eu-west-1:210987654321:event-bus/audit", dead_letter_queue = { enabled = false } }
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_event_rule.this["orders"].name == "core-prod-orders" && aws_cloudwatch_event_rule.this["orders"].event_bus_name == "core-prod" && aws_cloudwatch_event_rule.this["jobs"].event_bus_name == "core-prod"
    error_message = "Rules go on the custom bus."
  }

  assert {
    condition     = aws_cloudwatch_event_rule.this["orders"].schedule_expression == null && aws_cloudwatch_event_rule.this["orders"].event_pattern == "{\"source\":[\"core.orders\"]}"
    error_message = "Rules are event-pattern only."
  }

  assert {
    condition     = output.rule_names == { orders = "core-prod-orders", jobs = "core-prod-jobs" } && length(output.rule_arns) == 2 && output.rule_bus_names == { orders = "core-prod", jobs = "core-prod" }
    error_message = "Rule names, ARNs and bus names are exported by key."
  }

  assert {
    condition     = aws_cloudwatch_event_target.this["orders/worker"].role_arn == null && aws_cloudwatch_event_target.this["orders/worker"].dead_letter_config[0].arn == "arn:aws:sqs:eu-west-1:123456789012:core-prod-events-dlq" && aws_cloudwatch_event_target.this["orders/worker"].retry_policy[0].maximum_retry_attempts == 185
    error_message = "Lambda targets use no role and keep their DLQ and default retries."
  }

  assert {
    condition     = aws_cloudwatch_event_target.this["orders/queue"].sqs_target[0].message_group_id == "orders" && length(aws_cloudwatch_event_target.this["orders/queue"].dead_letter_config) == 0 && aws_cloudwatch_event_target.this["orders/queue"].role_arn == null
    error_message = "SQS targets use no role; dead_letter_queue.enabled = false removes the DLQ."
  }

  assert {
    condition     = aws_cloudwatch_event_target.this["orders/flow"].role_arn == "arn:aws:iam::123456789012:role/core-prod-events-eu-west-1" && aws_cloudwatch_event_target.this["orders/flow"].retry_policy[0].maximum_event_age_in_seconds == 3600 && output.role_arn == aws_cloudwatch_event_target.this["orders/flow"].role_arn
    error_message = "Role targets use the module role and their retry policy."
  }

  assert {
    condition     = aws_cloudwatch_event_target.this["orders/stream"].kinesis_target[0].partition_key_path == "$.id"
    error_message = "Kinesis rule targets take the partition key path."
  }

  assert {
    condition     = aws_cloudwatch_event_target.this["jobs/job"].batch_target[0].job_name == "core-prod-jobs-job" && aws_cloudwatch_event_target.this["jobs/task"].ecs_target[0].launch_type == "FARGATE" && !aws_cloudwatch_event_target.this["jobs/task"].ecs_target[0].network_configuration[0].assign_public_ip && aws_cloudwatch_event_target.this["jobs/hook"].http_target[0].header_parameters["X-Source"] == "events"
    error_message = "Batch, ECS and API destination settings must apply."
  }

  assert {
    condition     = aws_cloudwatch_event_target.this["jobs/forward"].arn == "arn:aws:events:eu-west-1:210987654321:event-bus/audit" && aws_cloudwatch_event_target.this["jobs/forward"].role_arn == output.role_arn
    error_message = "Event bus targets forward with the module role."
  }

  assert {
    condition     = jsondecode(module.role[0].trust_policy_json).Statement[0].Principal.Service == ["events.amazonaws.com", "scheduler.amazonaws.com"] && jsondecode(module.role[0].trust_policy_json).Statement[0].Condition.StringEquals["aws:SourceAccount"] == ["123456789012"] && module.role[0].name == "core-prod-events-eu-west-1"
    error_message = "Only EventBridge and EventBridge Scheduler in this account may assume the target role."
  }

  assert {
    condition     = [for s in jsondecode(module.role[0].policy_json).Statement : s.Sid] == ["StartExecutions", "SubmitJobs", "RunTasks", "TagTasks", "PassTaskRoles", "PutRecords", "EncryptRecords", "InvokeApiDestinations", "PutEvents"]
    error_message = "The role must get exactly the statements its targets need."
  }

  assert {
    condition     = jsondecode(module.role[0].policy_json).Statement[0].Action == ["states:StartExecution"] && jsondecode(module.role[0].policy_json).Statement[0].Resource == ["arn:aws:states:eu-west-1:123456789012:stateMachine:core-prod-flow"]
    error_message = "states:StartExecution only on the target state machine."
  }

  assert {
    condition     = jsondecode(module.role[0].policy_json).Statement[1].Resource == ["arn:aws:batch:eu-west-1:123456789012:job-queue/core-prod", "arn:aws:batch:eu-west-1:123456789012:job-definition/core-prod-report", "arn:aws:batch:eu-west-1:123456789012:job-definition/core-prod-report:*"]
    error_message = "batch:SubmitJob only on the job queue and job definition."
  }

  assert {
    condition     = jsondecode(module.role[0].policy_json).Statement[2].Resource == ["arn:aws:ecs:eu-west-1:123456789012:task-definition/core-prod-sync", "arn:aws:ecs:eu-west-1:123456789012:task-definition/core-prod-sync:*"] && jsondecode(module.role[0].policy_json).Statement[2].Condition.ArnEquals["ecs:cluster"] == ["arn:aws:ecs:eu-west-1:123456789012:cluster/core-prod"]
    error_message = "ecs:RunTask only for the task definition on the target cluster."
  }

  assert {
    condition     = jsondecode(module.role[0].policy_json).Statement[4].Resource == ["arn:aws:iam::123456789012:role/core-prod-sync-task", "arn:aws:iam::123456789012:role/core-prod-sync-exec"] && jsondecode(module.role[0].policy_json).Statement[4].Condition.StringLike["iam:PassedToService"] == "ecs-tasks.amazonaws.com"
    error_message = "iam:PassRole only for the task roles, only to ECS tasks."
  }

  assert {
    condition     = jsondecode(module.role[0].policy_json).Statement[5].Action == ["kinesis:PutRecord"] && jsondecode(module.role[0].policy_json).Statement[7].Action == ["events:InvokeApiDestination"]
    error_message = "Kinesis and API destination targets get only their own action."
  }

  assert {
    condition     = jsondecode(module.role[0].policy_json).Statement[8].Action == ["events:PutEvents"] && jsondecode(module.role[0].policy_json).Statement[8].Resource == ["arn:aws:events:eu-west-1:210987654321:event-bus/audit"]
    error_message = "events:PutEvents only on the target bus."
  }
}

run "scheduler_targets" {
  command   = apply
  state_key = "scheduler"

  variables {
    scheduler = {
      enabled = true
      schedules = {
        report = {
          description = "Nightly report."
          expression  = "cron(0 2 * * ? *)"
          target = {
            type              = "lambda"
            arn               = "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-report:live"
            dead_letter_queue = { arn = "arn:aws:sqs:eu-west-1:123456789012:core-prod-events-dlq", kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/aaaaaaaa-2222-3333-4444-555555555555" }
          }
        }
        enqueue = {
          expression              = "rate(5 minutes)"
          timezone                = "Europe/Dublin"
          flexible_window_minutes = 15
          target = {
            type              = "sqs"
            arn               = "arn:aws:sqs:eu-west-1:123456789012:core-prod-ticks.fifo"
            input             = "{\"kind\":\"tick\"}"
            sqs               = { message_group_id = "ticks", kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/bbbbbbbb-2222-3333-4444-555555555555" }
            dead_letter_queue = { arn = "arn:aws:sqs:eu-west-1:123456789012:core-prod-events-dlq" }
          }
        }
        flow = {
          expression              = "at(2030-01-01T00:00:00)"
          action_after_completion = "DELETE"
          start_date              = "2029-12-31T00:00:00Z"
          end_date                = "2030-01-02T00:00:00Z"
          target                  = { type = "step_functions", arn = "arn:aws:states:eu-west-1:123456789012:stateMachine:core-prod-flow", dead_letter_queue = { enabled = false }, retry_policy = { maximum_retry_attempts = 3, maximum_event_age_in_seconds = 3600 } }
        }
        job = {
          expression = "cron(0 3 * * ? *)"
          target     = { type = "batch", arn = "arn:aws:batch:eu-west-1:123456789012:job-queue/core-prod", batch = { job_definition_arn = "arn:aws:batch:eu-west-1:123456789012:job-definition/core-prod-report:3", array_size = 4, job_attempts = 2 }, dead_letter_queue = { enabled = false } }
        }
        cleanup = {
          expression = "cron(0 4 * * ? *)"
          target     = { type = "batch", arn = "arn:aws:batch:eu-west-1:123456789012:job-queue/core-prod", batch = { job_definition_arn = "arn:aws:batch:eu-west-1:123456789012:job-definition/core-prod-cleanup", job_name = "cleanup" }, dead_letter_queue = { enabled = false } }
        }
        task = {
          expression = "rate(1 hour)"
          state      = "DISABLED"
          target = {
            type              = "ecs"
            arn               = "arn:aws:ecs:eu-west-1:123456789012:cluster/core-prod"
            dead_letter_queue = { enabled = false }
            ecs = {
              task_definition_arn = "arn:aws:ecs:eu-west-1:123456789012:task-definition/core-prod-sync:7"
              pass_role_arns      = ["arn:aws:iam::123456789012:role/core-prod-sync-task"]
              subnet_ids          = ["subnet-0123456789abcdef0"]
              security_group_ids  = ["sg-0aaaaaaaaaaaaaaaa"]
            }
          }
        }
        stream = {
          expression = "rate(1 hour)"
          target     = { type = "kinesis", arn = "arn:aws:kinesis:eu-west-1:123456789012:stream/core-prod-clicks", kinesis = { partition_key = "ticks" }, dead_letter_queue = { enabled = false } }
        }
        publish = {
          expression = "rate(1 day)"
          target     = { type = "event_bus", input = "{\"ok\":true}", event_bus = { detail_type = "Tick", source = "core.scheduler" }, dead_letter_queue = { enabled = false } }
        }
      }
    }
  }

  assert {
    condition     = aws_scheduler_schedule_group.this[0].name == "core-prod" && aws_scheduler_schedule_group.this[0].tags["Name"] == "core-prod" && aws_scheduler_schedule_group.this[0].tags["Team"] == "payments" && aws_scheduler_schedule_group.this[0].tags["ManagedBy"] == "Terraform"
    error_message = "One tagged schedule group <application>-<environment>."
  }

  assert {
    condition     = output.schedule_group_name == "core-prod" && output.schedule_group_arn == "arn:aws:scheduler:eu-west-1:123456789012:schedule-group/core-prod" && keys(output.schedule_arns) == ["cleanup", "enqueue", "flow", "job", "publish", "report", "stream", "task"]
    error_message = "Group name, group ARN and schedule ARNs by key are exported."
  }

  assert {
    condition     = aws_scheduler_schedule.this["report"].name == "core-prod-report" && alltrue([for s in values(aws_scheduler_schedule.this) : s.group_name == "core-prod"]) && aws_scheduler_schedule.this["report"].description == "Nightly report." && aws_scheduler_schedule.this["report"].schedule_expression == "cron(0 2 * * ? *)"
    error_message = "Schedules are named <...>-<key> in the module group."
  }

  assert {
    condition     = aws_scheduler_schedule.this["report"].schedule_expression_timezone == "UTC" && aws_scheduler_schedule.this["enqueue"].schedule_expression_timezone == "Europe/Dublin" && aws_scheduler_schedule.this["report"].state == "ENABLED" && aws_scheduler_schedule.this["task"].state == "DISABLED"
    error_message = "Timezone defaults to UTC and state to ENABLED."
  }

  assert {
    condition     = aws_scheduler_schedule.this["report"].flexible_time_window[0].mode == "OFF" && aws_scheduler_schedule.this["report"].flexible_time_window[0].maximum_window_in_minutes == null && aws_scheduler_schedule.this["enqueue"].flexible_time_window[0].mode == "FLEXIBLE" && aws_scheduler_schedule.this["enqueue"].flexible_time_window[0].maximum_window_in_minutes == 15
    error_message = "No window maps to OFF; minutes map to FLEXIBLE."
  }

  assert {
    condition     = aws_scheduler_schedule.this["report"].action_after_completion == "NONE" && aws_scheduler_schedule.this["flow"].action_after_completion == "DELETE" && aws_scheduler_schedule.this["flow"].start_date == "2029-12-31T00:00:00Z" && aws_scheduler_schedule.this["flow"].end_date == "2030-01-02T00:00:00Z"
    error_message = "action_after_completion, start_date and end_date must apply."
  }

  assert {
    condition     = alltrue([for s in values(aws_scheduler_schedule.this) : s.target[0].role_arn == "arn:aws:iam::123456789012:role/core-prod-events-eu-west-1" && s.kms_key_arn == null])
    error_message = "Every schedule uses the module role and the AWS owned key by default."
  }

  assert {
    condition     = aws_scheduler_schedule.this["report"].target[0].arn == "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-report:live" && aws_scheduler_schedule.this["report"].target[0].dead_letter_config[0].arn == "arn:aws:sqs:eu-west-1:123456789012:core-prod-events-dlq" && aws_scheduler_schedule.this["report"].target[0].retry_policy[0].maximum_retry_attempts == 185 && aws_scheduler_schedule.this["report"].target[0].retry_policy[0].maximum_event_age_in_seconds == 86400
    error_message = "Lambda schedules keep their DLQ and default retries."
  }

  assert {
    condition     = aws_scheduler_schedule.this["enqueue"].target[0].sqs_parameters[0].message_group_id == "ticks" && aws_scheduler_schedule.this["enqueue"].target[0].input == "{\"kind\":\"tick\"}"
    error_message = "SQS schedules take the message group and input."
  }

  assert {
    condition     = aws_scheduler_schedule.this["flow"].target[0].arn == "arn:aws:states:eu-west-1:123456789012:stateMachine:core-prod-flow" && length(aws_scheduler_schedule.this["flow"].target[0].dead_letter_config) == 0 && aws_scheduler_schedule.this["flow"].target[0].retry_policy[0].maximum_retry_attempts == 3 && aws_scheduler_schedule.this["flow"].target[0].retry_policy[0].maximum_event_age_in_seconds == 3600
    error_message = "Step Functions schedules take their retry policy; DLQ off removes it."
  }

  assert {
    condition     = aws_scheduler_schedule.this["job"].target[0].arn == "arn:aws:scheduler:::aws-sdk:batch:submitJob" && jsondecode(aws_scheduler_schedule.this["job"].target[0].input) == { JobName = "core-prod-job", JobQueue = "arn:aws:batch:eu-west-1:123456789012:job-queue/core-prod", JobDefinition = "arn:aws:batch:eu-west-1:123456789012:job-definition/core-prod-report:3", ArrayProperties = { Size = 4 }, RetryStrategy = { Attempts = 2 } }
    error_message = "Batch schedules use the SubmitJob universal target with the job request as input."
  }

  assert {
    condition     = jsondecode(aws_scheduler_schedule.this["cleanup"].target[0].input) == { JobName = "cleanup", JobQueue = "arn:aws:batch:eu-west-1:123456789012:job-queue/core-prod", JobDefinition = "arn:aws:batch:eu-west-1:123456789012:job-definition/core-prod-cleanup" }
    error_message = "Batch input omits unset array and retry settings."
  }

  assert {
    condition     = aws_scheduler_schedule.this["task"].target[0].ecs_parameters[0].task_definition_arn == "arn:aws:ecs:eu-west-1:123456789012:task-definition/core-prod-sync:7" && aws_scheduler_schedule.this["task"].target[0].ecs_parameters[0].launch_type == "FARGATE" && aws_scheduler_schedule.this["task"].target[0].ecs_parameters[0].propagate_tags == "TASK_DEFINITION" && !aws_scheduler_schedule.this["task"].target[0].ecs_parameters[0].network_configuration[0].assign_public_ip
    error_message = "ECS schedules take the task definition and private networking."
  }

  assert {
    condition     = aws_scheduler_schedule.this["stream"].target[0].kinesis_parameters[0].partition_key == "ticks" && length(aws_scheduler_schedule.this["stream"].target[0].sqs_parameters) == 0
    error_message = "Kinesis schedules take the partition key."
  }

  assert {
    condition     = aws_scheduler_schedule.this["publish"].target[0].arn == "arn:aws:events:eu-west-1:123456789012:event-bus/core-prod" && aws_scheduler_schedule.this["publish"].target[0].eventbridge_parameters[0].detail_type == "Tick" && aws_scheduler_schedule.this["publish"].target[0].eventbridge_parameters[0].source == "core.scheduler" && aws_scheduler_schedule.this["publish"].target[0].input == "{\"ok\":true}"
    error_message = "Event bus schedules default to the module bus."
  }

  assert {
    condition     = jsondecode(module.role[0].trust_policy_json).Statement[0].Principal.Service == ["events.amazonaws.com", "scheduler.amazonaws.com"] && jsondecode(module.role[0].trust_policy_json).Statement[0].Condition == { StringEquals = { "aws:SourceAccount" = ["123456789012"] } }
    error_message = "The role trusts EventBridge and EventBridge Scheduler in this account only."
  }

  assert {
    condition     = [for s in jsondecode(module.role[0].policy_json).Statement : s.Sid] == ["InvokeFunctions", "SendMessages", "StartExecutions", "SubmitJobs", "RunTasks", "TagTasks", "PassTaskRoles", "PutRecords", "EncryptRecords", "PutEvents", "SendDeadLetters", "EncryptMessages"]
    error_message = "Schedules get the role statements their targets need."
  }

  assert {
    condition     = jsondecode(module.role[0].policy_json).Statement[0].Action == ["lambda:InvokeFunction"] && jsondecode(module.role[0].policy_json).Statement[0].Resource == ["arn:aws:lambda:eu-west-1:123456789012:function:core-prod-report:live"]
    error_message = "lambda:InvokeFunction only on the target function."
  }

  assert {
    condition     = jsondecode(module.role[0].policy_json).Statement[1].Action == ["sqs:SendMessage"] && jsondecode(module.role[0].policy_json).Statement[1].Resource == ["arn:aws:sqs:eu-west-1:123456789012:core-prod-ticks.fifo"]
    error_message = "sqs:SendMessage only on the target queue."
  }

  assert {
    condition     = jsondecode(module.role[0].policy_json).Statement[3].Resource == ["arn:aws:batch:eu-west-1:123456789012:job-queue/core-prod", "arn:aws:batch:eu-west-1:123456789012:job-definition/core-prod-cleanup", "arn:aws:batch:eu-west-1:123456789012:job-definition/core-prod-report", "arn:aws:batch:eu-west-1:123456789012:job-definition/core-prod-cleanup:*", "arn:aws:batch:eu-west-1:123456789012:job-definition/core-prod-report:*"]
    error_message = "batch:SubmitJob only on the job queue and job definitions."
  }

  assert {
    condition     = jsondecode(module.role[0].policy_json).Statement[9].Resource == ["arn:aws:events:eu-west-1:123456789012:event-bus/core-prod"]
    error_message = "events:PutEvents only on the target bus."
  }

  assert {
    condition     = jsondecode(module.role[0].policy_json).Statement[10].Action == ["sqs:SendMessage"] && jsondecode(module.role[0].policy_json).Statement[10].Resource == ["arn:aws:sqs:eu-west-1:123456789012:core-prod-events-dlq"]
    error_message = "Schedules may send to their dead-letter queue."
  }

  assert {
    condition     = jsondecode(module.role[0].policy_json).Statement[11].Action == ["kms:GenerateDataKey", "kms:Decrypt"] && jsondecode(module.role[0].policy_json).Statement[11].Resource == ["arn:aws:kms:eu-west-1:123456789012:key/bbbbbbbb-2222-3333-4444-555555555555", "arn:aws:kms:eu-west-1:123456789012:key/aaaaaaaa-2222-3333-4444-555555555555"] && jsondecode(module.role[0].policy_json).Statement[11].Condition.StringEquals["kms:ViaService"] == "sqs.eu-west-1.amazonaws.com"
    error_message = "Queue keys only through SQS."
  }
}

run "scheduler_group_only" {
  command   = plan
  state_key = "group"

  variables {
    scheduler = { enabled = true }
  }

  assert {
    condition     = length(aws_scheduler_schedule_group.this) == 1 && length(aws_scheduler_schedule.this) == 0 && length(module.role) == 1 && module.role[0].policy_json == null
    error_message = "enabled creates the group and the role; no schedules, no module policy."
  }
}

run "schedules_without_a_bus" {
  command   = plan
  state_key = "schedonly"

  variables {
    bus = { enabled = false }
    scheduler = {
      enabled   = true
      schedules = { nightly = { expression = "cron(0 2 * * ? *)", target = { type = "lambda", arn = "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-report:live", dead_letter_queue = { enabled = false } } } }
    }
  }

  assert {
    condition     = length(aws_cloudwatch_event_bus.this) + length(module.log_group) + length(aws_cloudwatch_event_rule.this) == 0 && length(aws_scheduler_schedule.this) == 1 && aws_scheduler_schedule.this["nightly"].name == "core-prod-nightly"
    error_message = "A schedules-only call creates no bus."
  }

  assert {
    condition     = [for s in jsondecode(module.role[0].policy_json).Statement : s.Sid] == ["InvokeFunctions"]
    error_message = "A Lambda schedule without a DLQ gets only lambda:InvokeFunction."
  }
}

run "sqs_and_lambda_targets_need_no_role" {
  command   = plan
  state_key = "norole"

  variables {
    rules = {
      orders = { event_pattern = "{\"source\":[\"core.orders\"]}" }
    }
    targets = {
      orders = {
        worker = { type = "lambda", arn = "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-worker:live", dead_letter_queue = { arn = "arn:aws:sqs:eu-west-1:123456789012:core-prod-events-dlq" } }
        queue  = { type = "sqs", arn = "arn:aws:sqs:eu-west-1:123456789012:core-prod-orders", dead_letter_queue = { arn = "arn:aws:sqs:eu-west-1:123456789012:core-prod-events-dlq" } }
      }
    }
  }

  assert {
    condition     = length(module.role) == 0 && output.role_arn == null && output.role_name == null
    error_message = "SQS and Lambda targets use resource policies, not a role."
  }
}

run "module_key_is_planned_safely" {
  command = plan

  variables {
    kms     = { create = true }
    archive = { enabled = true }
    scheduler = {
      enabled   = true
      schedules = { nightly = { expression = "cron(0 2 * * ? *)", target = { type = "lambda", arn = "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-report:live", dead_letter_queue = { enabled = false } } } }
    }
  }

  assert {
    condition     = module.encryption.created && length(aws_cloudwatch_event_archive.this) == 1 && length(aws_scheduler_schedule.this) == 1
    error_message = "kms.create must plan without knowing the key ARN."
  }
}

run "module_key_encrypts_bus_archive_and_logs" {
  command = apply

  variables {
    kms     = { create = true }
    archive = { enabled = true, retention_days = 30 }
    scheduler = {
      enabled   = true
      schedules = { nightly = { expression = "cron(0 2 * * ? *)", target = { type = "lambda", arn = "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-report:live", dead_letter_queue = { enabled = false } } } }
    }
  }

  assert {
    condition     = aws_cloudwatch_event_bus.this[0].kms_key_identifier == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && aws_cloudwatch_event_archive.this[0].kms_key_identifier == aws_cloudwatch_event_bus.this[0].kms_key_identifier && module.log_group[0].kms_key_arn == aws_cloudwatch_event_bus.this[0].kms_key_identifier
    error_message = "The module key must encrypt the bus, the archive and the logs."
  }

  assert {
    condition     = aws_cloudwatch_event_archive.this[0].name == "core-prod" && aws_cloudwatch_event_archive.this[0].retention_days == 30 && aws_cloudwatch_event_archive.this[0].event_source_arn == output.bus_arn
    error_message = "The archive must record the bus with its retention."
  }

  assert {
    condition     = aws_scheduler_schedule.this["nightly"].kms_key_arn == output.kms_key_arn && output.kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    error_message = "The module key must encrypt schedule payloads."
  }

  assert {
    condition     = [for s in jsondecode(module.role[0].policy_json).Statement : s if s.Sid == "DecryptSchedulePayloads"][0].Action == ["kms:Decrypt"] && [for s in jsondecode(module.role[0].policy_json).Statement : s if s.Sid == "DecryptSchedulePayloads"][0].Resource == [output.kms_key_arn]
    error_message = "The role may decrypt schedule payloads with the module key."
  }
}

run "caller_key_id_and_log_key_override" {
  command = plan

  variables {
    kms             = { key_id = "11111111-2222-3333-4444-555555555555" }
    cloudwatch_logs = { kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/99999999-2222-3333-4444-555555555555", retention_in_days = 731 }
    scheduler = {
      enabled   = true
      schedules = { nightly = { expression = "cron(0 2 * * ? *)", target = { type = "lambda", arn = "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-report:live", dead_letter_queue = { enabled = false } } } }
    }
  }

  assert {
    condition     = aws_cloudwatch_event_bus.this[0].kms_key_identifier == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && aws_scheduler_schedule.this["nightly"].kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    error_message = "A key ID must be used as the key ARN on the bus and schedules."
  }

  assert {
    condition     = [for s in jsondecode(module.role[0].policy_json).Statement : s.Sid] == ["InvokeFunctions", "DecryptSchedulePayloads"] && jsondecode(module.role[0].policy_json).Statement[1].Resource == ["arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"]
    error_message = "The role may decrypt schedule payloads with the caller key."
  }

  assert {
    condition     = module.log_group[0].kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/99999999-2222-3333-4444-555555555555" && module.log_group[0].retention_in_days == 731
    error_message = "cloudwatch_logs must override the log key and retention."
  }
}

run "logging_off" {
  command   = plan
  state_key = "nologs"

  variables {
    cloudwatch_logs = { enabled = false }
  }

  assert {
    condition     = length(aws_cloudwatch_event_bus.this[0].log_config) == 0 && length(module.log_group) + length(aws_cloudwatch_log_resource_policy.this) + length(aws_cloudwatch_log_delivery_source.this) + length(aws_cloudwatch_log_delivery_destination.this) + length(aws_cloudwatch_log_delivery.error) == 0 && output.log_group_name == null
    error_message = "Without bus logging there is no log group, log policy or delivery."
  }
}

run "default_bus" {
  command   = apply
  state_key = "default"

  variables {
    bus = { enabled = false }
    rules = {
      orders = { event_pattern = "{\"source\":[\"core.orders\"]}" }
    }
  }

  assert {
    condition     = length(aws_cloudwatch_event_bus.this) == 0 && length(module.log_group) == 0 && length(aws_cloudwatch_log_delivery_source.this) == 0 && length(aws_cloudwatch_log_resource_policy.this) == 0
    error_message = "The default bus gets no bus resources and no bus logging."
  }

  assert {
    condition     = aws_cloudwatch_event_rule.this["orders"].event_bus_name == "default" && output.bus_name == "default" && output.bus_arn == "arn:aws:events:eu-west-1:123456789012:event-bus/default"
    error_message = "Rules attach to the default bus."
  }
}

run "bus_policy" {
  command = apply

  variables {
    policy_statements = [{
      sid        = "AllowOrganization"
      actions    = ["events:PutEvents"]
      principals = { AWS = ["*"] }
      conditions = [{ test = "StringEquals", variable = "aws:PrincipalOrgID", values = ["o-a1b2c3d4e5"] }]
    }]
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_event_bus_policy.this[0].policy).Statement[0].Resource == ["arn:aws:events:eu-west-1:123456789012:event-bus/core-prod"] && aws_cloudwatch_event_bus_policy.this[0].event_bus_name == "core-prod"
    error_message = "Bus policy statements default to the bus (EventBridge.3)."
  }
}

run "bring_your_own_role" {
  command   = plan
  state_key = "byorole"

  variables {
    iam_role = { create = false, arn = "arn:aws:iam::123456789012:role/shared-events" }
    rules    = { orders = { event_pattern = "{\"source\":[\"core.orders\"]}" } }
    targets  = { orders = { flow = { type = "step_functions", arn = "arn:aws:states:eu-west-1:123456789012:stateMachine:core-prod-flow", dead_letter_queue = { enabled = false } } } }
    scheduler = {
      enabled   = true
      schedules = { nightly = { expression = "rate(1 day)", target = { type = "step_functions", arn = "arn:aws:states:eu-west-1:123456789012:stateMachine:core-prod-flow", dead_letter_queue = { enabled = false } } } }
    }
  }

  assert {
    condition     = aws_cloudwatch_event_target.this["orders/flow"].role_arn == "arn:aws:iam::123456789012:role/shared-events" && aws_scheduler_schedule.this["nightly"].target[0].role_arn == "arn:aws:iam::123456789012:role/shared-events" && length(module.role) == 0
    error_message = "A caller role must replace the module role on rules and schedules."
  }
}

run "extend_the_role" {
  command   = plan
  state_key = "extend"

  variables {
    iam_role = {
      permissions_boundary_arn = "arn:aws:iam::123456789012:policy/boundary"
      policy_statements        = [{ sid = "ReadConfig", actions = ["ssm:GetParameter"], resources = ["arn:aws:ssm:eu-west-1:123456789012:parameter/core/prod/*"] }]
    }
    rules   = { orders = { event_pattern = "{\"source\":[\"core.orders\"]}" } }
    targets = { orders = { flow = { type = "step_functions", arn = "arn:aws:states:eu-west-1:123456789012:stateMachine:core-prod-flow", dead_letter_queue = { enabled = false } } } }
  }

  assert {
    condition     = [for s in jsondecode(module.role[0].policy_json).Statement : s.Sid] == ["StartExecutions", "ReadConfig"]
    error_message = "Caller statements must be added to the module statements."
  }
}

run "long_names_are_truncated" {
  command   = plan
  state_key = "long"

  variables {
    application = "abcdefghijklmnopqrstuvwx"
    environment = "abcdefghijkl"
    name        = "abcdefghijklmnopqrstuvwxyz012345"
    archive     = { enabled = true }
    rules       = { abcdefghijklmnopqrstuvwxyz012345 = { event_pattern = "{\"source\":[\"x\"]}" } }
    scheduler = {
      enabled   = true
      schedules = { abcdefghijklmnopqrstuvwxyz012345 = { expression = "rate(1 hour)", target = { type = "lambda", arn = "arn:aws:lambda:eu-west-1:123456789012:function:f", dead_letter_queue = { enabled = false } } } }
    }
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.this["abcdefghijklmnopqrstuvwxyz012345"].name) == 64 && length(aws_cloudwatch_event_archive.this[0].name) == 48 && length(aws_cloudwatch_log_delivery_source.this["ERROR_LOGS"].name) == 60
    error_message = "Rule, archive and delivery names are cut to their limits."
  }

  assert {
    condition     = length(aws_scheduler_schedule_group.this[0].name) == 64 && length(aws_scheduler_schedule.this["abcdefghijklmnopqrstuvwxyz012345"].name) == 64 && aws_scheduler_schedule.this["abcdefghijklmnopqrstuvwxyz012345"].name != aws_scheduler_schedule_group.this[0].name
    error_message = "Group and schedule names are cut to 64."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Orders_Bus"
  }

  expect_failures = [var.name]
}

run "rejects_invalid_application" {
  command = plan

  variables {
    application = "Core"
  }

  expect_failures = [var.application]
}

run "rejects_invalid_environment" {
  command = plan

  variables {
    environment = "PROD"
  }

  expect_failures = [var.environment]
}

run "rejects_create_and_key_id" {
  command = plan

  variables {
    kms = { create = true, key_id = "11111111-2222-3333-4444-555555555555" }
  }

  expect_failures = [var.kms]
}

run "rejects_invalid_key_id" {
  command = plan

  variables {
    kms = { key_id = "alias/events" }
  }

  expect_failures = [var.kms]
}

run "rejects_invalid_log_level" {
  command = plan

  variables {
    cloudwatch_logs = { level = "OFF" }
  }

  expect_failures = [var.cloudwatch_logs]
}

run "rejects_invalid_archive_retention" {
  command = plan

  variables {
    archive = { enabled = true, retention_days = 0 }
  }

  expect_failures = [var.archive]
}

run "rejects_invalid_rule_key" {
  command = plan

  variables {
    rules = { Orders_Rule = { event_pattern = "{\"source\":[\"x\"]}" } }
  }

  expect_failures = [var.rules]
}

run "rejects_invalid_event_pattern" {
  command = plan

  variables {
    rules = { orders = { event_pattern = "core.orders" } }
  }

  expect_failures = [var.rules]
}

run "rejects_invalid_rule_state" {
  command = plan

  variables {
    rules = { orders = { event_pattern = "{\"source\":[\"x\"]}", state = "ON" } }
  }

  expect_failures = [var.rules]
}

run "rejects_invalid_target_key" {
  command = plan

  variables {
    rules   = { orders = { event_pattern = "{\"source\":[\"x\"]}" } }
    targets = { orders = { "a/b" = { type = "sqs", arn = "arn:aws:sqs:eu-west-1:123456789012:q", dead_letter_queue = { enabled = false } } } }
  }

  expect_failures = [var.targets]
}

run "rejects_unknown_target_type" {
  command = plan

  variables {
    rules   = { orders = { event_pattern = "{\"source\":[\"x\"]}" } }
    targets = { orders = { t = { type = "sns", arn = "arn:aws:sns:eu-west-1:123456789012:t", dead_letter_queue = { enabled = false } } } }
  }

  expect_failures = [var.targets]
}

run "rejects_batch_without_block" {
  command = plan

  variables {
    rules   = { orders = { event_pattern = "{\"source\":[\"x\"]}" } }
    targets = { orders = { t = { type = "batch", arn = "arn:aws:batch:eu-west-1:123456789012:job-queue/q", dead_letter_queue = { enabled = false } } } }
  }

  expect_failures = [var.targets]
}

run "rejects_dead_letter_queue_without_arn" {
  command = plan

  variables {
    rules   = { orders = { event_pattern = "{\"source\":[\"x\"]}" } }
    targets = { orders = { t = { type = "sqs", arn = "arn:aws:sqs:eu-west-1:123456789012:q" } } }
  }

  expect_failures = [var.targets]
}

run "rejects_invalid_retry_policy" {
  command = plan

  variables {
    rules   = { orders = { event_pattern = "{\"source\":[\"x\"]}" } }
    targets = { orders = { t = { type = "sqs", arn = "arn:aws:sqs:eu-west-1:123456789012:q", dead_letter_queue = { enabled = false }, retry_policy = { maximum_retry_attempts = 200 } } } }
  }

  expect_failures = [var.targets]
}

run "rejects_fargate_without_subnets" {
  command = plan

  variables {
    rules   = { orders = { event_pattern = "{\"source\":[\"x\"]}" } }
    targets = { orders = { t = { type = "ecs", arn = "arn:aws:ecs:eu-west-1:123456789012:cluster/c", dead_letter_queue = { enabled = false }, ecs = { task_definition_arn = "arn:aws:ecs:eu-west-1:123456789012:task-definition/t:1" } } } }
  }

  expect_failures = [var.targets]
}

run "rejects_role_without_arn" {
  command = plan

  variables {
    iam_role = { create = false }
  }

  expect_failures = [var.iam_role]
}

run "rejects_targets_for_unknown_rule" {
  command = plan

  variables {
    rules   = { orders = { event_pattern = "{\"source\":[\"x\"]}" } }
    targets = { refunds = { t = { type = "sqs", arn = "arn:aws:sqs:eu-west-1:123456789012:q", dead_letter_queue = { enabled = false } } } }
  }

  expect_failures = [var.targets]
}

run "rejects_rule_target_without_arn" {
  command = plan

  variables {
    rules   = { orders = { event_pattern = "{\"source\":[\"x\"]}" } }
    targets = { orders = { t = { type = "event_bus", dead_letter_queue = { enabled = false } } } }
  }

  expect_failures = [var.targets]
}

run "rejects_schedule_fields_on_rule_targets" {
  command = plan

  variables {
    rules   = { orders = { event_pattern = "{\"source\":[\"x\"]}" } }
    targets = { orders = { t = { type = "sqs", arn = "arn:aws:sqs:eu-west-1:123456789012:q", sqs = { kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" }, dead_letter_queue = { enabled = false } } } }
  }

  expect_failures = [var.targets]
}

run "rejects_schedules_when_disabled" {
  command = plan

  variables {
    scheduler = { schedules = { nightly = { expression = "rate(1 hour)", target = { type = "lambda", arn = "arn:aws:lambda:eu-west-1:123456789012:function:f", dead_letter_queue = { enabled = false } } } } }
  }

  expect_failures = [var.scheduler]
}

run "rejects_invalid_schedule_key" {
  command = plan

  variables {
    scheduler = { enabled = true, schedules = { Nightly_Run = { expression = "rate(1 hour)", target = { type = "lambda", arn = "arn:aws:lambda:eu-west-1:123456789012:function:f", dead_letter_queue = { enabled = false } } } } }
  }

  expect_failures = [var.scheduler]
}

run "rejects_invalid_schedule_expression" {
  command = plan

  variables {
    scheduler = { enabled = true, schedules = { nightly = { expression = "0 2 * * *", target = { type = "lambda", arn = "arn:aws:lambda:eu-west-1:123456789012:function:f", dead_letter_queue = { enabled = false } } } } }
  }

  expect_failures = [var.scheduler]
}

run "rejects_invalid_schedule_state" {
  command = plan

  variables {
    scheduler = { enabled = true, schedules = { nightly = { expression = "rate(1 hour)", action_after_completion = "KEEP", target = { type = "lambda", arn = "arn:aws:lambda:eu-west-1:123456789012:function:f", dead_letter_queue = { enabled = false } } } } }
  }

  expect_failures = [var.scheduler]
}

run "rejects_invalid_flexible_window" {
  command = plan

  variables {
    scheduler = { enabled = true, schedules = { nightly = { expression = "rate(1 hour)", flexible_window_minutes = 1441, target = { type = "lambda", arn = "arn:aws:lambda:eu-west-1:123456789012:function:f", dead_letter_queue = { enabled = false } } } } }
  }

  expect_failures = [var.scheduler]
}

run "rejects_api_destination_schedule" {
  command = plan

  variables {
    scheduler = { enabled = true, schedules = { nightly = { expression = "rate(1 hour)", target = { type = "api_destination", arn = "arn:aws:events:eu-west-1:123456789012:api-destination/hook/abcd", dead_letter_queue = { enabled = false } } } } }
  }

  expect_failures = [var.scheduler]
}

run "rejects_event_bus_schedule_without_bus" {
  command = plan

  variables {
    bus       = { enabled = false }
    scheduler = { enabled = true, schedules = { nightly = { expression = "rate(1 hour)", target = { type = "event_bus", event_bus = { detail_type = "Tick", source = "core" }, dead_letter_queue = { enabled = false } } } } }
  }

  expect_failures = [var.scheduler]
}

run "rejects_input_path_on_schedules" {
  command = plan

  variables {
    scheduler = { enabled = true, schedules = { nightly = { expression = "rate(1 hour)", target = { type = "lambda", arn = "arn:aws:lambda:eu-west-1:123456789012:function:f", input_path = "$.detail", dead_letter_queue = { enabled = false } } } } }
  }

  expect_failures = [var.scheduler]
}

run "rejects_input_transformer_on_schedules" {
  command = plan

  variables {
    scheduler = { enabled = true, schedules = { nightly = { expression = "rate(1 hour)", target = { type = "lambda", arn = "arn:aws:lambda:eu-west-1:123456789012:function:f", input_transformer = { input_template = "{}" }, dead_letter_queue = { enabled = false } } } } }
  }

  expect_failures = [var.scheduler]
}

run "rejects_http_on_schedules" {
  command = plan

  variables {
    scheduler = { enabled = true, schedules = { nightly = { expression = "rate(1 hour)", target = { type = "lambda", arn = "arn:aws:lambda:eu-west-1:123456789012:function:f", http = { header_parameters = { X-Source = "scheduler" } }, dead_letter_queue = { enabled = false } } } } }
  }

  expect_failures = [var.scheduler]
}

run "rejects_input_on_batch_schedules" {
  command = plan

  variables {
    scheduler = { enabled = true, schedules = { nightly = { expression = "rate(1 hour)", target = { type = "batch", arn = "arn:aws:batch:eu-west-1:123456789012:job-queue/q", input = "{}", batch = { job_definition_arn = "arn:aws:batch:eu-west-1:123456789012:job-definition/j" }, dead_letter_queue = { enabled = false } } } } }
  }

  expect_failures = [var.scheduler]
}

run "rejects_kinesis_schedule_without_partition_key" {
  command = plan

  variables {
    scheduler = { enabled = true, schedules = { nightly = { expression = "rate(1 hour)", target = { type = "kinesis", arn = "arn:aws:kinesis:eu-west-1:123456789012:stream/s", dead_letter_queue = { enabled = false } } } } }
  }

  expect_failures = [var.scheduler]
}

run "rejects_event_bus_schedule_without_block" {
  command = plan

  variables {
    scheduler = { enabled = true, schedules = { nightly = { expression = "rate(1 hour)", target = { type = "event_bus", dead_letter_queue = { enabled = false } } } } }
  }

  expect_failures = [var.scheduler]
}

run "rejects_schedule_dead_letter_queue_without_arn" {
  command = plan

  variables {
    scheduler = { enabled = true, schedules = { nightly = { expression = "rate(1 hour)", target = { type = "lambda", arn = "arn:aws:lambda:eu-west-1:123456789012:function:f" } } } }
  }

  expect_failures = [var.scheduler]
}

run "rejects_invalid_schedule_retry_policy" {
  command = plan

  variables {
    scheduler = { enabled = true, schedules = { nightly = { expression = "rate(1 hour)", target = { type = "lambda", arn = "arn:aws:lambda:eu-west-1:123456789012:function:f", dead_letter_queue = { enabled = false }, retry_policy = { maximum_event_age_in_seconds = 30 } } } } }
  }

  expect_failures = [var.scheduler]
}

run "rejects_fargate_schedule_without_subnets" {
  command = plan

  variables {
    scheduler = { enabled = true, schedules = { nightly = { expression = "rate(1 hour)", target = { type = "ecs", arn = "arn:aws:ecs:eu-west-1:123456789012:cluster/c", dead_letter_queue = { enabled = false }, ecs = { task_definition_arn = "arn:aws:ecs:eu-west-1:123456789012:task-definition/t:1" } } } } }
  }

  expect_failures = [var.scheduler]
}
