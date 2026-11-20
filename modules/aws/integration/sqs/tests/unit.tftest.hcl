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

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    }
  }

  mock_resource "aws_sqs_queue" {
    defaults = {
      id  = "https://sqs.eu-west-1.amazonaws.com/123456789012/core-prod-orders"
      url = "https://sqs.eu-west-1.amazonaws.com/123456789012/core-prod-orders"
      arn = "arn:aws:sqs:eu-west-1:123456789012:core-prod-orders"
    }
  }
}

override_resource {
  target = aws_sqs_queue.dlq
  values = {
    id  = "https://sqs.eu-west-1.amazonaws.com/123456789012/core-prod-orders-dlq"
    url = "https://sqs.eu-west-1.amazonaws.com/123456789012/core-prod-orders-dlq"
    arn = "arn:aws:sqs:eu-west-1:123456789012:core-prod-orders-dlq"
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
    condition     = aws_sqs_queue.this.name == "core-prod-orders" && aws_sqs_queue.dlq[0].name == "core-prod-orders-dlq" && !aws_sqs_queue.this.fifo_queue
    error_message = "Queues must be named <application>-<environment>-<name>[-dlq], standard by default."
  }

  assert {
    condition     = aws_sqs_queue.this.sqs_managed_sse_enabled && aws_sqs_queue.dlq[0].sqs_managed_sse_enabled && aws_sqs_queue.this.kms_master_key_id == null && output.kms_key_arn == null
    error_message = "No kms input means SSE-SQS on both queues (SQS.1)."
  }

  assert {
    condition     = aws_sqs_queue.this.message_retention_seconds == 345600 && aws_sqs_queue.dlq[0].message_retention_seconds == 1209600 && aws_sqs_queue.this.visibility_timeout_seconds == 30
    error_message = "Defaults: 4-day retention, 14-day DLQ retention, 30 s visibility."
  }

  assert {
    condition     = length(aws_sqs_queue_redrive_policy.this) == 1 && length(aws_sqs_queue_redrive_allow_policy.this) == 1 && length(aws_sqs_queue_policy.dlq) == 1
    error_message = "The dead-letter queue, redrive and DLQ policy are on by default."
  }

  assert {
    condition     = aws_sqs_queue.this.tags["Name"] == "core-prod-orders" && aws_sqs_queue.dlq[0].tags["Name"] == "core-prod-orders-dlq" && aws_sqs_queue.this.tags["Team"] == "payments" && aws_sqs_queue.this.tags["ManagedBy"] == "Terraform" && aws_sqs_queue.this.tags["Application"] == "core"
    error_message = "Caller and governance tags must be applied; Name is the queue name (SQS.2)."
  }
}

run "governance_tags_win" {
  command = plan

  variables {
    tags = { Environment = "dev", Owner = "team-a" }
  }

  assert {
    condition     = aws_sqs_queue.this.tags["Environment"] == "prod" && aws_sqs_queue.this.tags["Owner"] == "team-a"
    error_message = "Governance tags must override caller tags."
  }
}

run "redrive_and_tls_policies" {
  command = apply

  assert {
    condition     = jsondecode(aws_sqs_queue_redrive_policy.this[0].redrive_policy).deadLetterTargetArn == "arn:aws:sqs:eu-west-1:123456789012:core-prod-orders-dlq" && jsondecode(aws_sqs_queue_redrive_policy.this[0].redrive_policy).maxReceiveCount == 3
    error_message = "The queue must redrive to its DLQ after 3 receives."
  }

  assert {
    condition     = jsondecode(aws_sqs_queue_redrive_allow_policy.this[0].redrive_allow_policy).redrivePermission == "byQueue" && jsondecode(aws_sqs_queue_redrive_allow_policy.this[0].redrive_allow_policy).sourceQueueArns == ["arn:aws:sqs:eu-west-1:123456789012:core-prod-orders"]
    error_message = "Only the source queue may use the DLQ."
  }

  assert {
    condition     = jsondecode(aws_sqs_queue_policy.this.policy).Statement[0].Sid == "DenyInsecureTransport" && jsondecode(aws_sqs_queue_policy.this.policy).Statement[0].Effect == "Deny" && jsondecode(aws_sqs_queue_policy.this.policy).Statement[0].Condition.Bool["aws:SecureTransport"] == ["false"] && jsondecode(aws_sqs_queue_policy.this.policy).Statement[0].Resource == ["arn:aws:sqs:eu-west-1:123456789012:core-prod-orders"]
    error_message = "The queue policy must deny non-TLS access to the queue."
  }

  assert {
    condition     = length(jsondecode(aws_sqs_queue_policy.this.policy).Statement) == 1 && jsondecode(aws_sqs_queue_policy.dlq[0].policy).Statement[0].Sid == "DenyInsecureTransport" && jsondecode(aws_sqs_queue_policy.dlq[0].policy).Statement[0].Resource == ["arn:aws:sqs:eu-west-1:123456789012:core-prod-orders-dlq"]
    error_message = "Both policies hold only the TLS guard by default."
  }

  assert {
    condition     = output.id == output.url && output.dlq_arn == "arn:aws:sqs:eu-west-1:123456789012:core-prod-orders-dlq" && output.dlq_name == "core-prod-orders-dlq"
    error_message = "id is the queue URL; DLQ outputs are set."
  }
}

