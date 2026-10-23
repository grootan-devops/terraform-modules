mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      name   = "us-west-2"
      region = "us-west-2"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:user/terraform"
      user_id    = "AIDAEXAMPLEUSERID0001"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition          = "aws"
      dns_suffix         = "amazonaws.com"
      reverse_dns_prefix = "com.amazonaws"
    }
  }

  # The provider validates policy arguments as JSON, so every policy document
  # needs a JSON-shaped mock. Assertions inspect the configured statements.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json          = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"sts:AssumeRole\",\"Principal\":{\"Service\":\"lambda.amazonaws.com\"}}]}"
      minified_json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"sts:AssumeRole\",\"Principal\":{\"Service\":\"lambda.amazonaws.com\"}}]}"
    }
  }

  # The provider validates ARN-typed arguments, so computed ARNs that feed
  # other resources need ARN-shaped mock values.
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/core-prod-api-execution-role"
    }
  }

  mock_resource "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/core-prod-api-execution-policy"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-west-2:123456789012:log-group:/aws/lambda/core-prod-api"
    }
  }

  mock_resource "aws_lambda_function" {
    defaults = {
      arn           = "arn:aws:lambda:us-west-2:123456789012:function:core-prod-api"
      qualified_arn = "arn:aws:lambda:us-west-2:123456789012:function:core-prod-api:1"
      invoke_arn    = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:core-prod-api/invocations"
      version       = "1"
    }
  }

  mock_resource "aws_lambda_alias" {
    defaults = {
      arn        = "arn:aws:lambda:us-west-2:123456789012:function:core-prod-api:live"
      invoke_arn = "arn:aws:apigateway:us-west-2:lambda:path/2015-03-31/functions/arn:aws:lambda:us-west-2:123456789012:function:core-prod-api:live/invocations"
    }
  }
}

mock_provider "archive" {}

variables {
  application = "core"
  environment = "prod"
  name        = "api"
  runtime     = "nodejs22.x"
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
}

# ------------------------------------------------------------------------------
# Naming
# ------------------------------------------------------------------------------
run "verify_rendered_names" {
  command = plan

  assert {
    condition     = aws_lambda_function.this.function_name == "core-prod-api"
    error_message = "Lambda function name did not match <application>-<environment>-<name>."
  }

  assert {
    condition     = aws_lambda_function.this.description == "Lambda function for core-prod-api"
    error_message = "Lambda function description did not use the rendered name."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/aws/lambda/core-prod-api"
    error_message = "Log group name did not match /aws/lambda/<rendered name>."
  }

  assert {
    condition     = aws_iam_role.this.name == "core-prod-api-execution-role"
    error_message = "Execution role name did not match <rendered name>-execution-role."
  }

  assert {
    condition     = aws_iam_policy.this.name == "core-prod-api-execution-policy"
    error_message = "Execution policy name did not match <rendered name>-execution-policy."
  }

  assert {
    condition     = output.function_name == "core-prod-api"
    error_message = "function_name output did not return the rendered name."
  }
}

run "verify_name_fallback_when_null" {
  command = plan

  variables {
    name = null
  }

  assert {
    condition     = aws_lambda_function.this.function_name == "core-prod"
    error_message = "Lambda function name did not fall back to <application>-<environment> when name is null."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/aws/lambda/core-prod"
    error_message = "Log group name did not use the fallback rendered name when name is null."
  }

  assert {
    condition     = aws_iam_role.this.name == "core-prod-execution-role"
    error_message = "Execution role name did not use the fallback rendered name when name is null."
  }
}

run "verify_name_fallback_when_empty" {
  command = plan

  variables {
    name = ""
  }

  assert {
    condition     = aws_lambda_function.this.function_name == "core-prod"
    error_message = "Lambda function name did not fall back to <application>-<environment> when name is empty."
  }

  assert {
    condition     = aws_iam_policy.this.name == "core-prod-execution-policy"
    error_message = "Execution policy name did not use the fallback rendered name when name is empty."
  }
}

# ------------------------------------------------------------------------------
# Tags
# ------------------------------------------------------------------------------
run "verify_governance_and_caller_tags" {
  command = plan

  variables {
    tags = {
      CostCenter = "platform"
      Owner      = "team-core"
    }
  }

  assert {
    condition = alltrue([
      for tags in [
        aws_lambda_function.this.tags,
        aws_cloudwatch_log_group.this.tags,
        aws_iam_role.this.tags,
        aws_iam_policy.this.tags,
        ] : (
        tags["Application"] == "core" &&
        tags["Environment"] == "prod" &&
        tags["Name"] == "core-prod-api"
      )
    ])
    error_message = "Application, Environment and Name governance tags were not set on every taggable resource."
  }

  assert {
    condition = alltrue([
      for tags in [
        aws_lambda_function.this.tags,
        aws_cloudwatch_log_group.this.tags,
        aws_iam_role.this.tags,
        aws_iam_policy.this.tags,
        ] : (
        tags["CostCenter"] == "platform" &&
        tags["Owner"] == "team-core"
      )
    ])
    error_message = "Caller tags from var.tags were not preserved on every taggable resource."
  }
}

