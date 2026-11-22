locals {
  table_name  = module.naming.names.table
  kms_key_arn = module.encryption.key_arn
  provisioned = var.billing_mode == "PROVISIONED"

  key_attribute_names = distinct(compact(concat(
    [var.hash_key, var.range_key],
    flatten([for i in values(var.global_secondary_indexes) : [i.hash_key, i.range_key]]),
    [for i in values(var.local_secondary_indexes) : i.range_key]
  )))

  attributes = { for n in local.key_attribute_names : n => try(var.attributes[n], "S") }

  kms_service_statements = [{
    sid        = "AllowDynamoDB"
    actions    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:CreateGrant", "kms:DescribeKey"]
    principals = { AWS = ["*"] }
    conditions = [
      { test = "StringEquals", variable = "kms:CallerAccount", values = [module.naming.account_id] },
      { test = "StringEquals", variable = "kms:ViaService", values = ["dynamodb.${module.naming.region}.${module.naming.dns_suffix}"] }
    ]
  }]

  scaled_capacity = merge(
    {
      table = {
        resource_suffix = ""
        kind            = "table"
        read            = var.provisioned_capacity.read
        write           = var.provisioned_capacity.write
      }
    },
    {
      for k, i in var.global_secondary_indexes : "index-${k}" => {
        resource_suffix = "/index/${k}"
        kind            = "index"
        read            = coalesce(i.read_capacity, var.provisioned_capacity.read)
        write           = coalesce(i.write_capacity, var.provisioned_capacity.write)
      }
    }
  )

  autoscaling_targets = local.provisioned && var.autoscaling.enabled ? merge([
    for k, c in local.scaled_capacity : {
      "${k}-read" = {
        resource_suffix = c.resource_suffix
        dimension       = "dynamodb:${c.kind}:ReadCapacityUnits"
        metric          = "DynamoDBReadCapacityUtilization"
        min_capacity    = c.read
        max_capacity    = var.autoscaling.max_read_capacity
      }
      "${k}-write" = {
        resource_suffix = c.resource_suffix
        dimension       = "dynamodb:${c.kind}:WriteCapacityUnits"
        metric          = "DynamoDBWriteCapacityUtilization"
        min_capacity    = c.write
        max_capacity    = var.autoscaling.max_write_capacity
      }
    }
  ]...) : {}

  contributor_insights = var.contributor_insights.enabled ? merge({ table = null }, { for n in var.contributor_insights.index_names : "index-${n}" => n }) : {}
}