run "publishers_and_statements" {
  command = apply

  variables {
    allowed_publishers = {
      nightly = { principal = "events.amazonaws.com", source_arn = "arn:aws:events:eu-west-1:123456789012:rule/core-prod-nightly" }
      uploads = { principal = "s3.amazonaws.com", source_arn = "arn:aws:s3:::core-prod-uploads" }
    }
    policy_statements = [{
      sid        = "AllowWorker"
      actions    = ["sqs:ReceiveMessage"]
      principals = { AWS = ["arn:aws:iam::123456789012:role/worker"] }
    }]
  }

  assert {
    condition     = [for s in jsondecode(aws_sqs_queue_policy.this.policy).Statement : s.Sid] == ["DenyInsecureTransport", "AllowPublishernightly", "AllowPublisheruploads", "AllowWorker"]
    error_message = "Guard first, then publishers, then caller statements."
  }

  assert {
    condition     = jsondecode(aws_sqs_queue_policy.this.policy).Statement[1].Action == ["sqs:SendMessage"] && jsondecode(aws_sqs_queue_policy.this.policy).Statement[1].Principal.Service == ["events.amazonaws.com"] && jsondecode(aws_sqs_queue_policy.this.policy).Statement[1].Condition.ArnEquals["aws:SourceArn"] == ["arn:aws:events:eu-west-1:123456789012:rule/core-prod-nightly"]
    error_message = "Publishers get only sqs:SendMessage, scoped by aws:SourceArn (SQS.3)."
  }

  assert {
    condition     = jsondecode(aws_sqs_queue_policy.this.policy).Statement[3].Resource == ["arn:aws:sqs:eu-west-1:123456789012:core-prod-orders"]
    error_message = "Caller statements default to the queue as resource."
  }
}

run "caller_resource_is_kept" {
  command = apply

  variables {
    policy_statements = [{
      sid        = "AllowWorker"
      actions    = ["sqs:ReceiveMessage"]
      resources  = ["arn:aws:sqs:eu-west-1:123456789012:core-prod-other"]
      principals = { AWS = ["arn:aws:iam::123456789012:role/worker"] }
    }]
  }

  assert {
    condition     = jsondecode(aws_sqs_queue_policy.this.policy).Statement[1].Resource == ["arn:aws:sqs:eu-west-1:123456789012:core-prod-other"]
    error_message = "A caller Resource is never overwritten."
  }
}

run "module_key_is_planned_safely" {
  command = plan

  variables {
    kms                = { create = true }
    allowed_publishers = { topic = { principal = "sns.amazonaws.com", source_arn = "arn:aws:sns:eu-west-1:123456789012:core-prod-orders" } }
  }

  assert {
    condition     = module.encryption.created && aws_sqs_queue.this.kms_data_key_reuse_period_seconds == 300
    error_message = "kms.create must plan without knowing the key ARN."
  }
}

run "module_key_encrypts_both_queues" {
  command = apply

  variables {
    kms = { create = true }
  }

  assert {
    condition     = aws_sqs_queue.this.kms_master_key_id == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && aws_sqs_queue.dlq[0].kms_master_key_id == aws_sqs_queue.this.kms_master_key_id && output.kms_key_arn == aws_sqs_queue.this.kms_master_key_id
    error_message = "The module key must encrypt the queue and the DLQ."
  }
}

run "caller_key_id" {
  command = plan

  variables {
    kms                               = { key_id = "11111111-2222-3333-4444-555555555555" }
    kms_data_key_reuse_period_seconds = 600
  }

  assert {
    condition     = aws_sqs_queue.this.kms_master_key_id == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && aws_sqs_queue.this.kms_data_key_reuse_period_seconds == 600
    error_message = "A key ID must be used as the key ARN."
  }
}

