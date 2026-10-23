mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  application = "core"
  environment = "prod"
  name        = "order-pipeline"
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
  definition = jsonencode({
    Comment = "Order processing state machine"
    StartAt = "Validate"
    States = {
      Validate = {
        Type = "Pass"
        End  = true
      }
    }
  })
  cloudwatch_logs = {
    retention_in_days = 30
  }
}

run "verify_naming" {
  command = plan

  assert {
    condition     = aws_sfn_state_machine.this.name == "core-prod-order-pipeline"
    error_message = "State machine name must render as <application>-<environment>-<name>."
  }

  assert {
    condition     = aws_iam_role.this.name == "core-prod-order-pipeline-sfn"
    error_message = "Execution role name must render as <rendered_name>-sfn."
  }

  assert {
    condition     = aws_iam_role_policy.execution.name == "core-prod-order-pipeline-sfn-execution"
    error_message = "Execution role policy name must render as <rendered_name>-sfn-execution."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.name == "/aws/step_function/core-prod-order-pipeline"
    error_message = "Log group name must render as /aws/step_function/<rendered_name>."
  }

  assert {
    condition     = output.state_machine_name == "core-prod-order-pipeline"
    error_message = "state_machine_name output must expose the rendered state machine name."
  }
}

run "verify_tags" {
  command = plan

  variables {
    tags = {
      WorkflowTier = "OrderOrchestration"
      CostCenter   = "1234"
    }
  }

  assert {
    condition     = aws_sfn_state_machine.this.tags["Application"] == "core" && aws_sfn_state_machine.this.tags["Environment"] == "prod" && aws_sfn_state_machine.this.tags["Name"] == "core-prod-order-pipeline"
    error_message = "State machine must carry Application, Environment and Name governance tags."
  }

  assert {
    condition     = aws_sfn_state_machine.this.tags["WorkflowTier"] == "OrderOrchestration" && aws_sfn_state_machine.this.tags["CostCenter"] == "1234"
    error_message = "Caller tags must be preserved on the state machine."
  }

  assert {
    condition     = aws_iam_role.this.tags["Application"] == "core" && aws_iam_role.this.tags["Environment"] == "prod" && aws_iam_role.this.tags["Name"] == "core-prod-order-pipeline" && aws_iam_role.this.tags["WorkflowTier"] == "OrderOrchestration"
    error_message = "Execution role must carry governance and caller tags."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.tags["Application"] == "core" && aws_cloudwatch_log_group.this.tags["Environment"] == "prod" && aws_cloudwatch_log_group.this.tags["WorkflowTier"] == "OrderOrchestration"
    error_message = "Log group must carry governance and caller tags."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.tags["Name"] == "/aws/step_function/core-prod-order-pipeline"
    error_message = "Log group must override the Name tag with its log group name."
  }
}

run "verify_security_defaults" {
  command = plan

  assert {
    condition     = aws_sfn_state_machine.this.encryption_configuration[0].type == "CUSTOMER_MANAGED_KMS_KEY"
    error_message = "State machine must be encrypted with a customer managed KMS key."
  }

  assert {
    condition     = aws_sfn_state_machine.this.encryption_configuration[0].kms_key_id == var.kms_key_arn
    error_message = "State machine must be encrypted with the caller-supplied KMS key."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.kms_key_id == var.kms_key_arn
    error_message = "Log group must fall back to kms_key_arn when cloudwatch_logs.kms_key_arn is not set."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 30
    error_message = "Log group retention must follow cloudwatch_logs.retention_in_days."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.log_group_class == "STANDARD"
    error_message = "Log group must use the STANDARD class."
  }

  assert {
    condition     = toset(data.aws_iam_policy_document.assume.statement[0].actions) == toset(["sts:AssumeRole"])
    error_message = "Execution role trust policy must only allow sts:AssumeRole."
  }

  assert {
    condition     = toset(flatten([for p in data.aws_iam_policy_document.assume.statement[0].principals : [for i in p.identifiers : "${p.type}:${i}"]])) == toset(["Service:states.amazonaws.com"])
    error_message = "Execution role must only be assumable by the Step Functions service."
  }

  assert {
    condition     = aws_iam_role.this.assume_role_policy == data.aws_iam_policy_document.assume.json
    error_message = "Execution role trust policy must be rendered from the assume policy document."
  }
}

run "verify_parameter_defaults" {
  command = plan

  assert {
    condition     = aws_sfn_state_machine.this.type == "STANDARD"
    error_message = "State machine type must default to STANDARD."
  }

  assert {
    condition     = aws_sfn_state_machine.this.definition == var.definition
    error_message = "State machine definition must flow through unchanged."
  }

  assert {
    condition     = aws_sfn_state_machine.this.tracing_configuration[0].enabled == true
    error_message = "X-Ray tracing must be enabled by default."
  }

  assert {
    condition     = aws_sfn_state_machine.this.logging_configuration[0].level == "ALL"
    error_message = "Logging level must default to ALL."
  }

  assert {
    condition     = aws_sfn_state_machine.this.logging_configuration[0].include_execution_data == true
    error_message = "Execution data must be included in logs."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.deletion_protection_enabled == false
    error_message = "Log group deletion protection must default to false."
  }
}

