mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      name   = "us-west-2"
      region = "us-west-2"
    }
  }

  # The provider validates ARN-typed arguments, so computed ARNs that feed
  # other resources need ARN-shaped mock values.
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/core-prod-etl-mock"
    }
  }

  mock_resource "aws_batch_scheduling_policy" {
    defaults = {
      arn = "arn:aws:batch:us-west-2:123456789012:scheduling-policy/core-prod-etl-policy"
    }
  }

  mock_resource "aws_batch_compute_environment" {
    defaults = {
      arn = "arn:aws:batch:us-west-2:123456789012:compute-environment/core-prod-etl-fargate"
    }
  }

  mock_resource "aws_batch_job_queue" {
    defaults = {
      arn = "arn:aws:batch:us-west-2:123456789012:job-queue/core-prod-etl-default"
    }
  }

  mock_resource "aws_batch_job_definition" {
    defaults = {
      arn = "arn:aws:batch:us-west-2:123456789012:job-definition/core-prod-etl-sync:1"
    }
  }
}

variables {
  application = "core"
  environment = "prod"
  name        = "etl"
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
}

# ------------------------------------------------------------------------------
# Naming
# ------------------------------------------------------------------------------
run "verify_rendered_names" {
  command = plan

  assert {
    condition     = aws_iam_role.ecs_execution_role.name == "core-prod-etl-ecs-execution-role"
    error_message = "ECS execution role name did not match <application>-<environment>-<name>-ecs-execution-role."
  }

  assert {
    condition     = aws_iam_role.ecs_job_role.name == "core-prod-etl-ecs-job-role"
    error_message = "ECS job role name did not match <application>-<environment>-<name>-ecs-job-role."
  }

  assert {
    condition     = aws_iam_role.eventbridge_batch.name == "core-prod-etl-eb-batch-role"
    error_message = "EventBridge role name did not match <application>-<environment>-<name>-eb-batch-role."
  }

  assert {
    condition     = aws_iam_role_policy.eventbridge_batch.name == "core-prod-etl-eb-batch-policy"
    error_message = "EventBridge inline policy name did not match <application>-<environment>-<name>-eb-batch-policy."
  }
}

run "verify_name_fallback_when_empty" {
  command = plan

  variables {
    name = ""
  }

  assert {
    condition     = aws_iam_role.ecs_execution_role.name == "core-prod-ecs-execution-role"
    error_message = "An empty name must fall back to <application>-<environment>."
  }

  assert {
    condition     = aws_iam_role.ecs_execution_role.tags["Name"] == "core-prod"
    error_message = "The Name tag must fall back to <application>-<environment> when name is empty."
  }
}

run "verify_name_fallback_when_null" {
  command = plan

  variables {
    name = null
  }

  assert {
    condition     = aws_iam_role.eventbridge_batch.name == "core-prod-eb-batch-role"
    error_message = "A null name must fall back to <application>-<environment>."
  }

  assert {
    condition     = aws_iam_role.ecs_job_role.tags["Name"] == "core-prod"
    error_message = "The Name tag must fall back to <application>-<environment> when name is null."
  }
}

# ------------------------------------------------------------------------------
# Tags
# ------------------------------------------------------------------------------
run "verify_governance_and_caller_tags" {
  command = plan

  variables {
    tags = {
      CostCenter = "data-platform"
      Owner      = "platform-team"
    }
  }

  assert {
    condition = alltrue([
      for role in [aws_iam_role.ecs_execution_role, aws_iam_role.ecs_job_role, aws_iam_role.eventbridge_batch] :
      role.tags["Application"] == "core" && role.tags["Environment"] == "prod" && role.tags["Name"] == "core-prod-etl"
    ])
    error_message = "Every IAM role must carry the Application, Environment and Name governance tags."
  }

  assert {
    condition = alltrue([
      for role in [aws_iam_role.ecs_execution_role, aws_iam_role.ecs_job_role, aws_iam_role.eventbridge_batch] :
      role.tags["CostCenter"] == "data-platform" && role.tags["Owner"] == "platform-team"
    ])
    error_message = "Caller tags from var.tags must be preserved on every IAM role."
  }
}