run "fifo_queues" {
  command   = plan
  state_key = "fifo"

  variables {
    fifo              = { enabled = true, content_based_deduplication = true, high_throughput = true }
    dead_letter_queue = { max_receive_count = 5 }
  }

  assert {
    condition     = aws_sqs_queue.this.name == "core-prod-orders.fifo" && aws_sqs_queue.dlq[0].name == "core-prod-orders-dlq.fifo" && aws_sqs_queue.this.fifo_queue && aws_sqs_queue.dlq[0].fifo_queue
    error_message = "FIFO queues end in .fifo; the DLQ is <base>-dlq.fifo."
  }

  assert {
    condition     = aws_sqs_queue.this.content_based_deduplication && aws_sqs_queue.this.deduplication_scope == "messageGroup" && aws_sqs_queue.this.fifo_throughput_limit == "perMessageGroupId"
    error_message = "FIFO options must apply."
  }
}

run "fifo_high_throughput_on" {
  command   = apply
  state_key = "fifo-toggle"

  variables {
    fifo = { enabled = true, high_throughput = true }
  }

  assert {
    condition     = aws_sqs_queue.this.deduplication_scope == "messageGroup" && aws_sqs_queue.this.fifo_throughput_limit == "perMessageGroupId"
    error_message = "High throughput scopes deduplication and throughput to the message group."
  }
}

run "fifo_high_throughput_off_again" {
  command   = plan
  state_key = "fifo-toggle"

  variables {
    fifo = { enabled = true, high_throughput = false }
  }

  assert {
    condition     = aws_sqs_queue.this.deduplication_scope == "queue" && aws_sqs_queue.this.fifo_throughput_limit == "perQueue"
    error_message = "Turning high throughput off sets the queue-wide scopes back."
  }
}

run "long_names_fit" {
  command   = plan
  state_key = "long"

  variables {
    application = "abcdefghijklmnopqrstuvwx"
    environment = "abcdefghijkl"
    name        = "abcdefghijklmnopqrstuvwxyz012345"
    fifo        = { enabled = true }
  }

  assert {
    condition     = length(aws_sqs_queue.dlq[0].name) <= 80 && endswith(aws_sqs_queue.dlq[0].name, "-dlq.fifo") && endswith(aws_sqs_queue.this.name, "abcdefghijklmnopqrstuvwxyz012345.fifo")
    error_message = "The longest names fit 80 characters and keep their suffixes."
  }
}

run "dead_letter_queue_off" {
  command   = plan
  state_key = "nodlq"

  variables {
    dead_letter_queue = { enabled = false }
  }

  assert {
    condition     = length(aws_sqs_queue.dlq) + length(aws_sqs_queue_redrive_policy.this) + length(aws_sqs_queue_redrive_allow_policy.this) + length(aws_sqs_queue_policy.dlq) == 0 && output.dlq_arn == null && output.dlq_name == null
    error_message = "dead_letter_queue.enabled = false removes the DLQ and redrive."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Orders_Queue"
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

run "rejects_fifo_options_on_standard_queue" {
  command = plan

  variables {
    fifo = { content_based_deduplication = true }
  }

  expect_failures = [var.fifo]
}

run "rejects_invalid_visibility_timeout" {
  command = plan

  variables {
    visibility_timeout_seconds = 50000
  }

  expect_failures = [var.visibility_timeout_seconds]
}

run "rejects_invalid_retention" {
  command = plan

  variables {
    message_retention_seconds = 30
  }

  expect_failures = [var.message_retention_seconds]
}

run "rejects_invalid_message_size" {
  command = plan

  variables {
    max_message_size = 512
  }

  expect_failures = [var.max_message_size]
}

run "rejects_invalid_delay" {
  command = plan

  variables {
    delay_seconds = 901
  }

  expect_failures = [var.delay_seconds]
}

run "rejects_invalid_receive_wait" {
  command = plan

  variables {
    receive_wait_time_seconds = 21
  }

  expect_failures = [var.receive_wait_time_seconds]
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

run "rejects_invalid_key_reuse_period" {
  command = plan

  variables {
    kms_data_key_reuse_period_seconds = 30
  }

  expect_failures = [var.kms_data_key_reuse_period_seconds]
}

run "rejects_invalid_max_receive_count" {
  command = plan

  variables {
    dead_letter_queue = { max_receive_count = 0 }
  }

  expect_failures = [var.dead_letter_queue]
}

run "rejects_invalid_dlq_retention" {
  command = plan

  variables {
    dead_letter_queue = { message_retention_seconds = 2000000 }
  }

  expect_failures = [var.dead_letter_queue]
}

run "rejects_unknown_publisher" {
  command = plan

  variables {
    allowed_publishers = { any = { principal = "lambda.amazonaws.com", source_arn = "arn:aws:lambda:eu-west-1:123456789012:function:x" } }
  }

  expect_failures = [var.allowed_publishers]
}
