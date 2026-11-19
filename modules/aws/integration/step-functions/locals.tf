locals {
  state_machine_name = module.naming.names.state_machine
  state_machine_arn  = "arn:${module.naming.partition}:states:${module.naming.region}:${module.naming.account_id}:stateMachine:${local.state_machine_name}"
  log_group_name     = "/aws/vendedlogs/states/${local.state_machine_name}"
  log_group_arn      = "arn:${module.naming.partition}:logs:${module.naming.region}:${module.naming.account_id}:log-group:${local.log_group_name}"
  kms_key_arn        = module.encryption.key_arn
  customer_key       = var.kms.create || var.kms.key_id != null
  role_arn           = var.iam_role.create ? module.role[0].arn : var.iam_role.arn

  kms_service_statements = [
    {
      sid        = "AllowCloudWatchLogs"
      actions    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
      principals = { Service = ["logs.${module.naming.region}.${module.naming.dns_suffix}"] }
      conditions = [{ test = "ArnLike", variable = "kms:EncryptionContext:aws:logs:arn", values = [local.log_group_arn] }]
    },
    {
      sid        = "AllowLogDelivery"
      actions    = ["kms:Decrypt"]
      principals = { Service = ["delivery.logs.${module.naming.dns_suffix}"] }
      conditions = [{ test = "StringEquals", variable = "aws:SourceAccount", values = [module.naming.account_id] }]
    }
  ]

  role_statement_candidates = [
    {
      when = length(var.lambda_function_arns) > 0
      statement = {
        Sid      = "InvokeFunctions"
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = flatten([for arn in var.lambda_function_arns : [arn, "${arn}:*"]])
      }
    },
    {
      when = true
      statement = {
        Sid      = "DeliverLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogDelivery", "logs:GetLogDelivery", "logs:UpdateLogDelivery", "logs:DeleteLogDelivery", "logs:ListLogDeliveries", "logs:PutResourcePolicy", "logs:DescribeResourcePolicies", "logs:DescribeLogGroups"]
        Resource = ["*"]
      }
    },
    {
      when = local.customer_key
      statement = {
        Sid       = "UseStateMachineKey"
        Effect    = "Allow"
        Action    = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource  = [local.kms_key_arn]
        Condition = { StringEquals = { "kms:EncryptionContext:aws:states:stateMachineArn" = local.state_machine_arn } }
      }
    },
    {
      when = local.customer_key
      statement = {
        Sid       = "UseKeyForLogDelivery"
        Effect    = "Allow"
        Action    = ["kms:GenerateDataKey"]
        Resource  = [local.kms_key_arn]
        Condition = { StringLike = { "kms:EncryptionContext:SourceArn" = "arn:${module.naming.partition}:logs:${module.naming.region}:${module.naming.account_id}:*" } }
      }
    },
    {
      when = var.tracing.enabled
      statement = {
        Sid      = "WriteTraces"
        Effect   = "Allow"
        Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords", "xray:GetSamplingRules", "xray:GetSamplingTargets"]
        Resource = ["*"]
      }
    }
  ]

  role_statements = [for c in local.role_statement_candidates : c.statement if c.when]
}