# ------------------------------------------------------------------------------
# Security and shipped defaults
# ------------------------------------------------------------------------------
run "verify_iam_least_privilege_defaults" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_role.ecs_execution_role.assume_role_policy).Statement[0].Principal.Service == "ecs-tasks.amazonaws.com"
    error_message = "ECS execution role must only be assumable by ecs-tasks.amazonaws.com."
  }

  assert {
    condition     = jsondecode(aws_iam_role.ecs_job_role.assume_role_policy).Statement[0].Principal.Service == "ecs-tasks.amazonaws.com"
    error_message = "ECS job role must only be assumable by ecs-tasks.amazonaws.com."
  }

  assert {
    condition     = jsondecode(aws_iam_role.eventbridge_batch.assume_role_policy).Statement[0].Principal.Service == "events.amazonaws.com"
    error_message = "EventBridge role must only be assumable by events.amazonaws.com."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.ecs_execution.policy_arn == "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
    error_message = "ECS execution role must have the AWS managed AmazonECSTaskExecutionRolePolicy attached."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.eventbridge_batch.policy).Statement[0].Action == ["batch:SubmitJob"]
    error_message = "EventBridge inline policy must grant only batch:SubmitJob."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.ecs_job_custom) == 0
    error_message = "The ECS job role must have no policies attached unless the caller supplies them."
  }
}

run "verify_optional_features_off_by_default" {
  command = plan

  assert {
    condition     = length(aws_batch_scheduling_policy.this) == 0
    error_message = "No scheduling policy should be created by default."
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.this) == 0
    error_message = "No CloudWatch log group should be created when cloudwatch_logs is null."
  }

  assert {
    condition = (
      length(aws_batch_compute_environment.this) == 0 &&
      length(aws_batch_job_queue.this) == 0 &&
      length(aws_batch_job_definition.this) == 0
    )
    error_message = "No compute environments, job queues or job definitions should be created by default."
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.this) == 0 && length(aws_cloudwatch_event_target.this) == 0
    error_message = "No EventBridge rules or targets should be created by default."
  }

  assert {
    condition = (
      length(aws_iam_role_policy_attachment.ecs_execution_custom) == 0 &&
      length(aws_iam_role_policy_attachment.eventbridge_batch_custom) == 0
    )
    error_message = "No custom policy attachments should be created by default."
  }

  assert {
    condition     = output.job_queue_arns == {} && output.job_definition_arns == {}
    error_message = "Job queue and job definition ARN outputs must be empty maps by default."
  }
}

run "verify_cloudwatch_logs_encrypted_with_module_kms_key" {
  command = plan

  variables {
    cloudwatch_logs = {
      retention_in_days = 90
    }
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.this) == 1
    error_message = "A log group must be created when cloudwatch_logs is set."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].name == "/aws/batch/core-prod-etl"
    error_message = "Log group name must be /aws/batch/<rendered_name>."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].kms_key_id == "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
    error_message = "Log group must be encrypted with var.kms_key_arn when cloudwatch_logs.kms_key_arn is unset."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].retention_in_days == 90
    error_message = "Log group retention must come from cloudwatch_logs.retention_in_days."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].log_group_class == "STANDARD"
    error_message = "Log group class must be STANDARD."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].deletion_protection_enabled == false
    error_message = "Log group deletion protection must default to false."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].tags["Name"] == "/aws/batch/core-prod-etl"
    error_message = "Log group Name tag must be overridden with the log group name."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].tags["Application"] == "core" && aws_cloudwatch_log_group.this[0].tags["Environment"] == "prod"
    error_message = "Log group must carry the Application and Environment governance tags."
  }
}

