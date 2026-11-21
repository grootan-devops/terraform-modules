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
      arn = "arn:aws:iam::123456789012:role/core-prod-orders-sfn-eu-west-1"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-west-1:123456789012:log-group:/aws/vendedlogs/states/core-prod-orders"
    }
  }

  mock_resource "aws_sfn_state_machine" {
    defaults = {
      arn = "arn:aws:states:eu-west-1:123456789012:stateMachine:core-prod-orders"
    }
  }
}

variables {
  application = "core"
  environment = "prod"
  name        = "orders"
  tags        = { Team = "payments" }
  definition  = "{\"StartAt\":\"Done\",\"States\":{\"Done\":{\"Type\":\"Pass\",\"End\":true}}}"
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = aws_sfn_state_machine.this.name == "core-prod-orders" && aws_sfn_state_machine.this.type == "STANDARD"
    error_message = "The state machine must be <application>-<environment>-<name>, STANDARD by default."
  }

  assert {
    condition     = aws_sfn_state_machine.this.encryption_configuration[0].type == "AWS_OWNED_KEY" && aws_sfn_state_machine.this.encryption_configuration[0].kms_key_id == null && output.kms_key_arn == null
    error_message = "No kms input means the AWS owned key."
  }

  assert {
    condition     = aws_sfn_state_machine.this.logging_configuration[0].level == "ERROR" && !aws_sfn_state_machine.this.logging_configuration[0].include_execution_data && aws_sfn_state_machine.this.tracing_configuration[0].enabled
    error_message = "Logging ERROR without execution data and X-Ray tracing by default (StepFunctions.1)."
  }

  assert {
    condition     = module.log_group.name == "/aws/vendedlogs/states/core-prod-orders" && module.log_group.retention_in_days == 365 && module.log_group.kms_key_arn == null
    error_message = "Logs go to /aws/vendedlogs/states/<name>, 365 days, service encryption."
  }

  assert {
    condition     = aws_sfn_state_machine.this.tags["Name"] == "core-prod-orders" && aws_sfn_state_machine.this.tags["Team"] == "payments" && aws_sfn_state_machine.this.tags["ManagedBy"] == "Terraform"
    error_message = "Caller and governance tags must be applied."
  }
}

run "execution_role" {
  command = plan

  assert {
    condition     = module.role[0].name == "core-prod-orders-sfn-eu-west-1"
    error_message = "The role must be <application>-<environment>-<name>-sfn-<region>."
  }

  assert {
    condition     = jsondecode(module.role[0].trust_policy_json).Statement[0].Principal.Service == ["states.amazonaws.com"] && jsondecode(module.role[0].trust_policy_json).Statement[0].Condition.StringEquals["aws:SourceAccount"] == ["123456789012"] && jsondecode(module.role[0].trust_policy_json).Statement[0].Condition.ArnLike["aws:SourceArn"] == ["arn:aws:states:eu-west-1:123456789012:stateMachine:core-prod-orders", "arn:aws:states:eu-west-1:123456789012:stateMachine:core-prod-orders:*"]
    error_message = "Only this state machine in this account may assume the role."
  }

  assert {
    condition     = [for s in jsondecode(module.role[0].policy_json).Statement : s.Sid] == ["DeliverLogs", "WriteTraces"]
    error_message = "By default the role may only deliver logs and write traces."
  }
}

run "invoke_listed_functions" {
  command = plan

  variables {
    lambda_function_arns = ["arn:aws:lambda:eu-west-1:123456789012:function:core-prod-validate", "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-charge"]
  }

  assert {
    condition = jsondecode(module.role[0].policy_json).Statement[0].Sid == "InvokeFunctions" && jsondecode(module.role[0].policy_json).Statement[0].Action == ["lambda:InvokeFunction"] && jsondecode(module.role[0].policy_json).Statement[0].Resource == [
      "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-validate", "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-validate:*",
      "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-charge", "arn:aws:lambda:eu-west-1:123456789012:function:core-prod-charge:*"
    ]
    error_message = "Invoke is limited to the listed functions, their versions and aliases."
  }
}

run "tracing_off" {
  command = plan

  variables {
    tracing = { enabled = false }
    type    = "EXPRESS"
  }

  assert {
    condition     = !aws_sfn_state_machine.this.tracing_configuration[0].enabled && !contains(jsondecode(module.role[0].policy_json).Statement[*].Sid, "WriteTraces") && aws_sfn_state_machine.this.type == "EXPRESS"
    error_message = "X-Ray permissions only when tracing is on."
  }
}

run "log_destination" {
  command = apply

  assert {
    condition     = aws_sfn_state_machine.this.logging_configuration[0].log_destination == "arn:aws:logs:eu-west-1:123456789012:log-group:/aws/vendedlogs/states/core-prod-orders:*" && output.log_group_arn == "arn:aws:logs:eu-west-1:123456789012:log-group:/aws/vendedlogs/states/core-prod-orders"
    error_message = "Execution history must go to the module log group."
  }

  assert {
    condition     = output.arn == "arn:aws:states:eu-west-1:123456789012:stateMachine:core-prod-orders" && output.role_arn == "arn:aws:iam::123456789012:role/core-prod-orders-sfn-eu-west-1"
    error_message = "Outputs must expose the state machine and role ARNs."
  }
}