run "verify_optional_resource_tags" {
  command = plan

  variables {
    tags = {
      CostCenter = "platform"
    }
    create_deployer_role            = true
    deployer_principal_arn_patterns = ["arn:aws:iam::123456789012:role/ci-deployer"]
    artifact_bucket_arn             = "arn:aws:s3:::core-prod-artifacts"
    sqs_event_sources = {
      orders = {
        arn = "arn:aws:sqs:us-west-2:123456789012:core-prod-orders"
      }
    }
  }

  assert {
    condition = alltrue([
      for tags in [
        aws_iam_role.deployer[0].tags,
        aws_iam_policy.deployer[0].tags,
        aws_lambda_event_source_mapping.sqs["orders"].tags,
        ] : (
        tags["Application"] == "core" &&
        tags["Environment"] == "prod" &&
        tags["Name"] == "core-prod-api" &&
        tags["CostCenter"] == "platform"
      )
    ])
    error_message = "Deployer role, deployer policy and SQS event source mapping did not carry governance and caller tags."
  }
}

# ------------------------------------------------------------------------------
# Security defaults
# ------------------------------------------------------------------------------
run "verify_kms_encryption_defaults" {
  command = plan

  assert {
    condition     = aws_lambda_function.this.kms_key_arn == var.kms_key_arn
    error_message = "Lambda environment variables were not encrypted with kms_key_arn."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.kms_key_id == var.kms_key_arn
    error_message = "Lambda log group was not encrypted with kms_key_arn by default."
  }

  assert {
    condition     = aws_lambda_function.this.source_kms_key_arn == null
    error_message = "source_kms_key_arn should be unset by default."
  }
}

run "verify_log_group_kms_override" {
  command = plan

  variables {
    cloudwatch_logs = {
      kms_key_id = "arn:aws:kms:us-west-2:123456789012:key/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    }
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.kms_key_id == "arn:aws:kms:us-west-2:123456789012:key/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    error_message = "cloudwatch_logs.kms_key_id did not override the log group KMS key."
  }

  assert {
    condition     = aws_lambda_function.this.kms_key_arn == var.kms_key_arn
    error_message = "Overriding the log group key must not change the function KMS key."
  }
}

run "verify_logging_defaults" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 14
    error_message = "Log group retention did not default to 14 days."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.deletion_protection_enabled == true
    error_message = "Log group deletion protection was not enabled by default."
  }

  assert {
    condition     = aws_lambda_function.this.logging_config[0].log_format == "JSON"
    error_message = "Lambda logging_config did not use the JSON log format."
  }

  assert {
    condition     = aws_lambda_function.this.logging_config[0].log_group == "/aws/lambda/core-prod-api"
    error_message = "Lambda logging_config was not wired to the managed log group."
  }

  assert {
    condition = (
      aws_lambda_function.this.logging_config[0].application_log_level == "INFO" &&
      aws_lambda_function.this.logging_config[0].system_log_level == "INFO"
    )
    error_message = "Lambda application and system log levels did not default to INFO."
  }
}

run "verify_runtime_guardrails" {
  command = plan

  assert {
    condition     = aws_lambda_function_recursion_config.this.recursive_loop == "Terminate"
    error_message = "Recursive loop detection was not set to Terminate."
  }

  assert {
    condition     = aws_lambda_function.this.tracing_config[0].mode == "PassThrough"
    error_message = "Tracing mode did not default to PassThrough."
  }

  assert {
    condition     = aws_lambda_function.this.publish == true
    error_message = "Lambda function should publish a version on every change."
  }

  assert {
    condition     = length(aws_lambda_function.this.vpc_config) == 0
    error_message = "vpc_config should be absent by default."
  }
}