run "verify_cloudwatch_logs_kms_and_protection_overrides" {
  command = plan

  variables {
    cloudwatch_logs = {
      retention_in_days           = 365
      kms_key_arn                 = "arn:aws:kms:us-west-2:123456789012:key/87654321-4321-4321-4321-210987654321"
      deletion_protection_enabled = true
    }
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].kms_key_id == "arn:aws:kms:us-west-2:123456789012:key/87654321-4321-4321-4321-210987654321"
    error_message = "cloudwatch_logs.kms_key_arn must take precedence over var.kms_key_arn."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].retention_in_days == 365
    error_message = "Log group retention override was not applied."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this[0].deletion_protection_enabled == true
    error_message = "Log group deletion protection override was not applied."
  }
}

# ------------------------------------------------------------------------------
# Full stack with shipped per-item defaults
# ------------------------------------------------------------------------------
run "verify_full_stack_defaults_and_wiring" {
  command   = apply
  state_key = "verify_full_stack_defaults_and_wiring"

  variables {
    tags = {
      Workload = "DataPipeline"
    }

    create_scheduling_policy = true

    cloudwatch_logs = {
      retention_in_days = 30
    }

    compute_environments = {
      fargate = {
        compute_resources = {
          max_vcpus          = 16
          security_group_ids = ["sg-0123456789abcdef0"]
          subnets            = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
        }
      }
    }

    job_queues = {
      default = {
        priority             = 1
        compute_environments = ["fargate"]
      }
    }

    job_definitions = {
      sync = {
        type = "container"
        container_properties = jsonencode({
          image = "123456789012.dkr.ecr.us-west-2.amazonaws.com/etl-sync:v1.0.0"
        })
      }
    }

    eventbridge_rules = {
      nightly = {
        schedule_expression = "cron(0 2 * * ? *)"
      }
    }

    eventbridge_targets = {
      nightly_sync = {
        rule_name          = "nightly"
        job_queue_key      = "default"
        job_definition_key = "sync"
        job_name           = "nightly-sync"
      }
    }
  }

  # Compute environment
  assert {
    condition     = aws_batch_compute_environment.this["fargate"].name == "core-prod-etl-fargate"
    error_message = "Compute environment name must be <rendered_name>-<key>."
  }

  assert {
    condition     = aws_batch_compute_environment.this["fargate"].type == "MANAGED" && aws_batch_compute_environment.this["fargate"].state == "ENABLED"
    error_message = "Compute environment must default to a MANAGED, ENABLED environment."
  }

  assert {
    condition     = aws_batch_compute_environment.this["fargate"].compute_resources[0].type == "FARGATE"
    error_message = "Compute resources must default to FARGATE."
  }

  assert {
    condition     = aws_batch_compute_environment.this["fargate"].compute_resources[0].max_vcpus == 16
    error_message = "Compute resources max_vcpus did not flow through."
  }

  assert {
    condition     = toset(aws_batch_compute_environment.this["fargate"].compute_resources[0].subnets) == toset(["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"])
    error_message = "Compute resources subnets did not flow through."
  }

  assert {
    condition     = toset(aws_batch_compute_environment.this["fargate"].compute_resources[0].security_group_ids) == toset(["sg-0123456789abcdef0"])
    error_message = "Compute resources security groups did not flow through."
  }

  assert {
    condition     = aws_batch_compute_environment.this["fargate"].tags["Name"] == "core-prod-etl-fargate"
    error_message = "Compute environment Name tag must be overridden with <rendered_name>-<key>."
  }

  assert {
    condition = (
      aws_batch_compute_environment.this["fargate"].tags["Application"] == "core" &&
      aws_batch_compute_environment.this["fargate"].tags["Environment"] == "prod" &&
      aws_batch_compute_environment.this["fargate"].tags["Workload"] == "DataPipeline"
    )
    error_message = "Compute environment must carry the governance tags and the caller tags."
  }

  # Scheduling policy
  assert {
    condition     = aws_batch_scheduling_policy.this[0].name == "core-prod-etl-policy"
    error_message = "Scheduling policy name must default to <rendered_name>-policy."
  }

  assert {
    condition     = aws_batch_scheduling_policy.this[0].tags["Name"] == "core-prod-etl" && aws_batch_scheduling_policy.this[0].tags["Workload"] == "DataPipeline"
    error_message = "Scheduling policy must carry the governance Name tag and the caller tags."
  }

  assert {
    condition     = length(aws_batch_scheduling_policy.this[0].fair_share_policy) == 0
    error_message = "No fair share policy block should be rendered unless one is configured."
  }

  # Job queue
  assert {
    condition     = aws_batch_job_queue.this["default"].name == "core-prod-etl-default"
    error_message = "Job queue name must be <rendered_name>-<key>."
  }

  assert {
    condition     = aws_batch_job_queue.this["default"].state == "ENABLED" && aws_batch_job_queue.this["default"].priority == 1
    error_message = "Job queue must default to ENABLED and use the configured priority."
  }

  assert {
    condition     = aws_batch_job_queue.this["default"].scheduling_policy_arn == aws_batch_scheduling_policy.this[0].arn
    error_message = "Job queue must use the module-created scheduling policy when create_scheduling_policy is true."
  }

  assert {
    condition     = aws_batch_job_queue.this["default"].compute_environment_order[0].compute_environment == aws_batch_compute_environment.this["fargate"].arn
    error_message = "Job queue must resolve a compute environment key to the module-created compute environment ARN."
  }

  assert {
    condition     = aws_batch_job_queue.this["default"].compute_environment_order[0].order == 0
    error_message = "Compute environment order must follow the list index."
  }

  assert {
    condition     = aws_batch_job_queue.this["default"].tags["Name"] == "core-prod-etl-default"
    error_message = "Job queue Name tag must be overridden with <rendered_name>-<key>."
  }

  # Job definition
  assert {
    condition     = aws_batch_job_definition.this["sync"].name == "core-prod-etl-sync"
    error_message = "Job definition name must be <rendered_name>-<key>."
  }

  assert {
    condition     = toset(aws_batch_job_definition.this["sync"].platform_capabilities) == toset(["FARGATE"])
    error_message = "Job definition platform capabilities must default to FARGATE."
  }

  assert {
    condition     = length(aws_batch_job_definition.this["sync"].retry_strategy) == 0 && length(aws_batch_job_definition.this["sync"].timeout) == 0
    error_message = "No retry strategy or timeout should be rendered unless configured."
  }

  assert {
    condition     = jsondecode(aws_batch_job_definition.this["sync"].container_properties).executionRoleArn == aws_iam_role.ecs_execution_role.arn
    error_message = "Job definition must inject the module ECS execution role ARN."
  }

  assert {
    condition     = jsondecode(aws_batch_job_definition.this["sync"].container_properties).jobRoleArn == aws_iam_role.ecs_job_role.arn
    error_message = "Job definition must inject the module ECS job role ARN."
  }

  assert {
    condition     = jsondecode(aws_batch_job_definition.this["sync"].container_properties).image == "123456789012.dkr.ecr.us-west-2.amazonaws.com/etl-sync:v1.0.0"
    error_message = "Caller container properties must be preserved in the job definition."
  }

  assert {
    condition = jsondecode(aws_batch_job_definition.this["sync"].container_properties).logConfiguration == {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/aws/batch/core-prod-etl"
        "awslogs-region"        = "us-west-2"
        "awslogs-stream-prefix" = "sync"
      }
    }
    error_message = "Job definition must ship logs to the module KMS-encrypted log group with the awslogs driver."
  }

  assert {
    condition     = aws_batch_job_definition.this["sync"].tags["Name"] == "core-prod-etl-sync"
    error_message = "Job definition Name tag must be overridden with <rendered_name>-<key>."
  }

  # EventBridge
  assert {
    condition     = aws_cloudwatch_event_rule.this["nightly"].name == "core-prod-etl-nightly"
    error_message = "EventBridge rule name must be <rendered_name>-<key>."
  }

  assert {
    condition     = aws_cloudwatch_event_rule.this["nightly"].state == "ENABLED"
    error_message = "EventBridge rule state must default to ENABLED."
  }

  assert {
    condition     = aws_cloudwatch_event_rule.this["nightly"].schedule_expression == "cron(0 2 * * ? *)"
    error_message = "EventBridge rule schedule expression did not flow through."
  }

  assert {
    condition     = aws_cloudwatch_event_rule.this["nightly"].tags["Name"] == "core-prod-etl-nightly"
    error_message = "EventBridge rule Name tag must be overridden with <rendered_name>-<key>."
  }

  assert {
    condition     = aws_cloudwatch_event_target.this["nightly_sync"].rule == aws_cloudwatch_event_rule.this["nightly"].name
    error_message = "EventBridge target must attach to the rule named by rule_name."
  }

  assert {
    condition     = aws_cloudwatch_event_target.this["nightly_sync"].arn == aws_batch_job_queue.this["default"].arn
    error_message = "EventBridge target must resolve a job queue key to the module-created queue ARN."
  }

  assert {
    condition     = aws_cloudwatch_event_target.this["nightly_sync"].batch_target[0].job_definition == aws_batch_job_definition.this["sync"].arn
    error_message = "EventBridge target must resolve a job definition key to the module-created job definition ARN."
  }

  assert {
    condition     = aws_cloudwatch_event_target.this["nightly_sync"].batch_target[0].job_name == "nightly-sync"
    error_message = "EventBridge target job name did not flow through."
  }

  assert {
    condition     = aws_cloudwatch_event_target.this["nightly_sync"].role_arn == aws_iam_role.eventbridge_batch.arn
    error_message = "EventBridge target must use the module EventBridge role."
  }

  assert {
    condition = (
      length(aws_cloudwatch_event_target.this["nightly_sync"].dead_letter_config) == 0 &&
      length(aws_cloudwatch_event_target.this["nightly_sync"].retry_policy) == 0
    )
    error_message = "No dead letter or retry policy block should be rendered unless configured."
  }

  # Outputs
  assert {
    condition     = output.job_queue_arns == { default = aws_batch_job_queue.this["default"].arn }
    error_message = "job_queue_arns output must map queue keys to queue ARNs."
  }

  assert {
    condition     = output.job_definition_arns == { sync = aws_batch_job_definition.this["sync"].arn }
    error_message = "job_definition_arns output must map job definition keys to job definition ARNs."
  }

  assert {
    condition     = output.eventbridge_role_arn == aws_iam_role.eventbridge_batch.arn
    error_message = "eventbridge_role_arn output must expose the EventBridge role ARN."
  }
}

