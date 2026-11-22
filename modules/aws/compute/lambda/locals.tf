locals {
  function_name  = module.naming.names.function
  log_group_name = "/aws/lambda/${local.function_name}"
  log_group_arn  = "arn:${module.naming.partition}:logs:${module.naming.region}:${module.naming.account_id}:log-group:${local.log_group_name}"
  kms_key_arn    = module.encryption.key_arn
  in_vpc         = length(var.subnet_ids) > 0
  zip            = var.package.type == "Zip"
  placeholder    = local.zip && var.package.filename == null && var.package.s3_bucket == null
  runtime_family = local.zip ? (startswith(var.package.runtime, "nodejs") ? "nodejs" : "python") : null
  handler        = local.zip ? coalesce(var.package.handler, local.runtime_family == "nodejs" ? "index.handler" : "lambda_function.handler") : null
  role_arn       = var.iam_role.create ? module.role[0].arn : var.iam_role.arn
  arn_prefix     = "arn:${module.naming.partition}"

  kms_service_statements = [{
    sid        = "AllowCloudWatchLogs"
    actions    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    principals = { Service = ["logs.${module.naming.region}.${module.naming.dns_suffix}"] }
    conditions = [{ test = "ArnLike", variable = "kms:EncryptionContext:aws:logs:arn", values = [local.log_group_arn] }]
  }]

  sqs_sources    = { for k, s in var.event_sources : k => s if s.type == "sqs" }
  stream_sources = { for k, s in var.event_sources : k => s if s.type != "sqs" }

  role_statement_candidates = concat(
    [
      {
        when = true
        statement = {
          Sid      = "WriteLogs"
          Effect   = "Allow"
          Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
          Resource = ["${local.log_group_arn}:*"]
        }
      },
      {
        when = length(var.secret_arns) > 0
        statement = {
          Sid      = "ReadSecrets"
          Effect   = "Allow"
          Action   = ["secretsmanager:GetSecretValue"]
          Resource = var.secret_arns
        }
      },
      {
        when = length(var.secret_arns) > 0
        statement = {
          Sid       = "DecryptSecrets"
          Effect    = "Allow"
          Action    = ["kms:Decrypt"]
          Resource  = ["*"]
          Condition = { StringEquals = { "kms:ViaService" = "secretsmanager.${module.naming.region}.${module.naming.dns_suffix}" } }
        }
      },
      {
        when = length(local.sqs_sources) > 0
        statement = {
          Sid      = "ConsumeQueues"
          Effect   = "Allow"
          Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:ChangeMessageVisibility"]
          Resource = [for s in values(local.sqs_sources) : s.arn]
        }
      },
      {
        when = length(local.sqs_sources) > 0
        statement = {
          Sid       = "DecryptQueues"
          Effect    = "Allow"
          Action    = ["kms:Decrypt"]
          Resource  = ["*"]
          Condition = { StringEquals = { "kms:ViaService" = "sqs.${module.naming.region}.${module.naming.dns_suffix}" } }
        }
      },
      {
        when = length(local.stream_sources) > 0
        statement = {
          Sid      = "ReadStreams"
          Effect   = "Allow"
          Action   = ["kinesis:GetRecords", "kinesis:GetShardIterator", "kinesis:DescribeStream", "kinesis:DescribeStreamSummary", "kinesis:ListShards", "kinesis:SubscribeToShard", "dynamodb:GetRecords", "dynamodb:GetShardIterator", "dynamodb:DescribeStream", "dynamodb:ListStreams"]
          Resource = [for s in values(local.stream_sources) : s.arn]
        }
      },
      {
        when = var.dead_letter_target_arn != null
        statement = {
          Sid      = "DeadLetter"
          Effect   = "Allow"
          Action   = ["sqs:SendMessage", "sns:Publish"]
          Resource = [var.dead_letter_target_arn]
        }
      }
    ],
    [for k, s in local.stream_sources : {
      when = s.on_failure_destination_arn != null
      statement = {
        Sid      = "SendFailedRecords${replace(k, "/[^a-zA-Z0-9]/", "")}"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage", "sns:Publish"]
        Resource = [s.on_failure_destination_arn]
      }
    }],
    [for kind, arn in { Success = var.async_invoke.on_success_destination_arn, Failure = var.async_invoke.on_failure_destination_arn } : {
      when                      = var.async_invoke.enabled && arn != null
      statement = {
        Sid      = "Async${kind}Destination"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage", "sns:Publish", "events:PutEvents", "lambda:InvokeFunction"]
        Resource = [arn]
      }
    }]
  )

  role_statements = [for c in local.role_statement_candidates : c.statement if c.when]

  managed_policy_arns = concat(
    local.in_vpc ? ["${local.arn_prefix}:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"] : [],
    var.tracing == "Active" ? ["${local.arn_prefix}:iam::aws:policy/AWSXRayDaemonWriteAccess"] : [],
    var.lambda_insights.enabled ? ["${local.arn_prefix}:iam::aws:policy/CloudWatchLambdaInsightsExecutionRolePolicy"] : [],
    var.iam_role.managed_policy_arns
  )

  layers = concat(
    var.layers,
    var.lambda_insights.enabled ? [var.lambda_insights.layer_arn] : []
  )

  security_group_ids = concat(local.in_vpc && var.security_group.create ? [module.security_group[0].id] : [], var.security_group.additional_security_group_ids)

  egress_rules = merge(
    { for i, cidr in var.security_group.egress_cidr_blocks : "cidr-${i}" => { description = "Outbound to ${cidr}", ip_protocol = "-1", cidr_ipv4 = cidr } },
    { for i, pl in var.security_group.egress_prefix_list_ids : "pl-${i}" => { description = "Outbound to a prefix list", ip_protocol = "-1", prefix_list_id = pl } },
    { for i, sg in var.security_group.egress_security_group_ids : "sg-${i}" => { description = "Outbound to a security group", ip_protocol = "-1", referenced_security_group_id = sg } }
  )
}