run "module_key_is_planned_safely" {
  command = plan

  variables {
    kms = { create = true }
  }

  assert {
    condition     = module.encryption.created && aws_sfn_state_machine.this.encryption_configuration[0].type == "CUSTOMER_MANAGED_KMS_KEY"
    error_message = "kms.create must plan without knowing the key ARN."
  }
}

run "module_key_encrypts_state_machine_and_logs" {
  command = apply

  variables {
    kms = { create = true }
  }

  assert {
    condition     = aws_sfn_state_machine.this.encryption_configuration[0].kms_key_id == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && aws_sfn_state_machine.this.encryption_configuration[0].kms_data_key_reuse_period_seconds == 300 && module.log_group.kms_key_arn == output.kms_key_arn
    error_message = "The module key must encrypt the execution history and the logs."
  }

  assert {
    condition     = [for s in jsondecode(module.role[0].policy_json).Statement : s.Sid] == ["DeliverLogs", "UseStateMachineKey", "UseKeyForLogDelivery", "WriteTraces"]
    error_message = "A customer key adds the key statements."
  }

  assert {
    condition     = jsondecode(module.role[0].policy_json).Statement[1].Resource == ["arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"] && jsondecode(module.role[0].policy_json).Statement[1].Condition.StringEquals["kms:EncryptionContext:aws:states:stateMachineArn"] == "arn:aws:states:eu-west-1:123456789012:stateMachine:core-prod-orders"
    error_message = "Key use is limited to this state machine's encryption context."
  }
}

run "caller_key_id_and_log_key_override" {
  command = plan

  variables {
    kms             = { key_id = "11111111-2222-3333-4444-555555555555" }
    cloudwatch_logs = { kms_key_arn = "arn:aws:kms:eu-west-1:123456789012:key/99999999-2222-3333-4444-555555555555", retention_in_days = 731, level = "ALL", include_execution_data = true }
  }

  assert {
    condition     = aws_sfn_state_machine.this.encryption_configuration[0].kms_key_id == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    error_message = "A key ID must be used as the key ARN."
  }

  assert {
    condition     = module.log_group.kms_key_arn == "arn:aws:kms:eu-west-1:123456789012:key/99999999-2222-3333-4444-555555555555" && module.log_group.retention_in_days == 731 && aws_sfn_state_machine.this.logging_configuration[0].level == "ALL" && aws_sfn_state_machine.this.logging_configuration[0].include_execution_data
    error_message = "cloudwatch_logs must override the log key, retention and level."
  }
}

run "bring_your_own_role" {
  command = plan

  variables {
    iam_role = { create = false, arn = "arn:aws:iam::123456789012:role/shared-sfn" }
  }

  assert {
    condition     = aws_sfn_state_machine.this.role_arn == "arn:aws:iam::123456789012:role/shared-sfn" && length(module.role) == 0 && output.role_name == null
    error_message = "A caller role must replace the module role."
  }
}

run "extend_the_role" {
  command = plan

  variables {
    iam_role = {
      managed_policy_arns      = ["arn:aws:iam::123456789012:policy/orders-read"]
      permissions_boundary_arn = "arn:aws:iam::123456789012:policy/boundary"
      policy_statements        = [{ sid = "PublishEvents", actions = ["events:PutEvents"], resources = ["arn:aws:events:eu-west-1:123456789012:event-bus/core-prod"] }]
    }
  }

  assert {
    condition     = contains(jsondecode(module.role[0].policy_json).Statement[*].Sid, "PublishEvents") && contains(jsondecode(module.role[0].policy_json).Statement[*].Sid, "DeliverLogs")
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
  }

  assert {
    condition     = length(aws_sfn_state_machine.this.name) == 70 && length(module.role[0].name) == 64
    error_message = "The state machine keeps 80 characters; the role is cut to 64 with a hash."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Orders_Flow"
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

run "rejects_invalid_definition" {
  command = plan

  variables {
    definition = "{\"States\":{}}"
  }

  expect_failures = [var.definition]
}

run "rejects_invalid_type" {
  command = plan

  variables {
    type = "SYNC"
  }

  expect_failures = [var.type]
}

run "rejects_qualified_function_arn" {
  command = plan

  variables {
    lambda_function_arns = ["arn:aws:lambda:eu-west-1:123456789012:function:core-prod-validate:live"]
  }

  expect_failures = [var.lambda_function_arns]
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

run "rejects_logging_off" {
  command = plan

  variables {
    cloudwatch_logs = { level = "OFF" }
  }

  expect_failures = [var.cloudwatch_logs]
}
