locals {
  arn_prefix         = "arn:${module.naming.partition}"
  kms_create         = var.kms.create && (var.trail.enabled || var.bucket.enabled)
  kms_key_arn        = module.encryption.key_arn
  cloudwatch_enabled = var.trail.enabled && var.cloudwatch_logs.enabled
  role_enabled       = local.cloudwatch_enabled && var.iam_role.create
  role_arn           = local.cloudwatch_enabled ? (var.iam_role.create ? module.role[0].arn : var.iam_role.arn) : null

  trail_name             = module.naming.names.trail
  trail_owner_account_id = var.trail.is_organization_trail && var.trail.management_account_id != null ? var.trail.management_account_id : module.naming.account_id
  trail_arn              = "${local.arn_prefix}:cloudtrail:${module.naming.region}:${local.trail_owner_account_id}:trail/${local.trail_name}"
  trail_writers          = var.trail.enabled || length(var.bucket.additional_trail_arns) > 0
  trail_arns             = distinct(concat(var.trail.enabled ? [local.trail_arn] : [], var.bucket.additional_trail_arns))
  trail_owner_accounts   = distinct([for arn in local.trail_arns : split(":", arn)[4]])

  log_group_name = "/aws/cloudtrail/${module.naming.name}"
  log_group_arn  = "${local.arn_prefix}:logs:${module.naming.region}:${module.naming.account_id}:log-group:${local.log_group_name}"

  read_only_values = {
    All       = null
    ReadOnly  = ["true"]
    WriteOnly = ["false"]
  }

  management_selector = {
    name = "Management events"
    field_selectors = concat(
      [{ field = "eventCategory", equals = ["Management"], not_equals = null, starts_with = null }],
      length(var.trail.exclude_management_event_sources) > 0 ? [{ field = "eventSource", equals = null, not_equals = sort(tolist(var.trail.exclude_management_event_sources)), starts_with = null }] : []
    )
  }

  data_events = var.trail.data_events

  data_selector_inputs = [
    for selector in [
      {
        enabled         = local.data_events.s3_objects.enabled
        name            = "S3 object data events"
        resource_type   = "AWS::S3::Object"
        read_write_type = local.data_events.s3_objects.read_write_type
        starts_with     = length(local.data_events.s3_objects.bucket_arns) > 0 ? [for arn in local.data_events.s3_objects.bucket_arns : "${trimsuffix(arn, "/")}/"] : null
        equals          = null
      },
      {
        enabled         = local.data_events.lambda_functions.enabled
        name            = "Lambda function data events"
        resource_type   = "AWS::Lambda::Function"
        read_write_type = local.data_events.lambda_functions.read_write_type
        starts_with     = null
        equals          = length(local.data_events.lambda_functions.function_arns) > 0 ? local.data_events.lambda_functions.function_arns : null
      },
      {
        enabled         = local.data_events.dynamodb_tables.enabled
        name            = "DynamoDB table data events"
        resource_type   = "AWS::DynamoDB::Table"
        read_write_type = local.data_events.dynamodb_tables.read_write_type
        starts_with     = null
        equals          = length(local.data_events.dynamodb_tables.table_arns) > 0 ? local.data_events.dynamodb_tables.table_arns : null
      },
    ] : selector if selector.enabled
  ]

  data_selectors = [
    for selector in local.data_selector_inputs : {
      name = selector.name
      field_selectors = concat(
        [
          { field = "eventCategory", equals = ["Data"], not_equals = null, starts_with = null },
          { field = "resources.type", equals = [selector.resource_type], not_equals = null, starts_with = null },
        ],
        selector.read_write_type == "All" ? [] : [{ field = "readOnly", equals = local.read_only_values[selector.read_write_type], not_equals = null, starts_with = null }],
        selector.starts_with == null && selector.equals == null ? [] : [{ field = "resources.ARN", equals = selector.equals, not_equals = null, starts_with = selector.starts_with }]
      )
    }
  ]

  advanced_event_selectors = concat([local.management_selector], local.data_selectors)

  kms_statement_candidates = [
    {
      when = local.trail_writers
      statement = {
        sid        = "AllowCloudTrailEncryptLogs"
        actions    = ["kms:GenerateDataKey*"]
        principals = { Service = ["cloudtrail.amazonaws.com"] }
        conditions = [
          { test = "StringEquals", variable = "aws:SourceArn", values = local.trail_arns },
          { test = "StringLike", variable = "kms:EncryptionContext:aws:cloudtrail:arn", values = [for account_id in local.trail_owner_accounts : "${local.arn_prefix}:cloudtrail:*:${account_id}:trail/*"] },
        ]
      }
    },
    {
      when = local.trail_writers
      statement = {
        sid        = "AllowCloudTrailDescribeKey"
        actions    = ["kms:DescribeKey"]
        principals = { Service = ["cloudtrail.amazonaws.com"] }
        conditions = [{ test = "StringEquals", variable = "aws:SourceArn", values = local.trail_arns }]
      }
    },
    {
      when = local.cloudwatch_enabled
      statement = {
        sid        = "AllowCloudWatchLogs"
        actions    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
        principals = { Service = ["logs.${module.naming.region}.${module.naming.dns_suffix}"] }
        conditions = [{ test = "ArnEquals", variable = "kms:EncryptionContext:aws:logs:arn", values = [local.log_group_arn] }]
      }
    },
    {
      when = true
      statement = {
        sid        = "AllowCloudTrailLogDecrypt"
        actions    = ["kms:Decrypt"]
        principals = { AWS = ["${local.arn_prefix}:iam::${module.naming.account_id}:root"] }
        conditions = [{ test = "Null", variable = "kms:EncryptionContext:aws:cloudtrail:arn", values = ["false"] }]
      }
    },
  ]

  kms_service_statements = [for c in local.kms_statement_candidates : c.statement if c.when]

  role_statements = [{
    Sid      = "DeliverToLogGroup"
    Effect   = "Allow"
    Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    Resource = ["${local.log_group_arn}:log-stream:*"]
  }]
}