run "verify_execution_role_least_privilege" {
  command = apply

  # Applied runs get their own state so later plan runs start from an empty
  # state; the function ignores changes to its package and tags after create.
  state_key = "verify_execution_role_least_privilege"

  assert {
    condition = (
      toset(one(data.aws_iam_policy_document.assume_role.statement).actions) == toset(["sts:AssumeRole"]) &&
      one(one(data.aws_iam_policy_document.assume_role.statement).principals).type == "Service" &&
      toset(one(one(data.aws_iam_policy_document.assume_role.statement).principals).identifiers) == toset(["lambda.amazonaws.com"])
    )
    error_message = "Execution role trust policy must allow only lambda.amazonaws.com to sts:AssumeRole."
  }

  assert {
    condition     = aws_iam_role.this.assume_role_policy == data.aws_iam_policy_document.assume_role.json
    error_message = "Execution role was not wired to the assume_role policy document."
  }

  assert {
    condition     = [for s in data.aws_iam_policy_document.this.statement : s.sid] == ["CloudWatchLogs"]
    error_message = "Default execution policy must contain only the CloudWatchLogs statement."
  }

  assert {
    condition = (
      toset(one(data.aws_iam_policy_document.this.statement).actions) == toset(["logs:CreateLogStream", "logs:PutLogEvents"]) &&
      toset(one(data.aws_iam_policy_document.this.statement).resources) == toset(["arn:aws:logs:us-west-2:123456789012:log-group:/aws/lambda/core-prod-api:*"])
    )
    error_message = "CloudWatchLogs statement must be scoped to the function's own log group."
  }

  assert {
    condition     = aws_iam_policy.this.policy == data.aws_iam_policy_document.this.json
    error_message = "Execution policy was not built from the execution policy document."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.this.policy_arn == aws_iam_policy.this.arn && aws_iam_role_policy_attachment.this.role == aws_iam_role.this.name
    error_message = "Execution policy was not attached to the execution role."
  }

  assert {
    condition     = aws_lambda_function.this.role == aws_iam_role.this.arn
    error_message = "Lambda function was not wired to the managed execution role."
  }

  assert {
    condition     = output.role_arn == aws_iam_role.this.arn && output.role_name == "core-prod-api-execution-role"
    error_message = "role_arn and role_name outputs did not return the execution role."
  }
}

run "verify_scoped_permissions_for_enabled_features" {
  command = apply

  # Applied runs get their own state so later plan runs start from an empty
  # state; the function ignores changes to its package and tags after create.
  state_key = "verify_scoped_permissions_for_enabled_features"

  variables {
    secret_arns                   = ["arn:aws:secretsmanager:us-west-2:123456789012:secret:core-prod-db-AbCdEf"]
    dead_letter_config_target_arn = "arn:aws:sqs:us-west-2:123456789012:core-prod-api-dlq"
    sqs_event_sources = {
      orders = {
        arn = "arn:aws:sqs:us-west-2:123456789012:core-prod-orders"
      }
    }
    async_invoke_config = {
      on_failure_destination_arn = "arn:aws:sqs:us-west-2:123456789012:core-prod-api-failures"
    }
  }

  assert {
    condition = toset([for s in data.aws_iam_policy_document.this.statement : s.sid]) == toset([
      "CloudWatchLogs",
      "ReadSecrets",
      "DecryptSecrets",
      "DeadLetterConfig",
      "SQSEventSourceMapping",
      "AsyncInvokeConfigDestinations",
    ])
    error_message = "Enabled features did not add exactly their matching execution policy statements."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.this.statement :
      toset(s.actions) == toset(["secretsmanager:GetSecretValue"]) &&
      toset(s.resources) == toset(["arn:aws:secretsmanager:us-west-2:123456789012:secret:core-prod-db-AbCdEf"])
      if s.sid == "ReadSecrets"
    ])
    error_message = "ReadSecrets statement must grant only GetSecretValue on the listed secrets."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.this.statement :
      toset(s.actions) == toset(["kms:Decrypt"]) && toset(s.resources) == toset([var.kms_key_arn])
      if s.sid == "DecryptSecrets"
    ])
    error_message = "DecryptSecrets statement must grant only kms:Decrypt on kms_key_arn."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.this.statement :
      toset(s.resources) == toset(["arn:aws:sqs:us-west-2:123456789012:core-prod-api-dlq"])
      if s.sid == "DeadLetterConfig"
    ])
    error_message = "DeadLetterConfig statement must be scoped to the dead letter target."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.this.statement :
      toset(s.actions) == toset(["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]) &&
      toset(s.resources) == toset(["arn:aws:sqs:us-west-2:123456789012:core-prod-orders"])
      if s.sid == "SQSEventSourceMapping"
    ])
    error_message = "SQSEventSourceMapping statement must be scoped to the configured queues."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.this.statement :
      toset(s.resources) == toset(["arn:aws:sqs:us-west-2:123456789012:core-prod-api-failures"])
      if s.sid == "AsyncInvokeConfigDestinations"
    ])
    error_message = "AsyncInvokeConfigDestinations statement must be scoped to the configured destinations."
  }
}

