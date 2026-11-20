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
      arn = "arn:aws:iam::123456789012:role/core-prod-orders-exec-eu-west-1"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    }
  }

  mock_resource "aws_lambda_alias" {
    defaults = {
      arn        = "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-orders:live"
      invoke_arn = "arn:aws:apigateway:eu-west-1:lambda:path/2015-03-31/functions/arn:aws:lambda:eu-west-1:123456789012:function:core-prod-orders:live/invocations"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-west-1:123456789012:log-group:/aws/lambda/core-prod-orders"
    }
  }
}

mock_provider "archive" {
  mock_data "archive_file" {
    defaults = {
      output_path = "placeholder.zip"
    }
  }
}

variables {
  application = "core"
  environment = "prod"
  name        = "orders"
  tags        = { Team = "payments" }
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = aws_lambda_function.this.function_name == "core-prod-orders" && aws_lambda_function.this.runtime == "python3.14" && aws_lambda_function.this.handler == "lambda_function.handler" && aws_lambda_function.this.architectures == tolist(["x86_64"])
    error_message = "Defaults: python3.14 placeholder handler on x86_64, named <application>-<environment>-<name>."
  }

  assert {
    condition     = aws_lambda_function.this.memory_size == 128 && aws_lambda_function.this.timeout == 30 && aws_lambda_function.this.reserved_concurrent_executions == -1 && aws_lambda_function.this.publish
    error_message = "Defaults: 128 MB, 30 s, unreserved concurrency, published versions."
  }

  assert {
    condition     = aws_lambda_function.this.tracing_config[0].mode == "Active" && aws_lambda_function.this.logging_config[0].log_format == "JSON" && aws_lambda_function.this.logging_config[0].log_group == "/aws/lambda/core-prod-orders"
    error_message = "Tracing must be Active and logs JSON into the module log group (Lambda.7)."
  }

  assert {
    condition     = aws_lambda_function.this.kms_key_arn == null && output.kms_key_arn == null && module.log_group.kms_key_arn == null && module.log_group.retention_in_days == 365
    error_message = "No kms input means the AWS managed key; logs keep 365 days."
  }

  assert {
    condition     = length(aws_lambda_function.this.vpc_config) == 0 && length(module.security_group) == 0 && output.security_group_id == null
    error_message = "No subnets means no VPC and no security group."
  }

  assert {
    condition     = aws_lambda_function.this.tags["Name"] == "core-prod-orders" && aws_lambda_function.this.tags["Team"] == "payments" && aws_lambda_function.this.tags["ManagedBy"] == "Terraform"
    error_message = "Caller and governance tags must be applied."
  }

  assert {
    condition     = aws_lambda_alias.this.name == "live" && aws_lambda_function_recursion_config.this.recursive_loop == "Terminate" && length(aws_lambda_runtime_management_config.this) == 0
    error_message = "Alias live, recursion stopped, runtime updates left on Auto."
  }

  assert {
    condition     = length(aws_lambda_event_source_mapping.this) + length(aws_lambda_permission.this) + length(aws_lambda_function_url.this) + length(aws_lambda_function_event_invoke_config.this) + length(aws_lambda_provisioned_concurrency_config.this) == 0
    error_message = "No trigger, URL, async config or provisioned concurrency by default."
  }
}

run "execution_role" {
  command = plan

  assert {
    condition     = module.role[0].name == "core-prod-orders-exec-eu-west-1"
    error_message = "The role must be <application>-<environment>-<name>-exec-<region>."
  }

  assert {
    condition     = jsondecode(module.role[0].trust_policy_json).Statement[0].Principal.Service == ["lambda.amazonaws.com"] && jsondecode(module.role[0].trust_policy_json).Statement[0].Condition.StringEquals["aws:SourceAccount"] == ["123456789012"]
    error_message = "Only Lambda in this account may assume the role."
  }

  assert {
    condition     = [for s in jsondecode(module.role[0].policy_json).Statement : s.Sid] == ["WriteLogs"] && jsondecode(module.role[0].policy_json).Statement[0].Resource == ["arn:aws:logs:eu-west-1:123456789012:log-group:/aws/lambda/core-prod-orders:*"]
    error_message = "By default the role may only write to its own log group."
  }
}