run "verify_parameter_overrides" {
  command = plan

  variables {
    type            = "EXPRESS"
    tracing_enabled = false
    cloudwatch_logs = {
      retention_in_days           = 90
      kms_key_arn                 = "arn:aws:kms:us-west-2:123456789012:key/87654321-4321-4321-4321-210987654321"
      deletion_protection_enabled = true
      level                       = "ERROR"
    }
  }

  assert {
    condition     = aws_sfn_state_machine.this.type == "EXPRESS"
    error_message = "type must flow through to the state machine."
  }

  assert {
    condition     = aws_sfn_state_machine.this.tracing_configuration[0].enabled == false
    error_message = "tracing_enabled must flow through to the state machine."
  }

  assert {
    condition     = aws_sfn_state_machine.this.logging_configuration[0].level == "ERROR"
    error_message = "cloudwatch_logs.level must flow through to the logging configuration."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.kms_key_id == "arn:aws:kms:us-west-2:123456789012:key/87654321-4321-4321-4321-210987654321"
    error_message = "cloudwatch_logs.kms_key_arn must take precedence over kms_key_arn for the log group."
  }

  assert {
    condition     = aws_sfn_state_machine.this.encryption_configuration[0].kms_key_id == var.kms_key_arn
    error_message = "State machine encryption must keep using kms_key_arn when the log group uses a different key."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 90 && aws_cloudwatch_log_group.this.deletion_protection_enabled == true
    error_message = "cloudwatch_logs retention and deletion protection must flow through to the log group."
  }
}

run "verify_lambda_invoke_scope" {
  command = plan

  variables {
    lambda_function_arns = [
      "arn:aws:lambda:us-west-2:123456789012:function:core-prod-validate",
      "arn:aws:lambda:us-west-2:123456789012:function:core-prod-charge",
    ]
  }

  assert {
    condition     = data.aws_iam_policy_document.execution.statement[0].sid == "InvokeLambdas" && toset(data.aws_iam_policy_document.execution.statement[0].actions) == toset(["lambda:InvokeFunction"])
    error_message = "Execution policy must contain an InvokeLambdas statement granting only lambda:InvokeFunction."
  }

  assert {
    condition = toset(data.aws_iam_policy_document.execution.statement[0].resources) == toset([
      "arn:aws:lambda:us-west-2:123456789012:function:core-prod-validate",
      "arn:aws:lambda:us-west-2:123456789012:function:core-prod-validate:*",
      "arn:aws:lambda:us-west-2:123456789012:function:core-prod-charge",
      "arn:aws:lambda:us-west-2:123456789012:function:core-prod-charge:*",
    ])
    error_message = "Lambda invoke permission must be scoped to the supplied functions and their versions or aliases."
  }

  assert {
    condition     = aws_iam_role_policy.execution.policy == data.aws_iam_policy_document.execution.json
    error_message = "Execution role policy must be rendered from the execution policy document."
  }
}

run "verify_wiring" {
  command = apply

  override_resource {
    target = aws_cloudwatch_log_group.this
    values = {
      arn = "arn:aws:logs:us-west-2:123456789012:log-group:/aws/step_function/core-prod-order-pipeline"
    }
  }

  override_resource {
    target = aws_iam_role.this
    values = {
      id  = "core-prod-order-pipeline-sfn"
      arn = "arn:aws:iam::123456789012:role/core-prod-order-pipeline-sfn"
    }
  }

  override_resource {
    target = aws_sfn_state_machine.this
    values = {
      arn = "arn:aws:states:us-west-2:123456789012:stateMachine:core-prod-order-pipeline"
    }
  }

  assert {
    condition     = aws_sfn_state_machine.this.logging_configuration[0].log_destination == "arn:aws:logs:us-west-2:123456789012:log-group:/aws/step_function/core-prod-order-pipeline:*"
    error_message = "State machine must log to the module's log group."
  }

  assert {
    condition     = aws_sfn_state_machine.this.role_arn == "arn:aws:iam::123456789012:role/core-prod-order-pipeline-sfn"
    error_message = "State machine must run as the module's execution role."
  }

  assert {
    condition     = aws_iam_role_policy.execution.role == "core-prod-order-pipeline-sfn"
    error_message = "Execution policy must be attached to the module's execution role."
  }

  assert {
    condition     = output.state_machine_arn == "arn:aws:states:us-west-2:123456789012:stateMachine:core-prod-order-pipeline" && output.role_arn == "arn:aws:iam::123456789012:role/core-prod-order-pipeline-sfn"
    error_message = "state_machine_arn and role_arn outputs must expose the state machine and its role."
  }
}

run "verify_invalid_environment_fails" {
  command = plan

  variables {
    environment = "INVALID_UPPERCASE"
  }

  expect_failures = [var.environment]
}