# ------------------------------------------------------------------------------
# Parameters: shipped defaults
# ------------------------------------------------------------------------------
run "verify_function_defaults" {
  command = plan

  assert {
    condition     = aws_lambda_function.this.package_type == "Zip"
    error_message = "package_type did not default to Zip."
  }

  assert {
    condition     = aws_lambda_function.this.runtime == "nodejs22.x"
    error_message = "Runtime was not passed through to the function."
  }

  assert {
    condition     = aws_lambda_function.this.architectures == tolist(["x86_64"])
    error_message = "Architectures did not default to x86_64."
  }

  assert {
    condition     = aws_lambda_function.this.memory_size == 128
    error_message = "memory_size did not default to 128 MB."
  }

  assert {
    condition     = aws_lambda_function.this.timeout == 60
    error_message = "timeout did not default to 60 seconds."
  }

  assert {
    condition     = aws_lambda_function.this.reserved_concurrent_executions == -1
    error_message = "reserved_concurrent_executions did not default to -1 (unreserved)."
  }

  assert {
    condition     = aws_lambda_function.this.ephemeral_storage[0].size == 512
    error_message = "Ephemeral storage was not set to 512 MB."
  }

  assert {
    condition     = aws_lambda_alias.this.name == "live"
    error_message = "Release alias did not default to live."
  }

  assert {
    condition     = aws_lambda_alias.this.function_name == "core-prod-api"
    error_message = "Release alias was not attached to the managed function."
  }

  assert {
    condition = (
      length(aws_lambda_runtime_management_config.this) == 1 &&
      aws_lambda_runtime_management_config.this[0].update_runtime_on == "Auto" &&
      aws_lambda_runtime_management_config.this[0].qualifier == "$LATEST"
    )
    error_message = "Runtime management config did not default to Auto on $LATEST for Zip packages."
  }

  assert {
    condition     = length(aws_lambda_function.this.layers) == 0
    error_message = "No layers should be attached by default."
  }
}

run "verify_generated_bootstrap_package_nodejs" {
  command = plan

  assert {
    condition     = length(data.archive_file.bootstrap) == 1
    error_message = "A bootstrap package should be generated when no filename or S3 package is supplied."
  }

  assert {
    condition     = endswith(data.archive_file.bootstrap[0].output_path, "/.terraform/core-prod-api-bootstrap.zip")
    error_message = "Bootstrap archive output path did not use the rendered name."
  }

  assert {
    condition     = aws_lambda_function.this.filename == data.archive_file.bootstrap[0].output_path
    error_message = "Lambda function was not deployed from the generated bootstrap archive."
  }

  assert {
    condition     = aws_lambda_function.this.handler == "index.handler"
    error_message = "Handler did not default to index.handler for the nodejs runtime."
  }

  assert {
    condition = (
      one(data.archive_file.bootstrap[0].source).filename == "index.js" &&
      strcontains(one(data.archive_file.bootstrap[0].source).content, "Code not deployed") &&
      strcontains(one(data.archive_file.bootstrap[0].source).content, "statusCode: 200")
    )
    error_message = "Node.js bootstrap source did not return the default message and status code."
  }
}

run "verify_generated_bootstrap_package_python" {
  command = plan

  variables {
    runtime               = "python3.12"
    bootstrap_message     = "Awaiting first deploy"
    bootstrap_status_code = 503
  }

  assert {
    condition     = aws_lambda_function.this.handler == "lambda_function.handler"
    error_message = "Handler did not default to lambda_function.handler for the python runtime."
  }

  assert {
    condition = (
      one(data.archive_file.bootstrap[0].source).filename == "lambda_function.py" &&
      strcontains(one(data.archive_file.bootstrap[0].source).content, "Awaiting first deploy") &&
      strcontains(one(data.archive_file.bootstrap[0].source).content, "\"statusCode\": 503")
    )
    error_message = "Python bootstrap source did not use bootstrap_message and bootstrap_status_code."
  }
}

run "verify_optional_features_disabled_by_default" {
  command = plan

  assert {
    condition     = length(aws_lambda_provisioned_concurrency_config.this) == 0
    error_message = "Provisioned concurrency should be off by default."
  }

  assert {
    condition     = length(aws_lambda_function_event_invoke_config.this) == 0
    error_message = "Async invoke config should be off by default."
  }

  assert {
    condition     = length(aws_lambda_event_source_mapping.sqs) == 0
    error_message = "No SQS event source mappings should be created by default."
  }

  assert {
    condition = (
      length(aws_iam_role.deployer) == 0 &&
      length(aws_iam_policy.deployer) == 0 &&
      length(aws_iam_role_policy_attachment.deployer) == 0
    )
    error_message = "Deployer role, policy and attachment should be off by default."
  }

  assert {
    condition = (
      length(aws_iam_role_policy_attachment.custom) == 0 &&
      length(aws_iam_role_policy_attachment.application_signals) == 0 &&
      length(aws_iam_role_policy_attachment.lambda_insights) == 0 &&
      length(aws_iam_role_policy_attachment.xray) == 0
    )
    error_message = "No managed or custom policies should be attached to the execution role by default."
  }

  assert {
    condition = (
      length(aws_lambda_function.this.dead_letter_config) == 0 &&
      length(aws_lambda_function.this.environment) == 0 &&
      length(aws_lambda_function.this.durable_config) == 0
    )
    error_message = "Dead letter, environment and durable config blocks should be absent by default."
  }
}