run "module_key_is_planned_safely" {
  command = plan

  variables {
    kms = { create = true }
  }

  assert {
    condition     = length(module.encryption.created ? [1] : []) == 1
    error_message = "kms.create must plan without knowing the key ARN."
  }
}

run "module_key_encrypts_function_and_logs" {
  command = apply

  variables {
    kms = { create = true }
  }

  assert {
    condition     = aws_lambda_function.this.kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && module.log_group.kms_key_arn == aws_lambda_function.this.kms_key_arn
    error_message = "The module key must encrypt environment variables and logs."
  }
}

run "caller_key_id_and_log_key_override" {
  command = plan

  variables {
    kms             = { key_id = "11111111-2222-3333-4444-555555555555" }
    cloudwatch_logs = { kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/99999999-2222-3333-4444-555555555555", retention_in_days = 731 }
  }

  assert {
    condition     = aws_lambda_function.this.kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    error_message = "A key ID must be used as the key ARN."
  }

  assert {
    condition     = module.log_group.kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/99999999-2222-3333-4444-555555555555" && module.log_group.retention_in_days == 731
    error_message = "cloudwatch_logs must override the log key and retention."
  }
}

run "vpc_function" {
  command = apply

  variables {
    vpc_id     = "vpc-0a1b2c3d4e5f67890"
    subnet_ids = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
    security_group = {
      egress_cidr_blocks            = ["10.0.0.0/16"]
      additional_security_group_ids = ["sg-0aaaaaaaaaaaaaaaa"]
    }
  }

  assert {
    condition     = length(aws_lambda_function.this.vpc_config) == 1 && contains(aws_lambda_function.this.vpc_config[0].security_group_ids, "sg-0aaaaaaaaaaaaaaaa") && length(aws_lambda_function.this.vpc_config[0].security_group_ids) == 2
    error_message = "The function must use the module group and the extra group."
  }

  assert {
    condition     = keys(module.security_group[0].egress_rule_ids) == ["cidr-0"]
    error_message = "Egress must follow egress_cidr_blocks."
  }

  assert {
    condition     = contains(jsondecode(module.role[0].policy_json).Statement[*].Sid, "WriteLogs")
    error_message = "The role keeps its log statement in a VPC."
  }
}

run "triggers_and_destinations" {
  command = apply

  variables {
    event_sources = {
      orders = { type = "sqs", arn = "arn:aws:sqs:eu-west-1:123456789012:core-prod-orders", batch_size = 10, maximum_concurrency = 5, filter_patterns = ["{\"body\":{\"type\":[\"order\"]}}"] }
      clicks = { type = "kinesis", arn = "arn:aws:kinesis:eu-west-1:123456789012:stream/clicks", on_failure_destination_arn = "arn:aws:sqs:eu-west-1:123456789012:clicks-dlq" }
    }
    allowed_triggers = {
      events = { principal = "events.amazonaws.com", source_arn = "arn:aws:events:eu-west-1:123456789012:rule/core-prod-nightly" }
    }
    async_invoke = { enabled = true, on_failure_destination_arn = "arn:aws:sqs:eu-west-1:123456789012:core-prod-orders-failed" }
    function_url = { enabled = true }
  }

  assert {
    condition     = aws_lambda_event_source_mapping.this["orders"].function_name == "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-orders:live" && aws_lambda_event_source_mapping.this["orders"].scaling_config[0].maximum_concurrency == 5 && aws_lambda_event_source_mapping.this["orders"].starting_position == null
    error_message = "SQS mappings must target the alias with a concurrency cap."
  }

  assert {
    condition     = aws_lambda_event_source_mapping.this["clicks"].starting_position == "LATEST" && aws_lambda_event_source_mapping.this["clicks"].destination_config[0].on_failure[0].destination_arn == "arn:aws:sqs:eu-west-1:123456789012:clicks-dlq"
    error_message = "Stream mappings must start at LATEST and send failed records on."
  }

  assert {
    condition     = aws_lambda_permission.this["events"].qualifier == "live" && aws_lambda_permission.this["events"].source_account == "123456789012"
    error_message = "Triggers must be scoped to the alias and the account."
  }

  assert {
    condition     = aws_lambda_function_url.this[0].authorization_type == "AWS_IAM" && aws_lambda_function_event_invoke_config.this[0].qualifier == "live"
    error_message = "Function URLs use IAM auth; async config applies to the alias."
  }

  assert {
    condition = [for s in jsondecode(module.role[0].policy_json).Statement : s.Sid] == [
      "WriteLogs", "ConsumeQueues", "DecryptQueues", "ReadStreams", "SendFailedRecordsclicks", "AsyncFailureDestination"
    ]
    error_message = "The role must get exactly the permissions its triggers and destinations need."
  }
}

run "image_package_and_extensions" {
  command   = plan
  state_key = "image"

  variables {
    package         = { type = "Image", image_uri = "123456789012.dkr.ecr.eu-west-1.amazonaws.com/orders:1.0.0" }
    architecture    = "arm64"
    lambda_insights = { enabled = true, layer_arn = "arn:aws:lambda:eu-west-1:580247275435:layer:LambdaInsightsExtension-Arm64:31" }
    secret_arns     = ["arn:aws:secretsmanager:eu-west-1:123456789012:secret:core-prod-orders-db"]
    concurrency     = { reserved = 10, provisioned = 2 }
  }

  assert {
    condition     = aws_lambda_function.this.runtime == null
    error_message = "Image functions set no runtime."
  }

  assert {
    condition     = aws_lambda_function.this.handler == null
    error_message = "Image functions set no handler."
  }

  assert {
    condition     = aws_lambda_function.this.image_uri == "123456789012.dkr.ecr.eu-west-1.amazonaws.com/orders:1.0.0"
    error_message = "Image functions use image_uri."
  }

  assert {
    condition     = aws_lambda_function.this.filename == null
    error_message = "Image functions use no file."
  }

  assert {
    condition     = contains(aws_lambda_function.this.layers, "arn:aws:lambda:eu-west-1:580247275435:layer:LambdaInsightsExtension-Arm64:31")
    error_message = "Lambda Insights uses the given layer."
  }

  assert {
    condition     = contains(jsondecode(module.role[0].policy_json).Statement[*].Sid, "ReadSecrets") && contains(jsondecode(module.role[0].policy_json).Statement[*].Sid, "DecryptSecrets")
    error_message = "secret_arns must grant read and decrypt through Secrets Manager."
  }

  assert {
    condition     = aws_lambda_function.this.reserved_concurrent_executions == 10 && aws_lambda_provisioned_concurrency_config.this[0].provisioned_concurrent_executions == 2
    error_message = "Reserved and provisioned concurrency must apply."
  }
}

run "bring_your_own_role" {
  command = plan

  variables {
    iam_role = { create = false, arn = "arn:aws:iam::123456789012:role/shared-lambda" }
  }

  assert {
    condition     = aws_lambda_function.this.role == "arn:aws:iam::123456789012:role/shared-lambda" && length(module.role) == 0 && output.role_name == null
    error_message = "A caller role must replace the module role."
  }
}

run "extend_the_role" {
  command = plan

  variables {
    iam_role = {
      managed_policy_arns      = ["arn:aws:iam::123456789012:policy/orders-read"]
      permissions_boundary_arn = "arn:aws:iam::123456789012:policy/boundary"
      policy_statements        = [{ sid = "ReadTable", actions = ["dynamodb:GetItem"], resources = ["arn:aws:dynamodb:eu-west-1:123456789012:table/core-prod-orders"] }]
    }
  }

  assert {
    condition     = contains(jsondecode(module.role[0].policy_json).Statement[*].Sid, "ReadTable") && contains(jsondecode(module.role[0].policy_json).Statement[*].Sid, "WriteLogs")
    error_message = "Caller statements must be added to the module statements."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Orders_Fn"
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

run "rejects_unknown_package_type" {
  command = plan

  variables {
    package = { type = "Jar" }
  }

  expect_failures = [var.package]
}

run "rejects_unsupported_runtime" {
  command = plan

  variables {
    package = { runtime = "python2.7" }
  }

  expect_failures = [var.package]
}

run "rejects_amazon_linux_2_runtime" {
  command = plan

  variables {
    package = { runtime = "java17" }
  }

  expect_failures = [var.package]
}

run "rejects_preview_runtime" {
  command = plan

  variables {
    package = { runtime = "python3.15" }
  }

  expect_failures = [var.package]
}

run "rejects_insights_without_layer" {
  command = plan

  variables {
    lambda_insights = { enabled = true }
  }

  expect_failures = [var.lambda_insights]
}

run "rejects_image_without_uri" {
  command = plan

  variables {
    package = { type = "Image" }
  }

  expect_failures = [var.package]
}

run "rejects_bucket_without_key" {
  command = plan

  variables {
    package = { s3_bucket = "artifacts" }
  }

  expect_failures = [var.package]
}

run "rejects_invalid_architecture" {
  command = plan

  variables {
    architecture = "arm32"
  }

  expect_failures = [var.architecture]
}

run "rejects_invalid_memory" {
  command = plan

  variables {
    memory_size = 64
  }

  expect_failures = [var.memory_size]
}

run "rejects_invalid_timeout" {
  command = plan

  variables {
    timeout = 1200
  }

  expect_failures = [var.timeout]
}

run "rejects_invalid_ephemeral_storage" {
  command = plan

  variables {
    ephemeral_storage_size = 256
  }

  expect_failures = [var.ephemeral_storage_size]
}

run "rejects_negative_concurrency" {
  command = plan

  variables {
    concurrency = { provisioned = -1 }
  }

  expect_failures = [var.concurrency]
}

run "rejects_numeric_alias" {
  command = plan

  variables {
    alias_name = "1"
  }

  expect_failures = [var.alias_name]
}

run "rejects_credentials_in_environment" {
  command = plan

  variables {
    environment_variables = { DB_PASSWORD = "x" }
  }

  expect_failures = [var.environment_variables]
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
    kms = { key_id = "alias/orders" }
  }

  expect_failures = [var.kms]
}

run "rejects_role_without_arn" {
  command = plan

  variables {
    iam_role = { create = false }
  }

  expect_failures = [var.iam_role]
}

run "rejects_invalid_log_level" {
  command = plan

  variables {
    cloudwatch_logs = { application_log_level = "VERBOSE" }
  }

  expect_failures = [var.cloudwatch_logs]
}

run "rejects_invalid_tracing" {
  command = plan

  variables {
    tracing = "Off"
  }

  expect_failures = [var.tracing]
}

run "rejects_no_security_group" {
  command = plan

  variables {
    security_group = { create = false }
  }

  expect_failures = [var.security_group]
}

run "rejects_unknown_event_source_type" {
  command = plan

  variables {
    event_sources = { x = { type = "kafka", arn = "arn:aws:kafka:eu-west-1:123456789012:cluster/x/1" } }
  }

  expect_failures = [var.event_sources]
}

run "rejects_unscoped_trigger" {
  command = plan

  variables {
    allowed_triggers = { s3 = { principal = "s3.amazonaws.com" } }
  }

  expect_failures = [var.allowed_triggers]
}

run "rejects_invalid_url_mode" {
  command = plan

  variables {
    function_url = { enabled = true, invoke_mode = "STREAM" }
  }

  expect_failures = [var.function_url]
}

run "rejects_single_subnet" {
  command = plan

  variables {
    vpc_id     = "vpc-0a1b2c3d4e5f67890"
    subnet_ids = ["subnet-0123456789abcdef0"]
  }

  expect_failures = [var.subnet_ids]
}

run "rejects_subnets_without_vpc" {
  command = plan

  variables {
    subnet_ids = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  }

  expect_failures = [var.subnet_ids]
}

run "rejects_invalid_runtime_update_mode" {
  command = plan

  variables {
    runtime_update_mode = "Never"
  }

  expect_failures = [var.runtime_update_mode]
}