# ------------------------------------------------------------------------------
# Parameter overrides
# ------------------------------------------------------------------------------
run "verify_optional_inputs_flow_through" {
  command   = apply
  state_key = "verify_optional_inputs_flow_through"

  variables {
    create_scheduling_policy = true
    scheduling_policy_name   = "core-prod-fair-share"
    scheduling_policy_fair_share_policy = {
      share_decay_seconds = 3600
      share_distribution = [
        {
          share_identifier = "high"
          weight_factor    = 1
        }
      ]
    }

    compute_environments = {
      spot = {
        state            = "DISABLED"
        service_role_arn = "arn:aws:iam::123456789012:role/aws-service-role/batch.amazonaws.com/AWSServiceRoleForBatch"
        compute_resources = {
          type               = "FARGATE_SPOT"
          max_vcpus          = 64
          security_group_ids = ["sg-0123456789abcdef0"]
          subnets            = ["subnet-0123456789abcdef0"]
        }
      }
    }

    job_queues = {
      external = {
        state                 = "DISABLED"
        priority              = 5
        scheduling_policy_arn = "arn:aws:batch:us-west-2:123456789012:scheduling-policy/external"
        compute_environments  = ["arn:aws:batch:us-west-2:123456789012:compute-environment/external"]
      }
    }

    job_definitions = {
      report = {
        type                  = "container"
        platform_capabilities = ["EC2"]
        parameters = {
          mode = "full"
        }
        retry_strategy = {
          attempts = 3
          evaluate_on_exit = [
            {
              action       = "RETRY"
              on_exit_code = "1"
            }
          ]
        }
        timeout = {
          attempt_duration_seconds = 3600
        }
      }
    }

    custom_ecs_execution_policies = ["arn:aws:iam::123456789012:policy/core-prod-ecr-pull"]
    custom_ecs_job_role_policies  = ["arn:aws:iam::123456789012:policy/core-prod-s3-read", "arn:aws:iam::123456789012:policy/core-prod-ssm-read"]
    custom_eventbridge_policies   = ["arn:aws:iam::123456789012:policy/core-prod-eb-extra"]

    eventbridge_rules = {
      on_upload = {
        description   = "Run the report when a file lands."
        event_pattern = "{\"source\":[\"aws.s3\"]}"
        state         = "DISABLED"
        tags = {
          Trigger = "s3"
        }
      }
    }

    eventbridge_targets = {
      report = {
        rule_name           = "on_upload"
        job_queue_key       = "arn:aws:batch:us-west-2:123456789012:job-queue/external"
        job_definition_key  = "arn:aws:batch:us-west-2:123456789012:job-definition/external:1"
        job_name            = "report"
        attempts            = 2
        container_overrides = "{\"ContainerOverrides\":{\"Command\":[\"run\"]}}"
        dead_letter_arn     = "arn:aws:sqs:us-west-2:123456789012:core-prod-etl-dlq"
        retry_policy = {
          maximum_event_age_in_seconds = 600
          maximum_retry_attempts       = 4
        }
      }
    }
  }

  assert {
    condition     = aws_batch_scheduling_policy.this[0].name == "core-prod-fair-share"
    error_message = "scheduling_policy_name must override the rendered scheduling policy name."
  }

  assert {
    condition     = aws_batch_scheduling_policy.this[0].fair_share_policy[0].share_decay_seconds == 3600
    error_message = "Fair share decay seconds did not flow through."
  }

  assert {
    condition     = one(aws_batch_scheduling_policy.this[0].fair_share_policy[0].share_distribution).share_identifier == "high"
    error_message = "Fair share distribution did not flow through."
  }

  assert {
    condition     = aws_batch_compute_environment.this["spot"].state == "DISABLED"
    error_message = "Compute environment state override did not flow through."
  }

  assert {
    condition     = aws_batch_compute_environment.this["spot"].service_role == "arn:aws:iam::123456789012:role/aws-service-role/batch.amazonaws.com/AWSServiceRoleForBatch"
    error_message = "Compute environment service role did not flow through."
  }

  assert {
    condition     = aws_batch_compute_environment.this["spot"].compute_resources[0].type == "FARGATE_SPOT" && aws_batch_compute_environment.this["spot"].compute_resources[0].max_vcpus == 64
    error_message = "Compute resources type and max_vcpus overrides did not flow through."
  }

  assert {
    condition     = aws_batch_job_queue.this["external"].state == "DISABLED" && aws_batch_job_queue.this["external"].priority == 5
    error_message = "Job queue state and priority overrides did not flow through."
  }

  assert {
    condition     = aws_batch_job_queue.this["external"].scheduling_policy_arn == "arn:aws:batch:us-west-2:123456789012:scheduling-policy/external"
    error_message = "An explicit queue scheduling_policy_arn must win over the module-created policy."
  }

  assert {
    condition     = aws_batch_job_queue.this["external"].compute_environment_order[0].compute_environment == "arn:aws:batch:us-west-2:123456789012:compute-environment/external"
    error_message = "A compute environment value that is not a module key must pass through as a direct ARN."
  }

  assert {
    condition     = toset(aws_batch_job_definition.this["report"].platform_capabilities) == toset(["EC2"])
    error_message = "Job definition platform capabilities override did not flow through."
  }

  assert {
    condition     = aws_batch_job_definition.this["report"].parameters["mode"] == "full"
    error_message = "Job definition parameters did not flow through."
  }

  assert {
    condition     = aws_batch_job_definition.this["report"].retry_strategy[0].attempts == 3
    error_message = "Job definition retry attempts did not flow through."
  }

  assert {
    condition     = aws_batch_job_definition.this["report"].retry_strategy[0].evaluate_on_exit[0].action == "RETRY" && aws_batch_job_definition.this["report"].retry_strategy[0].evaluate_on_exit[0].on_exit_code == "1"
    error_message = "Job definition evaluate_on_exit rules did not flow through."
  }

  assert {
    condition     = aws_batch_job_definition.this["report"].timeout[0].attempt_duration_seconds == 3600
    error_message = "Job definition timeout did not flow through."
  }

  assert {
    condition     = !can(jsondecode(aws_batch_job_definition.this["report"].container_properties).logConfiguration)
    error_message = "No logConfiguration should be injected when cloudwatch_logs is null."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.ecs_execution_custom["0"].policy_arn == "arn:aws:iam::123456789012:policy/core-prod-ecr-pull"
    error_message = "Custom ECS execution policies must be attached to the execution role."
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.ecs_job_custom) == 2 && aws_iam_role_policy_attachment.ecs_job_custom["1"].policy_arn == "arn:aws:iam::123456789012:policy/core-prod-ssm-read"
    error_message = "Custom ECS job role policies must be attached to the job role."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.ecs_job_custom["0"].role == aws_iam_role.ecs_job_role.name
    error_message = "Custom ECS job role policies must target the job role."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.eventbridge_batch_custom["0"].role == aws_iam_role.eventbridge_batch.name
    error_message = "Custom EventBridge policies must be attached to the EventBridge role."
  }

  assert {
    condition     = aws_cloudwatch_event_rule.this["on_upload"].state == "DISABLED" && aws_cloudwatch_event_rule.this["on_upload"].event_pattern == "{\"source\":[\"aws.s3\"]}"
    error_message = "EventBridge rule state and event pattern overrides did not flow through."
  }

  assert {
    condition     = aws_cloudwatch_event_rule.this["on_upload"].description == "Run the report when a file lands."
    error_message = "EventBridge rule description did not flow through."
  }

  assert {
    condition     = aws_cloudwatch_event_rule.this["on_upload"].tags["Trigger"] == "s3" && aws_cloudwatch_event_rule.this["on_upload"].tags["Name"] == "core-prod-etl-on_upload"
    error_message = "EventBridge rule must merge per-rule tags with the Name override."
  }

  assert {
    condition     = aws_cloudwatch_event_target.this["report"].arn == "arn:aws:batch:us-west-2:123456789012:job-queue/external"
    error_message = "A job_queue_key that is not a module key must pass through as a direct ARN."
  }

  assert {
    condition     = aws_cloudwatch_event_target.this["report"].batch_target[0].job_definition == "arn:aws:batch:us-west-2:123456789012:job-definition/external:1"
    error_message = "A job_definition_key that is not a module key must pass through as a direct ARN."
  }

  assert {
    condition     = aws_cloudwatch_event_target.this["report"].batch_target[0].job_attempts == 2
    error_message = "EventBridge target attempts did not flow through."
  }

  assert {
    condition     = aws_cloudwatch_event_target.this["report"].input == "{\"ContainerOverrides\":{\"Command\":[\"run\"]}}"
    error_message = "EventBridge target container overrides did not flow through."
  }

  assert {
    condition     = aws_cloudwatch_event_target.this["report"].dead_letter_config[0].arn == "arn:aws:sqs:us-west-2:123456789012:core-prod-etl-dlq"
    error_message = "EventBridge target dead letter ARN did not flow through."
  }

  assert {
    condition = (
      aws_cloudwatch_event_target.this["report"].retry_policy[0].maximum_event_age_in_seconds == 600 &&
      aws_cloudwatch_event_target.this["report"].retry_policy[0].maximum_retry_attempts == 4
    )
    error_message = "EventBridge target retry policy did not flow through."
  }
}

# ------------------------------------------------------------------------------
# Validation
# ------------------------------------------------------------------------------
run "verify_invalid_environment_fails" {
  command = plan

  variables {
    environment = "INVALID_UPPERCASE"
  }

  expect_failures = [var.environment]
}