# ------------------------------------------------------------------------------
# Parameters: overrides flow through
# ------------------------------------------------------------------------------
run "verify_function_overrides" {
  command = plan

  variables {
    runtime                        = "python3.12"
    handler                        = "app.main.handler"
    architectures                  = ["arm64"]
    memory_size                    = 1024
    timeout                        = 30
    reserved_concurrent_executions = 10
    alias_name                     = "stable"
    runtime_management_config      = "FunctionUpdate"
    source_kms_key_arn             = "arn:aws:kms:us-west-2:123456789012:key/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    additional_layers              = ["arn:aws:lambda:us-west-2:123456789012:layer:core-shared:3"]
    environment_variables = {
      LOG_LEVEL = "DEBUG"
    }
    dead_letter_config_target_arn = "arn:aws:sqs:us-west-2:123456789012:core-prod-api-dlq"
    durable_config = {
      execution_timeout = 900
      retention_period  = 7
    }
    cloudwatch_logs = {
      retention_in_days           = 90
      deletion_protection_enabled = false
    }
  }

  assert {
    condition     = aws_lambda_function.this.handler == "app.main.handler"
    error_message = "Custom handler was not passed through."
  }

  assert {
    condition     = aws_lambda_function.this.architectures == tolist(["arm64"])
    error_message = "Architectures override was not passed through."
  }

  assert {
    condition     = aws_lambda_function.this.memory_size == 1024 && aws_lambda_function.this.timeout == 30
    error_message = "memory_size and timeout overrides were not passed through."
  }

  assert {
    condition     = aws_lambda_function.this.reserved_concurrent_executions == 10
    error_message = "reserved_concurrent_executions override was not passed through."
  }

  assert {
    condition     = aws_lambda_alias.this.name == "stable"
    error_message = "alias_name override was not passed through."
  }

  assert {
    condition     = aws_lambda_runtime_management_config.this[0].update_runtime_on == "FunctionUpdate"
    error_message = "runtime_management_config override was not passed through."
  }

  assert {
    condition     = aws_lambda_function.this.source_kms_key_arn == "arn:aws:kms:us-west-2:123456789012:key/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    error_message = "source_kms_key_arn override was not passed through."
  }

  assert {
    condition     = aws_lambda_function.this.layers == tolist(["arn:aws:lambda:us-west-2:123456789012:layer:core-shared:3"])
    error_message = "additional_layers were not attached to the function."
  }

  assert {
    condition     = aws_lambda_function.this.environment[0].variables == tomap({ LOG_LEVEL = "DEBUG" })
    error_message = "environment_variables were not passed through."
  }

  assert {
    condition     = aws_lambda_function.this.dead_letter_config[0].target_arn == "arn:aws:sqs:us-west-2:123456789012:core-prod-api-dlq"
    error_message = "dead_letter_config_target_arn was not passed through."
  }

  assert {
    condition = (
      aws_lambda_function.this.durable_config[0].execution_timeout == 900 &&
      aws_lambda_function.this.durable_config[0].retention_period == 7
    )
    error_message = "durable_config was not passed through."
  }

  assert {
    condition = (
      aws_cloudwatch_log_group.this.retention_in_days == 90 &&
      aws_cloudwatch_log_group.this.deletion_protection_enabled == false
    )
    error_message = "cloudwatch_logs overrides were not passed through to the log group."
  }
}

run "verify_s3_package_source" {
  command = plan

  variables {
    s3_bucket = "core-prod-artifacts"
    s3_key    = "api/release.zip"
  }

  assert {
    condition = (
      aws_lambda_function.this.s3_bucket == "core-prod-artifacts" &&
      aws_lambda_function.this.s3_key == "api/release.zip" &&
      aws_lambda_function.this.filename == null
    )
    error_message = "S3 package inputs were not used as the function source."
  }

  assert {
    condition     = length(data.archive_file.bootstrap) == 0
    error_message = "No bootstrap package should be generated when an S3 package is supplied."
  }
}

run "verify_local_package_source" {
  command = plan

  variables {
    filename = "build/release.zip"
  }

  assert {
    condition     = aws_lambda_function.this.filename == "build/release.zip"
    error_message = "filename was not used as the function source."
  }

  assert {
    condition     = length(data.archive_file.bootstrap) == 0
    error_message = "No bootstrap package should be generated when filename is supplied."
  }
}

run "verify_image_package" {
  command = plan

  variables {
    package_type = "Image"
    runtime      = null
    image_uri    = "123456789012.dkr.ecr.us-west-2.amazonaws.com/core-api:1.0.0"
  }

  assert {
    condition = (
      aws_lambda_function.this.package_type == "Image" &&
      aws_lambda_function.this.image_uri == "123456789012.dkr.ecr.us-west-2.amazonaws.com/core-api:1.0.0"
    )
    error_message = "Image package type and image_uri were not passed through."
  }

  assert {
    condition = (
      aws_lambda_function.this.runtime == null &&
      aws_lambda_function.this.handler == null &&
      aws_lambda_function.this.filename == null
    )
    error_message = "Runtime, handler and filename must be unset for Image packages."
  }

  assert {
    condition     = length(data.archive_file.bootstrap) == 0 && length(aws_lambda_runtime_management_config.this) == 0
    error_message = "Image packages must not generate a bootstrap archive or runtime management config."
  }
}

