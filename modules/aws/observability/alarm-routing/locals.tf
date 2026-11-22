locals {
  regions    = length(var.regions) > 0 ? distinct(var.regions) : [module.naming.region]
  severities = distinct(var.severities)
  account_id = module.naming.account_id
  partition  = module.naming.partition

  topics = {
    for pair in setproduct(local.regions, local.severities) : "${pair[0]}/${pair[1]}" => {
      region   = pair[0]
      severity = pair[1]
      name     = module.naming.names[pair[1]]
      arn      = "arn:${local.partition}:sns:${pair[0]}:${local.account_id}:${module.naming.names[pair[1]]}"
    }
  }

  source_account = [{ test = "StringEquals", variable = "aws:SourceAccount", values = [local.account_id] }]

  source_arn_publishers = {
    "budgets.amazonaws.com"    = { sid = "Budgets", source_arn = "arn:${local.partition}:budgets::${local.account_id}:*" }
    "costalerts.amazonaws.com" = { sid = "CostAnomalyDetection", source_arn = "arn:${local.partition}:ce::${local.account_id}:*" }
  }

  scoped_publishers  = { for p, spec in local.source_arn_publishers : p => spec if contains(var.additional_publisher_service_principals, p) }
  account_publishers = distinct([for p in var.additional_publisher_service_principals : p if !contains(keys(local.source_arn_publishers), p)])
  extra_signed       = [for p in local.account_publishers : p if p != "events.amazonaws.com"]
  eventbridge        = contains(var.additional_publisher_service_principals, "events.amazonaws.com")

  kms_service_statements = concat(
    [{ sid = "AllowCloudWatchAlarms", actions = ["kms:Decrypt", "kms:GenerateDataKey*"], principals = { Service = ["cloudwatch.amazonaws.com"] }, conditions = local.source_account }],
    [for p, spec in local.scoped_publishers : {
      sid        = "Allow${spec.sid}"
      actions    = ["kms:Decrypt", "kms:GenerateDataKey*"]
      principals = { Service = [p] }
      conditions = concat(local.source_account, [{ test = "ArnLike", variable = "aws:SourceArn", values = [spec.source_arn] }])
    }],
    [for c in [
      {
        when      = length(local.extra_signed) > 0
        statement = { sid = "AllowServicePublishers", actions = ["kms:Decrypt", "kms:GenerateDataKey*"], principals = { Service = local.extra_signed }, conditions = local.source_account }
      },
      {
        when      = local.eventbridge
        statement = { sid = "AllowEventBridge", actions = ["kms:Decrypt", "kms:GenerateDataKey*"], principals = { Service = ["events.amazonaws.com"] }, conditions = [] }
      },
    ] : c.statement if c.when],
  )

  topic_policies = {
    for key, topic in local.topics : key => jsonencode({
      Version = "2012-10-17"
      Statement = concat(
        [{
          Sid       = "AllowCloudWatchAlarmsPublish"
          Effect    = "Allow"
          Principal = { Service = "cloudwatch.amazonaws.com" }
          Action    = "sns:Publish"
          Resource  = topic.arn
          Condition = {
            StringEquals = { "aws:SourceAccount" = local.account_id }
            ArnLike      = { "aws:SourceArn" = "arn:${local.partition}:cloudwatch:${topic.region}:${local.account_id}:alarm:*" }
          }
        }],
        [for p, spec in local.scoped_publishers : {
          Sid       = "Allow${spec.sid}Publish"
          Effect    = "Allow"
          Principal = { Service = p }
          Action    = "sns:Publish"
          Resource  = topic.arn
          Condition = {
            StringEquals = { "aws:SourceAccount" = local.account_id }
            ArnLike      = { "aws:SourceArn" = spec.source_arn }
          }
        }],
        [for c in [
          {
            when = length(local.account_publishers) > 0
            statement = {
              Sid       = "AllowServicePublishFromThisAccount"
              Effect    = "Allow"
              Principal = { Service = local.account_publishers }
              Action    = "sns:Publish"
              Resource  = topic.arn
              Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
            }
          },
        ] : c.statement if c.when],
        [
          {
            Sid       = "DenyInsecureTransport"
            Effect    = "Deny"
            Principal = "*"
            Action    = "sns:Publish"
            Resource  = topic.arn
            Condition = { Bool = { "aws:SecureTransport" = "false" } }
          },
          {
            Sid       = "DenyPlaintextHttpSubscriptions"
            Effect    = "Deny"
            Principal = "*"
            Action    = "sns:Subscribe"
            Resource  = topic.arn
            Condition = { StringEquals = { "sns:Protocol" = "http" } }
          },
        ],
      )
    })
  }

  redrive_policies = { for r, arn in var.dead_letter_queue_arns : r => jsonencode({ deadLetterTargetArn = arn }) }

  email_subscriptions = {
    for item in flatten([
      for key, topic in local.topics : [
        for address in distinct(try(var.email_subscriptions[topic.severity], [])) : {
          key       = "${key}/${address}"
          topic_key = key
          region    = topic.region
          address   = address
        }
      ]
    ]) : item.key => item
  }

  https_counts = nonsensitive({ for s, endpoints in var.https_subscriptions : s => length(endpoints) })

  https_subscriptions = {
    for item in flatten([
      for key, topic in local.topics : [
        for index in range(try(local.https_counts[topic.severity], 0)) : {
          key       = "${key}/${index}"
          topic_key = key
          region    = topic.region
          severity  = topic.severity
          index     = index
        }
      ]
    ]) : item.key => item
  }

  https_delivery_policy = var.https_delivery_policy.enabled ? jsonencode(merge(
    {
      healthyRetryPolicy = {
        minDelayTarget     = var.https_delivery_policy.min_delay_target
        maxDelayTarget     = var.https_delivery_policy.max_delay_target
        numRetries         = var.https_delivery_policy.num_retries
        numNoDelayRetries  = var.https_delivery_policy.num_no_delay_retries
        numMinDelayRetries = var.https_delivery_policy.num_min_delay_retries
        numMaxDelayRetries = var.https_delivery_policy.num_max_delay_retries
        backoffFunction    = var.https_delivery_policy.backoff_function
      }
    },
    var.https_delivery_policy.max_receives_per_second == null ? {} : { throttlePolicy = { maxReceivesPerSecond = var.https_delivery_policy.max_receives_per_second } },
    var.https_delivery_policy.header_content_type == null ? {} : { requestPolicy = { headerContentType = var.https_delivery_policy.header_content_type } },
  )) : null
}