run "verify_optional_features_enabled" {
  command = apply

  # Applied runs get their own state so later plan runs start from an empty
  # state; the function ignores changes to its package and tags after create.
  state_key = "verify_optional_features_enabled"

  variables {
    architectures              = ["arm64"]
    provisioned_concurrency    = 5
    tracing_config_mode        = "Active"
    enable_lambda_insights     = true
    enable_application_signals = true
    custom_iam_policies        = ["arn:aws:iam::123456789012:policy/core-prod-extra"]
    vpc_config = {
      subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
      security_group_ids = ["sg-0123456789abcdef0"]
    }
    sqs_event_sources = {
      orders = {
        arn                     = "arn:aws:sqs:us-west-2:123456789012:core-prod-orders"
        filter_criteria_pattern = "{\"body\":{\"type\":[\"order\"]}}"
        kms_key_arn             = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
      }
    }
    async_invoke_config = {
      maximum_retry_attempts     = 1
      on_success_destination_arn = "arn:aws:sqs:us-west-2:123456789012:core-prod-api-success"
      on_failure_destination_arn = "arn:aws:sqs:us-west-2:123456789012:core-prod-api-failures"
    }
  }

  assert {
    condition = (
      length(aws_lambda_provisioned_concurrency_config.this) == 1 &&
      aws_lambda_provisioned_concurrency_config.this[0].provisioned_concurrent_executions == 5 &&
      aws_lambda_provisioned_concurrency_config.this[0].qualifier == "live"
    )
    error_message = "Provisioned concurrency was not applied to the release alias."
  }

  assert {
    condition     = aws_lambda_function.this.tracing_config[0].mode == "Active"
    error_message = "Active tracing was not passed through."
  }

  assert {
    condition = (
      length(aws_iam_role_policy_attachment.xray) == 1 &&
      aws_iam_role_policy_attachment.xray[0].policy_arn == "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
    )
    error_message = "X-Ray write policy was not attached when tracing is Active."
  }

  assert {
    condition     = aws_lambda_function.this.layers == tolist(["arn:aws:lambda:us-west-2:580247275435:layer:LambdaInsightsExtension-Arm64:33"])
    error_message = "Lambda Insights arm64 layer was not attached when enable_lambda_insights is true."
  }

  assert {
    condition = (
      aws_iam_role_policy_attachment.lambda_insights[0].policy_arn == "arn:aws:iam::aws:policy/CloudWatchLambdaInsightsExecutionRolePolicy" &&
      aws_iam_role_policy_attachment.application_signals[0].policy_arn == "arn:aws:iam::aws:policy/CloudWatchLambdaApplicationSignalsExecutionRolePolicy"
    )
    error_message = "Lambda Insights and Application Signals managed policies were not attached."
  }

  assert {
    condition = (
      length(aws_iam_role_policy_attachment.custom) == 1 &&
      aws_iam_role_policy_attachment.custom["0"].policy_arn == "arn:aws:iam::123456789012:policy/core-prod-extra"
    )
    error_message = "custom_iam_policies were not attached to the execution role."
  }

  assert {
    condition = (
      toset(aws_lambda_function.this.vpc_config[0].subnet_ids) == toset(["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]) &&
      toset(aws_lambda_function.this.vpc_config[0].security_group_ids) == toset(["sg-0123456789abcdef0"])
    )
    error_message = "vpc_config was not passed through."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.this.statement :
      toset(s.resources) == toset(["*"]) &&
      toset(s.actions) == toset([
        "ec2:CreateNetworkInterface",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DeleteNetworkInterface",
        "ec2:AssignPrivateIpAddresses",
        "ec2:UnassignPrivateIpAddresses",
      ])
      if s.sid == "VPCAccess"
    ]) && contains([for s in data.aws_iam_policy_document.this.statement : s.sid], "VPCAccess")
    error_message = "VPCAccess statement was not added with only the ENI management actions."
  }

  assert {
    condition     = contains([for s in data.aws_iam_policy_document.this.statement : s.sid], "XRayTracing")
    error_message = "XRayTracing statement was not added when tracing is Active."
  }

  assert {
    condition = (
      aws_lambda_event_source_mapping.sqs["orders"].function_name == aws_lambda_alias.this.arn &&
      aws_lambda_event_source_mapping.sqs["orders"].event_source_arn == "arn:aws:sqs:us-west-2:123456789012:core-prod-orders"
    )
    error_message = "SQS event source mapping must invoke the release alias from the configured queue."
  }

  assert {
    condition = (
      aws_lambda_event_source_mapping.sqs["orders"].batch_size == 10 &&
      aws_lambda_event_source_mapping.sqs["orders"].scaling_config[0].maximum_concurrency == 2 &&
      aws_lambda_event_source_mapping.sqs["orders"].maximum_batching_window_in_seconds == 0 &&
      aws_lambda_event_source_mapping.sqs["orders"].enabled == true
    )
    error_message = "SQS event source mapping defaults (batch 10, concurrency 2, window 0, enabled) were not applied."
  }

  assert {
    condition     = toset(aws_lambda_event_source_mapping.sqs["orders"].function_response_types) == toset(["ReportBatchItemFailures"])
    error_message = "SQS event source mapping must report partial batch failures."
  }

  assert {
    condition = (
      one(aws_lambda_event_source_mapping.sqs["orders"].filter_criteria[0].filter).pattern == "{\"body\":{\"type\":[\"order\"]}}" &&
      aws_lambda_event_source_mapping.sqs["orders"].kms_key_arn == "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
    )
    error_message = "SQS filter pattern and filter KMS key were not passed through."
  }

  assert {
    condition = (
      length(aws_lambda_function_event_invoke_config.this) == 1 &&
      aws_lambda_function_event_invoke_config.this[0].maximum_retry_attempts == 1 &&
      aws_lambda_function_event_invoke_config.this[0].maximum_event_age_in_seconds == 21600 &&
      aws_lambda_function_event_invoke_config.this[0].qualifier == "$LATEST"
    )
    error_message = "Async invoke config retry and event age settings were not applied."
  }

  assert {
    condition = (
      aws_lambda_function_event_invoke_config.this[0].destination_config[0].on_success[0].destination == "arn:aws:sqs:us-west-2:123456789012:core-prod-api-success" &&
      aws_lambda_function_event_invoke_config.this[0].destination_config[0].on_failure[0].destination == "arn:aws:sqs:us-west-2:123456789012:core-prod-api-failures"
    )
    error_message = "Async invoke destinations were not passed through."
  }

  assert {
    condition     = output.alias_arn == aws_lambda_alias.this.arn && output.function_arn == aws_lambda_function.this.arn
    error_message = "alias_arn and function_arn outputs did not return the alias and function ARNs."
  }
}

run "verify_lambda_insights_layer_x86" {
  command = plan

  variables {
    enable_lambda_insights = true
    additional_layers      = ["arn:aws:lambda:us-west-2:123456789012:layer:core-shared:3"]
  }

  assert {
    condition = aws_lambda_function.this.layers == tolist([
      "arn:aws:lambda:us-west-2:123456789012:layer:core-shared:3",
      "arn:aws:lambda:us-west-2:580247275435:layer:LambdaInsightsExtension:33",
    ])
    error_message = "Lambda Insights x86_64 layer was not appended after additional_layers."
  }
}

run "verify_deployer_role" {
  command = apply

  # Applied runs get their own state so later plan runs start from an empty
  # state; the function ignores changes to its package and tags after create.
  state_key = "verify_deployer_role"

  variables {
    create_deployer_role            = true
    deployer_principal_arn_patterns = ["arn:aws:iam::123456789012:role/ci-deployer"]
    artifact_bucket_arn             = "arn:aws:s3:::core-prod-artifacts"
  }

  assert {
    condition = (
      aws_iam_role.deployer[0].name == "core-prod-api-deployer" &&
      aws_iam_policy.deployer[0].name == "core-prod-api-deployer"
    )
    error_message = "Deployer role and policy names did not default to <rendered name>-deployer."
  }

  assert {
    condition = (
      toset(one(one(data.aws_iam_policy_document.deployer_assume_role[0].statement).principals).identifiers) == toset(["arn:aws:iam::123456789012:root"]) &&
      one(one(data.aws_iam_policy_document.deployer_assume_role[0].statement).condition).test == "ArnLike" &&
      one(one(data.aws_iam_policy_document.deployer_assume_role[0].statement).condition).variable == "aws:PrincipalArn" &&
      toset(one(one(data.aws_iam_policy_document.deployer_assume_role[0].statement).condition).values) == toset(["arn:aws:iam::123456789012:role/ci-deployer"])
    )
    error_message = "Deployer trust policy must allow only the account root restricted to deployer_principal_arn_patterns."
  }

  assert {
    condition = toset([for s in data.aws_iam_policy_document.deployer[0].statement : s.sid]) == toset([
      "ReadArtifactBucketLocation",
      "ListFunctionArtifacts",
      "ManageFunctionArtifacts",
      "DeployAndInvokeFunction",
      "UseArtifactKmsKey",
    ])
    error_message = "Deployer policy did not contain exactly the expected statements."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.deployer[0].statement :
      toset(s.resources) == toset(["arn:aws:s3:::core-prod-artifacts/api/*"]) &&
      toset(s.actions) == toset(["s3:GetObject", "s3:PutObject"])
      if s.sid == "ManageFunctionArtifacts"
    ])
    error_message = "Deployer artifact access must be limited to Get/PutObject under the function prefix."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.deployer[0].statement :
      toset(one(s.condition).values) == toset(["api/*"])
      if s.sid == "ListFunctionArtifacts"
    ])
    error_message = "Deployer ListBucket must be conditioned on the function artifact prefix."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.deployer[0].statement :
      toset(s.resources) == toset([
        "arn:aws:lambda:us-west-2:123456789012:function:core-prod-api",
        "arn:aws:lambda:us-west-2:123456789012:function:core-prod-api:*",
      ])
      if s.sid == "DeployAndInvokeFunction"
    ])
    error_message = "Deployer Lambda permissions must be scoped to this function and its versions."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.deployer[0].statement :
      toset(s.resources) == toset([var.kms_key_arn])
      if s.sid == "UseArtifactKmsKey"
    ])
    error_message = "Deployer KMS permissions must be scoped to kms_key_arn."
  }

  assert {
    condition = (
      aws_iam_role_policy_attachment.deployer[0].role == aws_iam_role.deployer[0].name &&
      aws_iam_role_policy_attachment.deployer[0].policy_arn == aws_iam_policy.deployer[0].arn
    )
    error_message = "Deployer policy was not attached to the deployer role."
  }
}

run "verify_deployer_role_overrides" {
  command = plan

  variables {
    create_deployer_role            = true
    deployer_role_name              = "core-prod-api-ci"
    deployer_principal_arn_patterns = ["arn:aws:iam::123456789012:role/ci-*"]
    artifact_bucket_arn             = "arn:aws:s3:::core-prod-artifacts"
    artifact_prefix                 = "services/api"
  }

  assert {
    condition = (
      aws_iam_role.deployer[0].name == "core-prod-api-ci" &&
      aws_iam_policy.deployer[0].name == "core-prod-api-ci"
    )
    error_message = "deployer_role_name override was not applied to the deployer role and policy."
  }

  assert {
    condition = alltrue([
      for s in data.aws_iam_policy_document.deployer[0].statement :
      toset(s.resources) == toset(["arn:aws:s3:::core-prod-artifacts/services/api/*"])
      if s.sid == "ManageFunctionArtifacts"
    ])
    error_message = "artifact_prefix override was not applied to the deployer artifact permissions."
  }
}

# ------------------------------------------------------------------------------
# Preconditions
# ------------------------------------------------------------------------------
run "verify_deployer_requires_principal_patterns" {
  command = plan

  variables {
    create_deployer_role = true
    artifact_bucket_arn  = "arn:aws:s3:::core-prod-artifacts"
  }

  expect_failures = [aws_iam_role.deployer]
}

run "verify_deployer_requires_artifact_bucket" {
  command = plan

  variables {
    create_deployer_role            = true
    deployer_principal_arn_patterns = ["arn:aws:iam::123456789012:role/ci-deployer"]
  }

  expect_failures = [aws_iam_role.deployer]
}

run "verify_incomplete_s3_package_fails" {
  command = plan

  variables {
    s3_bucket = "core-prod-artifacts"
  }

  expect_failures = [aws_lambda_function.this]
}

run "verify_image_without_uri_fails" {
  command = plan

  variables {
    package_type = "Image"
    runtime      = null
  }

  expect_failures = [aws_lambda_function.this]
}

# ------------------------------------------------------------------------------
# Validation
# ------------------------------------------------------------------------------
run "verify_invalid_environment_fails" {
  command = plan

  variables {
    environment = "Prod_1"
  }

  expect_failures = [var.environment]
}

run "verify_invalid_architecture_fails" {
  command = plan

  variables {
    architectures = ["x86_64", "arm64"]
  }

  expect_failures = [var.architectures]
}

run "verify_invalid_package_type_fails" {
  command = plan

  variables {
    package_type = "Jar"
  }

  expect_failures = [var.package_type]
}

run "verify_unsupported_runtime_fails" {
  command = plan

  variables {
    runtime = "nodejs20.x"
  }

  expect_failures = [var.runtime]
}

run "verify_zero_provisioned_concurrency_fails" {
  command = plan

  variables {
    provisioned_concurrency = 0
  }

  expect_failures = [var.provisioned_concurrency]
}

run "verify_too_many_layers_fails" {
  command = plan

  variables {
    additional_layers = [
      "arn:aws:lambda:us-west-2:123456789012:layer:core-one:1",
      "arn:aws:lambda:us-west-2:123456789012:layer:core-two:1",
      "arn:aws:lambda:us-west-2:123456789012:layer:core-three:1",
      "arn:aws:lambda:us-west-2:123456789012:layer:core-four:1",
      "arn:aws:lambda:us-west-2:123456789012:layer:core-five:1",
      "arn:aws:lambda:us-west-2:123456789012:layer:core-six:1",
    ]
  }

  expect_failures = [var.additional_layers]
}

run "verify_invalid_runtime_management_config_fails" {
  command = plan

  variables {
    runtime_management_config = "Manual"
  }

  expect_failures = [var.runtime_management_config]
}
