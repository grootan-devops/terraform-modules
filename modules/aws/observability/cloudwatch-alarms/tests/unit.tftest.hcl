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

  mock_resource "aws_cloudwatch_metric_alarm" {
    defaults = {
      arn = "arn:aws:cloudwatch:eu-west-1:123456789012:alarm:mock-alarm"
    }
  }
}

variables {
  application = "core"
  environment = "prod"
  name        = "monitoring"

  alarms = {
    custom-queue-depth = {
      description         = "Custom single-metric alarm."
      comparison_operator = "GreaterThanThreshold"
      threshold           = 100
      evaluation_periods  = 3
      namespace           = "Custom/App"
      metric_name         = "QueueDepth"
      dimensions          = { Service = "billing" }
      statistic           = "Maximum"
    }
    custom-error-ratio = {
      comparison_operator = "GreaterThanOrEqualToThreshold"
      threshold           = 2
      evaluation_periods  = 5
      datapoints_to_alarm = 3
      treat_missing_data  = "notBreaching"
      metric_queries = [
        { id = "failed", metric = { namespace = "Custom/App", metric_name = "Failed", stat = "Sum" } },
        { id = "total", metric = { namespace = "Custom/App", metric_name = "Total", stat = "Sum", period = 300 } },
        { id = "ratio", expression = "IF(total > 0, 100 * failed / total, 0)", label = "Failure ratio", return_data = true },
      ]
    }
  }

  lambda_functions = {
    orders = { function_name = "core-prod-orders", timeout_seconds = 30 }
    stream = { function_name = "core-prod-stream", timeout_seconds = 60, event_source = "stream" }
  }

  api_gateways = {
    public = { api_name = "core-prod-api", stage = "v1" }
  }

  albs = {
    web = {
      load_balancer_arn_suffix = "app/core-prod-web/50dc6c495c0c9188"
      target_groups = {
        api = "targetgroup/core-prod-api/73e2d6bc24d8a067"
        ui  = "targetgroup/core-prod-ui/1234567890abcdef"
      }
    }
  }

  ecs_services = {
    api    = { cluster_name = "core-prod", service_name = "api" }
    worker = { cluster_name = "core-prod", service_name = "worker", container_insights = true }
  }

  eks_clusters = {
    main = { cluster_name = "core-prod", container_insights = true }
    off  = { cluster_name = "core-dev" }
  }

  auto_scaling_groups = {
    nodes = { auto_scaling_group_name = "eks-core-prod-nodes-0123" }
  }

  rds_instances = {
    main = { db_instance_identifier = "core-prod-db", allocated_storage_gib = 20 }
  }

  rds_proxies = {
    main = { proxy_name = "core-prod-proxy" }
  }

  dynamodb_tables = {
    orders = { table_name = "core-prod-orders", global_secondary_index_names = ["by-customer"] }
  }

  elasticache_clusters = {
    cache = { replication_group_id = "core-prod-cache", cache_cluster_ids = ["core-prod-cache-001", "core-prod-cache-002"] }
  }

  sqs_queues = {
    jobs = { queue_name = "core-prod-jobs", dlq_name = "core-prod-jobs-dlq", alarms = { age_of_oldest_message = { threshold = 300 } } }
  }

  eventbridge_rules = {
    nightly = { rule_name = "core-prod-nightly" }
    orders  = { rule_name = "core-prod-orders", event_bus_name = "core-prod-bus" }
  }

  nlbs = {
    edge = {
      load_balancer_arn_suffix = "net/core-prod-edge/50dc6c495c0c9188"
      target_groups            = { tcp = "targetgroup/core-prod-tcp/73e2d6bc24d8a067" }
    }
  }

  http_apis = {
    public = { api_id = "a1b2c3d4e5" }
  }

  schedule_groups = {
    jobs = { schedule_group_name = "core-prod-jobs" }
  }

  step_functions = {
    flow = { state_machine_arn = "arn:aws:states:eu-west-1:123456789012:stateMachine:core-prod-flow" }
  }

  cloudfront_distributions = {
    site = { distribution_id = "E2QWRUHAPOMQZL" }
  }

  efs_file_systems = {
    shared = { file_system_id = "fs-0123456789abcdef0" }
    burst  = { file_system_id = "fs-0fedcba9876543210", throughput_mode = "bursting" }
  }

  waf_web_acls = {
    regional = { web_acl_metric_name = "core-prod-waf-acl-metric", alarms = { blocked_requests = { threshold = 1000 } } }
    edge     = { web_acl_metric_name = "core-prod-edge-acl-metric", scope = "CLOUDFRONT", alarms = { blocked_requests = { threshold = 5000 } } }
  }

  s3_buckets = {
    assets = { bucket_name = "core-prod-assets", alarms = { bucket_size = { threshold = 1099511627776 } } }
  }

  nat_gateways = {
    zonal    = { nat_gateway_id = "nat-0123456789abcdef0" }
    regional = { nat_gateway_id = "nat-0fedcba9876543210", availability_zones = ["eu-west-1a", "eu-west-1b"] }
  }

  log_metric_filters = {
    app-errors = { log_group_name = "/aws/lambda/core-prod-orders", pattern = "ERROR" }
  }
}

run "no_notifications_on_every_alarm" {
  command = plan

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.this) == 84
    error_message = "The broad preset load must create exactly 84 alarms (guards the alltrue checks against an empty map)."
  }

  assert {
    condition     = alltrue([for k, a in aws_cloudwatch_metric_alarm.this : a.actions_enabled == false])
    error_message = "Every alarm must have actions_enabled = false."
  }

  assert {
    condition     = alltrue([for k, a in aws_cloudwatch_metric_alarm.this : length(a.alarm_actions) == 0 && length(a.ok_actions) == 0 && length(a.insufficient_data_actions) == 0])
    error_message = "Every alarm must have empty alarm_actions, ok_actions and insufficient_data_actions."
  }

  assert {
    condition = alltrue([
      for p in ["alarms", "lambda_functions", "api_gateways", "albs", "nlbs", "http_apis", "ecs_services", "eks_clusters", "auto_scaling_groups", "rds_instances", "rds_proxies", "dynamodb_tables", "elasticache_clusters", "sqs_queues", "eventbridge_rules", "schedule_groups", "step_functions", "cloudfront_distributions", "efs_file_systems", "waf_web_acls", "s3_buckets", "nat_gateways", "log_metric_filters"] : length(output.presets[p]) > 0
    ])
    error_message = "The broad load must produce at least one alarm for every input."
  }

  assert {
    condition     = length(output.presets["cis_cloudtrail_metric_filters"]) == 0 && length(output.presets["lambda_functions"]) == 7 && length(output.presets["elasticache_clusters"]) == 10 && length(output.presets["nat_gateways"]) == 6
    error_message = "Presets summary output must list the alarm keys per input."
  }

  assert {
    condition     = alltrue([for k, r in output.alarm_routes : r.topic_arn == null])
    error_message = "No alarm may resolve a topic while notifications are disabled."
  }
}

run "default_severities_and_regions" {
  command = plan

  assert {
    condition = alltrue([
      for k in ["lambda-orders-error-rate", "apigw-public-5xx-rate", "alb-web-api-unhealthy-hosts", "alb-web-target-5xx-rate", "alb-web-elb-5xx-count", "ecs-worker-running-tasks", "eks-main-failed-nodes", "asg-nodes-status-check-failed", "rdsproxy-main-connection-setup-failures", "dynamodb-orders-system-errors", "sqs-jobs-dlq-messages-visible", "eventbridge-nightly-failed-invocations", "eventbridge-nightly-dlq-send-failures", "sfn-flow-executions-failed", "sfn-flow-executions-timed-out", "cloudfront-site-5xx-error-rate", "nat-zonal-error-port-allocation"] : output.alarm_routes[k].severity == "critical"
    ])
    error_message = "Error, unhealthy, DLQ and failed-execution alarms must default to critical."
  }

  assert {
    condition = alltrue([
      for k in ["lambda-orders-throttles", "lambda-orders-duration-p99", "apigw-public-4xx-rate", "apigw-public-latency-p99", "alb-web-target-response-time-p99", "ecs-api-cpu", "ecs-api-memory", "eks-main-node-cpu", "rds-main-cpu", "rds-main-read-latency-p99", "dynamodb-orders-read-throttles", "elasticache-cache-core-prod-cache-001-engine-cpu", "sqs-jobs-age-of-oldest-message", "eventbridge-nightly-throttled-rules", "sfn-flow-execution-throttled", "efs-shared-percent-io-limit", "waf-regional-blocked-requests", "nat-zonal-packets-drop-rate", "custom-queue-depth", "custom-error-ratio", "log-app-errors"] : output.alarm_routes[k].severity == "warning"
    ])
    error_message = "Latency, CPU, memory, throttle, generic and log alarms must default to warning."
  }

  assert {
    condition     = output.alarm_routes["s3-assets-bucket-size"].severity == "info"
    error_message = "Capacity-planning alarms (S3 bucket size) must default to info."
  }

  assert {
    condition     = output.alarm_routes["lambda-orders-error-rate"].region == "eu-west-1" && output.alarm_routes["cloudfront-site-5xx-error-rate"].region == "us-east-1" && output.alarm_routes["waf-edge-blocked-requests"].region == "us-east-1"
    error_message = "Alarms without a region must resolve to the provider Region; CloudFront alarms to us-east-1."
  }
}

run "routing_enabled_uses_topic_per_region_and_severity" {
  command = plan

  variables {
    cis_cloudtrail_metric_filters = {
      enabled        = true
      log_group_name = "core-prod-cloudtrail"
    }
    notifications = {
      enabled = true
      topic_arns = {
        "eu-west-1" = {
          critical = "arn:aws:sns:eu-west-1:123456789012:core-prod-alerts-critical"
          warning  = "arn:aws:sns:eu-west-1:123456789012:core-prod-alerts-warning"
          info     = "arn:aws:sns:eu-west-1:123456789012:core-prod-alerts-info"
        }
        "us-east-1" = {
          critical = "arn:aws:sns:us-east-1:123456789012:core-prod-alerts-critical"
          warning  = "arn:aws:sns:us-east-1:123456789012:core-prod-alerts-warning"
          info     = "arn:aws:sns:us-east-1:123456789012:core-prod-alerts-info"
        }
      }
    }
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.this) == 98 && alltrue([for k, a in aws_cloudwatch_metric_alarm.this : a.actions_enabled == true])
    error_message = "Every alarm must have actions_enabled = true when notifications are enabled."
  }

  assert {
    condition     = alltrue([for k, a in aws_cloudwatch_metric_alarm.this : a.alarm_actions == toset([var.notifications.topic_arns[output.alarm_routes[k].region][output.alarm_routes[k].severity]])])
    error_message = "Every alarm's ALARM action must be the topic of its Region and severity."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["lambda-orders-error-rate"].alarm_actions == toset(["arn:aws:sns:eu-west-1:123456789012:core-prod-alerts-critical"]) && aws_cloudwatch_metric_alarm.this["lambda-orders-throttles"].alarm_actions == toset(["arn:aws:sns:eu-west-1:123456789012:core-prod-alerts-warning"]) && aws_cloudwatch_metric_alarm.this["s3-assets-bucket-size"].alarm_actions == toset(["arn:aws:sns:eu-west-1:123456789012:core-prod-alerts-info"])
    error_message = "Severity must select the critical, warning or info topic."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["cloudfront-site-5xx-error-rate"].alarm_actions == toset(["arn:aws:sns:us-east-1:123456789012:core-prod-alerts-critical"]) && aws_cloudwatch_metric_alarm.this["waf-edge-blocked-requests"].alarm_actions == toset(["arn:aws:sns:us-east-1:123456789012:core-prod-alerts-warning"])
    error_message = "CloudFront and CLOUDFRONT-scope WAF alarms must route to the us-east-1 topic."
  }

  assert {
    condition     = alltrue([for k, a in aws_cloudwatch_metric_alarm.this : a.ok_actions == a.alarm_actions && length(a.insufficient_data_actions) == 0])
    error_message = "By default OK actions must notify the same topic and INSUFFICIENT_DATA actions must stay empty."
  }

  assert {
    condition     = output.alarm_routes["cis-cloudwatch-1"].topic_arn == "arn:aws:sns:eu-west-1:123456789012:core-prod-alerts-critical"
    error_message = "alarm_routes must expose the topic each alarm uses."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["cis-cloudwatch-1"].alarm_description == "CIS CloudWatch.1: A log metric filter and alarm should exist for usage of the \"root\" user." && output.alarm_routes["cis-cloudwatch-14"].severity == "critical" && output.alarm_routes["cis-cloudwatch-1"].region == "eu-west-1"
    error_message = "CIS alarms describe their control, default to critical and live in the provider Region."
  }
}

run "routing_ok_off_insufficient_data_on" {
  command = plan

  variables {
    lambda_functions = {
      orders = { function_name = "core-prod-orders", timeout_seconds = 30 }
    }
    notifications = {
      enabled                     = true
      notify_on_ok                = false
      notify_on_insufficient_data = true
      topic_arns = {
        "eu-west-1" = {
          critical = "arn:aws:sns:eu-west-1:123456789012:core-prod-alerts-critical"
          warning  = "arn:aws:sns:eu-west-1:123456789012:core-prod-alerts-warning"
          info     = "arn:aws:sns:eu-west-1:123456789012:core-prod-alerts-info"
        }
        "us-east-1" = {
          critical = "arn:aws:sns:us-east-1:123456789012:core-prod-alerts-critical"
          warning  = "arn:aws:sns:us-east-1:123456789012:core-prod-alerts-warning"
          info     = "arn:aws:sns:us-east-1:123456789012:core-prod-alerts-info"
        }
      }
    }
  }

  assert {
    condition     = alltrue([for k, a in aws_cloudwatch_metric_alarm.this : length(a.ok_actions) == 0 && a.insufficient_data_actions == a.alarm_actions && length(a.alarm_actions) == 1])
    error_message = "notify_on_ok = false must empty OK actions; notify_on_insufficient_data = true must add the topic as INSUFFICIENT_DATA action."
  }
}

run "routing_severity_overrides" {
  command = plan

  variables {
    alarms = {
      custom-queue-depth = {
        severity            = "critical"
        comparison_operator = "GreaterThanThreshold"
        threshold           = 100
        evaluation_periods  = 3
        namespace           = "Custom/App"
        metric_name         = "QueueDepth"
        statistic           = "Maximum"
      }
    }
    lambda_functions = {
      orders = { function_name = "core-prod-orders", timeout_seconds = 30, alarms = { error_rate = { severity = "warning" }, throttles = { severity = "info" } } }
    }
    log_metric_filters = {
      app-errors = { log_group_name = "/aws/lambda/core-prod-orders", pattern = "ERROR", alarm = { severity = "info" } }
    }
    cis_cloudtrail_metric_filters = {
      enabled        = true
      log_group_name = "core-prod-cloudtrail"
      severity       = "warning"
    }
    notifications = {
      enabled = true
      topic_arns = {
        "eu-west-1" = {
          critical = "arn:aws:sns:eu-west-1:123456789012:core-prod-alerts-critical"
          warning  = "arn:aws:sns:eu-west-1:123456789012:core-prod-alerts-warning"
          info     = "arn:aws:sns:eu-west-1:123456789012:core-prod-alerts-info"
        }
        "us-east-1" = {
          critical = "arn:aws:sns:us-east-1:123456789012:core-prod-alerts-critical"
          warning  = "arn:aws:sns:us-east-1:123456789012:core-prod-alerts-warning"
          info     = "arn:aws:sns:us-east-1:123456789012:core-prod-alerts-info"
        }
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["custom-queue-depth"].alarm_actions == toset(["arn:aws:sns:eu-west-1:123456789012:core-prod-alerts-critical"])
    error_message = "A generic alarm's severity must select its topic."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["lambda-orders-error-rate"].alarm_actions == toset(["arn:aws:sns:eu-west-1:123456789012:core-prod-alerts-warning"]) && aws_cloudwatch_metric_alarm.this["lambda-orders-throttles"].alarm_actions == toset(["arn:aws:sns:eu-west-1:123456789012:core-prod-alerts-info"])
    error_message = "Preset severities must be overridable per alarm."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["log-app-errors"].alarm_actions == toset(["arn:aws:sns:eu-west-1:123456789012:core-prod-alerts-info"]) && alltrue([for k, a in aws_cloudwatch_metric_alarm.this : a.alarm_actions == toset(["arn:aws:sns:eu-west-1:123456789012:core-prod-alerts-warning"]) if startswith(k, "cis-")])
    error_message = "Log filter and CIS alarm severities must be overridable."
  }
}

run "routing_missing_topic_fails" {
  command = plan

  variables {
    notifications = {
      enabled = true
      topic_arns = {
        "eu-west-1" = {
          critical = "arn:aws:sns:eu-west-1:123456789012:core-prod-alerts-critical"
          warning  = "arn:aws:sns:eu-west-1:123456789012:core-prod-alerts-warning"
          info     = "arn:aws:sns:eu-west-1:123456789012:core-prod-alerts-info"
        }
      }
    }
  }

  expect_failures = [aws_cloudwatch_metric_alarm.this]
}

run "naming_renders_application_environment_name_key" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["custom-queue-depth"].alarm_name == "core-prod-monitoring-custom-queue-depth"
    error_message = "Alarm name must be <application>-<environment>-<name>-<key>."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["lambda-orders-error-rate"].alarm_name == "core-prod-monitoring-lambda-orders-error-rate"
    error_message = "Preset alarm keys must be <preset>-<resource key>-<alarm>."
  }

  assert {
    condition     = output.alarm_names["custom-queue-depth"] == "core-prod-monitoring-custom-queue-depth"
    error_message = "alarm_names output must map key to alarm name."
  }

  assert {
    condition     = aws_cloudwatch_log_metric_filter.this["app-errors"].name == "core-prod-monitoring-log-app-errors"
    error_message = "Metric filter names must be <application>-<environment>-<name>-log-<key>."
  }
}

run "naming_falls_back_when_name_is_null" {
  command = plan

  variables {
    name = null
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["custom-queue-depth"].alarm_name == "core-prod-custom-queue-depth"
    error_message = "With a null name the alarm name must be <application>-<environment>-<key>."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["custom-queue-depth"].tags["Name"] == "core-prod-custom-queue-depth"
    error_message = "Name tag must follow the alarm name."
  }
}

run "rejects_empty_name" {
  command = plan

  variables {
    name = ""
  }

  expect_failures = [var.name]
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Monitoring_1"
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

run "naming_truncates_names_over_255_characters" {
  command = plan

  variables {
    alarms = {
      aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa = {
        comparison_operator = "GreaterThanThreshold"
        threshold           = 1
        evaluation_periods  = 1
        namespace           = "Custom/App"
        metric_name         = "Errors"
        statistic           = "Sum"
      }
    }
  }

  assert {
    condition     = length(output.alarm_names["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"]) == 255
    error_message = "Alarm names longer than 255 characters must be truncated to exactly 255."
  }

  assert {
    condition     = output.alarm_names["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"] == "${substr("core-prod-monitoring-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", 0, 248)}-${substr(md5("core-prod-monitoring-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"), 0, 6)}"
    error_message = "Truncated alarm names must keep a 248-character prefix plus a 6-character md5 suffix of the full name."
  }
}

run "tags_governance_caller_and_precedence" {
  command = plan

  variables {
    tags = {
      Team        = "platform"
      Environment = "caller-override-attempt"
      ManagedBy   = "someone-else"
    }
  }

  assert {
    condition = alltrue([
      for k, a in aws_cloudwatch_metric_alarm.this : a.tags["Application"] == "core" && a.tags["Environment"] == "prod" && a.tags["ManagedBy"] == "Terraform" && a.tags["Name"] == a.alarm_name
    ])
    error_message = "Every alarm must carry Application, Environment, ManagedBy = Terraform and Name = alarm name."
  }

  assert {
    condition     = alltrue([for k, a in aws_cloudwatch_metric_alarm.this : a.tags["Team"] == "platform"])
    error_message = "Caller tags must be preserved on every alarm."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["rds-main-cpu"].tags["Environment"] == "prod" && aws_cloudwatch_metric_alarm.this["rds-main-cpu"].tags["ManagedBy"] == "Terraform"
    error_message = "Governance tags must win over caller tags with the same key."
  }
}

run "defaults_compute_lambda_api_alb" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["lambda-orders-error-rate"].threshold == 5 && aws_cloudwatch_metric_alarm.this["lambda-orders-error-rate"].evaluation_periods == 3
    error_message = "Lambda error rate default must be > 5 % over 3 periods."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["lambda-orders-throttles"].threshold == 0 && aws_cloudwatch_metric_alarm.this["lambda-orders-throttles"].metric_name == "Throttles" && aws_cloudwatch_metric_alarm.this["lambda-orders-throttles"].dimensions["FunctionName"] == "core-prod-orders"
    error_message = "Lambda throttles default must be Throttles > 0 on FunctionName."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["lambda-orders-duration-p99"].threshold == 24000 && aws_cloudwatch_metric_alarm.this["lambda-orders-duration-p99"].extended_statistic == "p99" && aws_cloudwatch_metric_alarm.this["lambda-orders-duration-p99"].statistic == null
    error_message = "Lambda Duration p99 default must be 80 % of timeout_seconds in ms (30 s -> 24000 ms)."
  }

  assert {
    condition     = !contains(keys(aws_cloudwatch_metric_alarm.this), "lambda-orders-iterator-age") && aws_cloudwatch_metric_alarm.this["lambda-stream-iterator-age"].threshold == 60000
    error_message = "IteratorAge must exist only for event_source = stream (default 60000 ms)."
  }

  assert {
    condition     = !contains(keys(aws_cloudwatch_metric_alarm.this), "lambda-orders-concurrent-executions")
    error_message = "ConcurrentExecutions must be off by default."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["apigw-public-5xx-rate"].threshold == 5 && aws_cloudwatch_metric_alarm.this["apigw-public-4xx-rate"].threshold == 5 && aws_cloudwatch_metric_alarm.this["apigw-public-latency-p99"].threshold == 2500 && aws_cloudwatch_metric_alarm.this["apigw-public-integration-latency-p99"].threshold == 2000
    error_message = "API Gateway defaults must be 5 % / 5 % / 2500 ms / 2000 ms."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["apigw-public-latency-p99"].dimensions["ApiName"] == "core-prod-api" && aws_cloudwatch_metric_alarm.this["apigw-public-latency-p99"].dimensions["Stage"] == "v1"
    error_message = "API Gateway alarms must use ApiName + Stage dimensions."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["alb-web-api-unhealthy-hosts"].threshold == 0 && aws_cloudwatch_metric_alarm.this["alb-web-api-unhealthy-hosts"].dimensions["TargetGroup"] == "targetgroup/core-prod-api/73e2d6bc24d8a067" && aws_cloudwatch_metric_alarm.this["alb-web-ui-unhealthy-hosts"].dimensions["LoadBalancer"] == "app/core-prod-web/50dc6c495c0c9188"
    error_message = "ALB UnHealthyHostCount > 0 must exist per target group with LoadBalancer + TargetGroup ARN suffixes."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["alb-web-target-response-time-p99"].threshold == 48 && aws_cloudwatch_metric_alarm.this["alb-web-elb-5xx-count"].metric_name == "HTTPCode_ELB_5XX_Count" && aws_cloudwatch_metric_alarm.this["alb-web-rejected-connections"].threshold == 0
    error_message = "ALB TargetResponseTime p99 default must be 80 % of the 60 s idle timeout; ELB 5XX and RejectedConnectionCount must exist."
  }
}

run "defaults_containers_and_hosts" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["ecs-api-cpu"].threshold == 80 && aws_cloudwatch_metric_alarm.this["ecs-api-memory"].threshold == 80 && aws_cloudwatch_metric_alarm.this["ecs-api-cpu"].namespace == "AWS/ECS"
    error_message = "ECS CPU/memory defaults must be > 80 % in AWS/ECS."
  }

  assert {
    condition     = !contains(keys(aws_cloudwatch_metric_alarm.this), "ecs-api-running-tasks") && contains(keys(aws_cloudwatch_metric_alarm.this), "ecs-worker-running-tasks")
    error_message = "ECS running-tasks alarm must exist only when container_insights = true."
  }

  assert {
    condition     = one([for q in aws_cloudwatch_metric_alarm.this["ecs-worker-running-tasks"].metric_query : q.expression if q.return_data]) == "desired - running" && alltrue([for q in aws_cloudwatch_metric_alarm.this["ecs-worker-running-tasks"].metric_query : q.return_data ? true : one(q.metric).namespace == "ECS/ContainerInsights"])
    error_message = "ECS running-tasks alarm must compare DesiredTaskCount and RunningTaskCount from ECS/ContainerInsights."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["eks-main-node-cpu"].threshold == 80 && aws_cloudwatch_metric_alarm.this["eks-main-node-memory"].threshold == 80 && aws_cloudwatch_metric_alarm.this["eks-main-failed-nodes"].metric_name == "cluster_failed_node_count" && aws_cloudwatch_metric_alarm.this["eks-main-node-cpu"].namespace == "ContainerInsights"
    error_message = "EKS Container Insights defaults must be node CPU/memory > 80 % and failed nodes > 0."
  }

  assert {
    condition     = length([for k in keys(aws_cloudwatch_metric_alarm.this) : k if startswith(k, "eks-off-")]) == 0
    error_message = "EKS alarms must not be created without the Container Insights prerequisite flag."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["asg-nodes-cpu"].threshold == 80 && aws_cloudwatch_metric_alarm.this["asg-nodes-cpu"].period == 300 && aws_cloudwatch_metric_alarm.this["asg-nodes-status-check-failed"].dimensions["AutoScalingGroupName"] == "eks-core-prod-nodes-0123"
    error_message = "ASG defaults must be CPU > 80 % over 300 s and StatusCheckFailed on AutoScalingGroupName."
  }
}

run "defaults_databases_and_caches" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["rds-main-cpu"].threshold == 80 && aws_cloudwatch_metric_alarm.this["rds-main-read-latency-p99"].threshold == 0.02 && aws_cloudwatch_metric_alarm.this["rds-main-write-latency-p99"].extended_statistic == "p99"
    error_message = "RDS defaults must be CPU > 80 % and Read/WriteLatency p99 > 0.02 s."
  }

  assert {
    condition     = !contains(keys(aws_cloudwatch_metric_alarm.this), "rds-main-freeable-memory") && !contains(keys(aws_cloudwatch_metric_alarm.this), "rds-main-connections")
    error_message = "RDS FreeableMemory and DatabaseConnections alarms must be opt-in."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["rdsproxy-main-connection-setup-failures"].metric_name == "DatabaseConnectionsSetupFailed" && aws_cloudwatch_metric_alarm.this["rdsproxy-main-borrowed-connections"].threshold == 80 && aws_cloudwatch_metric_alarm.this["rdsproxy-main-client-auth-failures"].dimensions["ProxyName"] == "core-prod-proxy"
    error_message = "RDS Proxy defaults must cover setup failures, auth failures and borrowed connections > 80 %."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["dynamodb-orders-read-throttles"].threshold == 0 && aws_cloudwatch_metric_alarm.this["dynamodb-orders-gsi-by-customer-write-throttles"].dimensions["GlobalSecondaryIndexName"] == "by-customer"
    error_message = "DynamoDB throttle alarms must exist for the table and each GSI."
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.this["dynamodb-orders-system-errors"].metric_query) == 11 && alltrue([for q in aws_cloudwatch_metric_alarm.this["dynamodb-orders-system-errors"].metric_query : q.return_data ? true : one(q.metric).dimensions["Operation"] != ""])
    error_message = "DynamoDB SystemErrors must sum 10 TableName + Operation metrics (SystemErrors is not published on TableName alone)."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["elasticache-cache-core-prod-cache-001-engine-cpu"].threshold == 80 && aws_cloudwatch_metric_alarm.this["elasticache-cache-core-prod-cache-002-memory"].metric_name == "DatabaseMemoryUsagePercentage" && aws_cloudwatch_metric_alarm.this["elasticache-cache-core-prod-cache-001-cpu"].dimensions["CacheNodeId"] == "0001"
    error_message = "ElastiCache defaults must be per member cluster: CPU/EngineCPU/memory > 80 %."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["elasticache-cache-core-prod-cache-002-replication-lag"].treat_missing_data == "notBreaching" && aws_cloudwatch_metric_alarm.this["elasticache-cache-core-prod-cache-001-evictions"].threshold == 0
    error_message = "ElastiCache ReplicationLag must tolerate missing data from the primary; Evictions > 0."
  }
}

run "defaults_integration_edge_storage_network" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["sqs-jobs-age-of-oldest-message"].threshold == 300 && aws_cloudwatch_metric_alarm.this["sqs-jobs-dlq-messages-visible"].threshold == 0 && aws_cloudwatch_metric_alarm.this["sqs-jobs-dlq-messages-visible"].dimensions["QueueName"] == "core-prod-jobs-dlq"
    error_message = "SQS must alarm on the given age threshold and on any visible DLQ message."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["eventbridge-nightly-failed-invocations"].dimensions == tomap({ RuleName = "core-prod-nightly" }) && aws_cloudwatch_metric_alarm.this["eventbridge-orders-throttled-rules"].dimensions["EventBusName"] == "core-prod-bus"
    error_message = "EventBridge alarms must use RuleName on the default bus and EventBusName + RuleName on a custom bus."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["eventbridge-orders-dlq-send-failures"].metric_name == "InvocationsFailedToBeSentToDlq" && aws_cloudwatch_metric_alarm.this["eventbridge-orders-failed-invocations"].threshold == 0
    error_message = "EventBridge FailedInvocations and InvocationsFailedToBeSentToDlq must alarm above 0."
  }

  assert {
    condition     = alltrue([for m in ["executions-failed", "executions-timed-out", "executions-aborted", "execution-throttled"] : aws_cloudwatch_metric_alarm.this["sfn-flow-${m}"].threshold == 0 && aws_cloudwatch_metric_alarm.this["sfn-flow-${m}"].namespace == "AWS/States"])
    error_message = "Step Functions must alarm on failed, timed-out, aborted and throttled executions above 0."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["cloudfront-site-5xx-error-rate"].threshold == 5 && !contains(keys(aws_cloudwatch_metric_alarm.this), "cloudfront-site-4xx-error-rate") && !contains(keys(aws_cloudwatch_metric_alarm.this), "cloudfront-site-requests")
    error_message = "CloudFront 5xxErrorRate > 5 must be on by default; 4xx rate and Requests opt-in."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["efs-shared-percent-io-limit"].threshold == 95 && !contains(keys(aws_cloudwatch_metric_alarm.this), "efs-shared-burst-credit-balance") && aws_cloudwatch_metric_alarm.this["efs-burst-burst-credit-balance"].comparison_operator == "LessThanOrEqualToThreshold"
    error_message = "EFS PercentIOLimit > 95 by default; BurstCreditBalance only in bursting mode."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["waf-regional-blocked-requests"].dimensions["Region"] == "eu-west-1" && aws_cloudwatch_metric_alarm.this["waf-regional-blocked-requests"].dimensions["Rule"] == "ALL" && !contains(keys(aws_cloudwatch_metric_alarm.this["waf-edge-blocked-requests"].dimensions), "Region")
    error_message = "WAF REGIONAL alarms need the Region dimension (provider Region by default); CLOUDFRONT ones must not."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["s3-assets-bucket-size"].period == 86400 && aws_cloudwatch_metric_alarm.this["s3-assets-bucket-size"].dimensions["StorageType"] == "StandardStorage" && aws_cloudwatch_metric_alarm.this["s3-assets-bucket-size"].threshold == 1099511627776
    error_message = "S3 BucketSizeBytes must use StorageType StandardStorage and a daily period."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["nat-zonal-error-port-allocation"].threshold == 0 && aws_cloudwatch_metric_alarm.this["nat-zonal-packets-drop-rate"].threshold == 0.01 && aws_cloudwatch_metric_alarm.this["nat-regional-eu-west-1b-error-port-allocation"].dimensions["AvailabilityZone"] == "eu-west-1b"
    error_message = "NAT defaults must be ErrorPortAllocation > 0 and drop rate > 0.01 %; regional gateways alarm per AZ."
  }
}

run "overrides_thresholds_and_evaluation" {
  command = plan

  variables {
    lambda_functions = {
      orders = {
        function_name   = "core-prod-orders"
        timeout_seconds = 30
        alarms = {
          error_rate            = { threshold = 1, evaluation_periods = 10, datapoints_to_alarm = 2, period = 300 }
          duration_p99          = { threshold = 1500 }
          concurrent_executions = { enabled = true, threshold = 50 }
        }
      }
    }
    rds_instances = {
      main = {
        db_instance_identifier = "core-prod-db"
        allocated_storage_gib  = 20
        alarms = {
          cpu             = { threshold = 90 }
          free_storage    = { threshold = 1000000000 }
          freeable_memory = { enabled = true, threshold = 268435456 }
        }
      }
    }
    albs = {
      web = {
        load_balancer_arn_suffix = "app/core-prod-web/50dc6c495c0c9188"
        idle_timeout_seconds     = 120
        alarms                   = { elb_5xx_count = { threshold = 25 } }
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["lambda-orders-error-rate"].threshold == 1 && aws_cloudwatch_metric_alarm.this["lambda-orders-error-rate"].evaluation_periods == 10 && aws_cloudwatch_metric_alarm.this["lambda-orders-error-rate"].datapoints_to_alarm == 2
    error_message = "Per-alarm threshold, evaluation_periods and datapoints_to_alarm overrides must apply."
  }

  assert {
    condition     = alltrue([for q in aws_cloudwatch_metric_alarm.this["lambda-orders-error-rate"].metric_query : length(q.metric) == 0 ? true : one(q.metric).period == 300])
    error_message = "A period override on a metric-math alarm must apply to every metric query."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["lambda-orders-duration-p99"].threshold == 1500 && aws_cloudwatch_metric_alarm.this["lambda-orders-concurrent-executions"].threshold == 50
    error_message = "Explicit thresholds must win over computed defaults; opt-in alarms must be created when enabled."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["rds-main-cpu"].threshold == 90 && aws_cloudwatch_metric_alarm.this["rds-main-free-storage"].threshold == 1000000000 && aws_cloudwatch_metric_alarm.this["rds-main-freeable-memory"].threshold == 268435456
    error_message = "RDS overrides must apply."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["alb-web-target-response-time-p99"].threshold == 96 && aws_cloudwatch_metric_alarm.this["alb-web-elb-5xx-count"].threshold == 25
    error_message = "ALB TargetResponseTime default must follow idle_timeout_seconds; ELB 5XX override must apply."
  }
}

run "metric_math_expressions_and_return_data" {
  command = plan

  assert {
    condition     = one([for q in aws_cloudwatch_metric_alarm.this["lambda-orders-error-rate"].metric_query : q.expression if q.return_data]) == "IF(invocations > 0, 100 * errors / invocations, 0)"
    error_message = "Lambda error rate must be the zero-guarded IF expression and the only return_data query."
  }

  assert {
    condition     = length([for q in aws_cloudwatch_metric_alarm.this["lambda-orders-error-rate"].metric_query : q if q.return_data]) == 1 && toset([for q in aws_cloudwatch_metric_alarm.this["lambda-orders-error-rate"].metric_query : one(q.metric).metric_name if !q.return_data]) == toset(["Errors", "Invocations"])
    error_message = "Lambda error rate must read Errors and Invocations without returning them."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["lambda-orders-error-rate"].metric_name == null && aws_cloudwatch_metric_alarm.this["lambda-orders-error-rate"].period == null && aws_cloudwatch_metric_alarm.this["lambda-orders-error-rate"].statistic == null
    error_message = "Metric-math alarms must not set metric_name, period or statistic at the alarm level."
  }

  assert {
    condition     = one([for q in aws_cloudwatch_metric_alarm.this["apigw-public-5xx-rate"].metric_query : q.expression if q.return_data]) == "IF(requests > 0, 100 * errors / requests, 0)" && one([for q in aws_cloudwatch_metric_alarm.this["apigw-public-5xx-rate"].metric_query : one(q.metric).stat if q.id == "requests"]) == "SampleCount" && one([for q in aws_cloudwatch_metric_alarm.this["apigw-public-5xx-rate"].metric_query : one(q.metric).metric_name if q.id == "errors"]) == "5XXError"
    error_message = "API Gateway 5XX rate must divide 5XXError (Sum) by Count (SampleCount) with a zero guard."
  }

  assert {
    condition     = one([for q in aws_cloudwatch_metric_alarm.this["alb-web-target-5xx-rate"].metric_query : q.expression if q.return_data]) == "IF(requests > 0, 100 * errors / requests, 0)" && one([for q in aws_cloudwatch_metric_alarm.this["alb-web-target-5xx-rate"].metric_query : one(q.metric).metric_name if q.id == "errors"]) == "HTTPCode_Target_5XX_Count" && one([for q in aws_cloudwatch_metric_alarm.this["alb-web-target-5xx-rate"].metric_query : one(q.metric).metric_name if q.id == "requests"]) == "RequestCount"
    error_message = "ALB target 5XX rate must divide HTTPCode_Target_5XX_Count by RequestCount with a zero guard."
  }

  assert {
    condition     = one([for q in aws_cloudwatch_metric_alarm.this["custom-error-ratio"].metric_query : one(q.metric).period if q.id == "failed"]) == 60 && one([for q in aws_cloudwatch_metric_alarm.this["custom-error-ratio"].metric_query : one(q.metric).period if q.id == "total"]) == 300
    error_message = "Generic metric queries must default metric.period to the alarm period and keep explicit periods."
  }
}

run "rds_free_storage_is_twenty_percent_of_allocated_bytes" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["rds-main-free-storage"].threshold == 4294967296
    error_message = "FreeStorageSpace threshold must be 20 GiB * 1073741824 * 0.2 = 4294967296 bytes."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["rds-main-free-storage"].comparison_operator == "LessThanThreshold" && aws_cloudwatch_metric_alarm.this["rds-main-free-storage"].statistic == "Minimum"
    error_message = "FreeStorageSpace must alarm on Minimum below the threshold."
  }
}

run "cloudfront_alarms_live_in_us_east_1" {
  command = plan

  variables {
    cloudfront_distributions = {
      site = {
        distribution_id = "E2QWRUHAPOMQZL"
        alarms = {
          client_error_rate = { enabled = true, threshold = 15 }
          requests          = { enabled = true, threshold = 1000000 }
        }
      }
    }
  }

  assert {
    condition     = alltrue([for k, a in aws_cloudwatch_metric_alarm.this : a.region == "us-east-1" if startswith(k, "cloudfront-")]) && length([for k in keys(aws_cloudwatch_metric_alarm.this) : k if startswith(k, "cloudfront-")]) == 3
    error_message = "Every CloudFront alarm must be created in us-east-1."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["cloudfront-site-5xx-error-rate"].dimensions == tomap({ DistributionId = "E2QWRUHAPOMQZL", Region = "Global" })
    error_message = "CloudFront alarms must use DistributionId + Region=Global."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["waf-edge-blocked-requests"].region == "us-east-1"
    error_message = "CLOUDFRONT-scope WAF alarms must be created in us-east-1."
  }
}

run "disabled_alarms_are_not_created" {
  command = plan

  variables {
    alarms = {
      custom-off = {
        enabled             = false
        comparison_operator = "GreaterThanThreshold"
        threshold           = 1
        evaluation_periods  = 1
        namespace           = "Custom/App"
        metric_name         = "Errors"
        statistic           = "Sum"
      }
    }
    lambda_functions = {
      orders = {
        function_name   = "core-prod-orders"
        timeout_seconds = 30
        alarms = {
          error_rate   = { enabled = false }
          duration_p99 = { enabled = false }
        }
      }
    }
    sqs_queues = {
      jobs = { queue_name = "core-prod-jobs", alarms = { age_of_oldest_message = { enabled = false } } }
    }
    elasticache_clusters = {
      single = { replication_group_id = "core-prod-cache", cache_cluster_ids = ["core-prod-cache-001"] }
    }
    log_metric_filters = {
      app-errors = { log_group_name = "/aws/lambda/core-prod-orders", pattern = "ERROR", alarm = { enabled = false } }
    }
  }

  assert {
    condition     = !contains(keys(aws_cloudwatch_metric_alarm.this), "custom-off") && !contains(keys(aws_cloudwatch_metric_alarm.this), "lambda-orders-error-rate") && !contains(keys(aws_cloudwatch_metric_alarm.this), "lambda-orders-duration-p99") && contains(keys(aws_cloudwatch_metric_alarm.this), "lambda-orders-throttles")
    error_message = "Alarms with enabled = false must not be created; the others must remain."
  }

  assert {
    condition     = length([for k in keys(aws_cloudwatch_metric_alarm.this) : k if startswith(k, "sqs-jobs-")]) == 0
    error_message = "A queue with the age alarm disabled and no DLQ must create no alarms."
  }

  assert {
    condition     = !contains(keys(aws_cloudwatch_metric_alarm.this), "elasticache-single-core-prod-cache-001-replication-lag") && contains(keys(aws_cloudwatch_metric_alarm.this), "elasticache-single-core-prod-cache-001-cpu")
    error_message = "ReplicationLag must be skipped for a single-member replication group."
  }

  assert {
    condition     = !contains(keys(aws_cloudwatch_metric_alarm.this), "log-app-errors") && contains(keys(aws_cloudwatch_log_metric_filter.this), "app-errors")
    error_message = "A disabled log alarm must still keep its metric filter."
  }
}

run "log_metric_filter_defaults" {
  command = plan

  assert {
    condition     = one(aws_cloudwatch_log_metric_filter.this["app-errors"].metric_transformation).namespace == "core-prod-monitoring/LogMetrics" && one(aws_cloudwatch_log_metric_filter.this["app-errors"].metric_transformation).name == "app-errors" && one(aws_cloudwatch_log_metric_filter.this["app-errors"].metric_transformation).value == "1"
    error_message = "Log metric filters must default to namespace <rendered_name>/LogMetrics, metric name = key, value 1."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["log-app-errors"].namespace == "core-prod-monitoring/LogMetrics" && aws_cloudwatch_metric_alarm.this["log-app-errors"].metric_name == "app-errors" && aws_cloudwatch_metric_alarm.this["log-app-errors"].threshold == 1 && aws_cloudwatch_metric_alarm.this["log-app-errors"].comparison_operator == "GreaterThanOrEqualToThreshold"
    error_message = "Each log metric filter must get a matching alarm (Sum >= 1)."
  }

  assert {
    condition     = output.metric_filter_names["log-app-errors"] == "core-prod-monitoring-log-app-errors"
    error_message = "metric_filter_names output must list log filters as log-<key>."
  }
}

run "cis_filters_off_by_default" {
  command = plan

  variables {
    cis_cloudtrail_metric_filters = {}
  }

  assert {
    condition     = length(aws_cloudwatch_log_metric_filter.cis) == 0 && length([for k in keys(aws_cloudwatch_metric_alarm.this) : k if startswith(k, "cis-")]) == 0
    error_message = "CIS metric filters and alarms must be off by default."
  }
}

run "cis_filters_enabled_create_fourteen" {
  command = plan

  variables {
    cis_cloudtrail_metric_filters = {
      enabled        = true
      log_group_name = "core-prod-cloudtrail"
    }
    notifications = {
      enabled = true
      topic_arns = {
        "eu-west-1" = {
          critical = "arn:aws:sns:eu-west-1:123456789012:core-prod-alerts-critical"
          warning  = "arn:aws:sns:eu-west-1:123456789012:core-prod-alerts-warning"
          info     = "arn:aws:sns:eu-west-1:123456789012:core-prod-alerts-info"
        }
        "us-east-1" = {
          critical = "arn:aws:sns:us-east-1:123456789012:core-prod-alerts-critical"
          warning  = "arn:aws:sns:us-east-1:123456789012:core-prod-alerts-warning"
          info     = "arn:aws:sns:us-east-1:123456789012:core-prod-alerts-info"
        }
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_log_metric_filter.cis["cis-cloudwatch-1"].name == "core-prod-monitoring-cis-cloudwatch-1" && output.metric_filter_names["cis-cloudwatch-14"] == "core-prod-monitoring-cis-cloudwatch-14"
    error_message = "CIS filter names must be <application>-<environment>-<name>-cis-cloudwatch-N."
  }

  assert {
    condition     = length(aws_cloudwatch_log_metric_filter.cis) == 14 && length([for k in keys(aws_cloudwatch_metric_alarm.this) : k if startswith(k, "cis-cloudwatch-")]) == 14
    error_message = "Enabling the CIS preset must create 14 metric filters and 14 alarms."
  }

  assert {
    condition     = alltrue([for k, f in aws_cloudwatch_log_metric_filter.cis : length(f.pattern) > 0 && f.log_group_name == "core-prod-cloudtrail"])
    error_message = "Every CIS filter pattern must be non-empty and target the CloudTrail log group."
  }

  assert {
    condition     = aws_cloudwatch_log_metric_filter.cis["cis-cloudwatch-1"].pattern == "{$.userIdentity.type=\"Root\" && $.userIdentity.invokedBy NOT EXISTS && $.eventType !=\"AwsServiceEvent\"}" && aws_cloudwatch_log_metric_filter.cis["cis-cloudwatch-2"].pattern == "{($.errorCode=\"*UnauthorizedOperation\") || ($.errorCode=\"AccessDenied*\")}"
    error_message = "CIS patterns must match the Security Hub remediation text exactly."
  }

  assert {
    condition     = alltrue([for k, f in aws_cloudwatch_log_metric_filter.cis : one(f.metric_transformation).value == "1" && one(f.metric_transformation).default_value == "0" && one(f.metric_transformation).namespace == "core-prod-monitoring/LogMetrics"])
    error_message = "CIS filters must publish value 1 with default 0."
  }

  assert {
    condition     = alltrue([for k, a in aws_cloudwatch_metric_alarm.this : a.threshold >= 1 && a.period == 300 && a.comparison_operator == "GreaterThanOrEqualToThreshold" && a.statistic == "Sum" if startswith(k, "cis-")])
    error_message = "CIS alarms must be Sum >= 1 over 300 s."
  }

  assert {
    condition     = length(distinct([for k, f in aws_cloudwatch_log_metric_filter.cis : one(f.metric_transformation).name])) == 14
    error_message = "Each CIS filter must publish a distinct metric."
  }
}

run "invalid_environment_fails" {
  command = plan

  variables {
    environment = "INVALID_UPPERCASE"
  }

  expect_failures = [var.environment]
}

run "invalid_comparison_operator_fails" {
  command = plan

  variables {
    alarms = {
      bad = { comparison_operator = "LessThanLowerOrGreaterThanUpperThreshold", threshold = 1, evaluation_periods = 1, namespace = "Custom/App", metric_name = "Errors", statistic = "Sum" }
    }
  }

  expect_failures = [var.alarms]
}

run "invalid_treat_missing_data_fails" {
  command = plan

  variables {
    alarms = {
      bad = { comparison_operator = "GreaterThanThreshold", threshold = 1, evaluation_periods = 1, treat_missing_data = "zero", namespace = "Custom/App", metric_name = "Errors", statistic = "Sum" }
    }
  }

  expect_failures = [var.alarms]
}

run "both_metric_forms_fail" {
  command = plan

  variables {
    alarms = {
      bad = {
        comparison_operator = "GreaterThanThreshold"
        threshold           = 1
        evaluation_periods  = 1
        namespace           = "Custom/App"
        metric_name         = "Errors"
        statistic           = "Sum"
        metric_queries      = [{ id = "m1", metric = { namespace = "Custom/App", metric_name = "Errors", stat = "Sum" }, return_data = true }]
      }
    }
  }

  expect_failures = [var.alarms]
}

run "statistic_and_extended_statistic_fail" {
  command = plan

  variables {
    alarms = {
      bad = { comparison_operator = "GreaterThanThreshold", threshold = 1, evaluation_periods = 1, namespace = "Custom/App", metric_name = "Latency", statistic = "Average", extended_statistic = "p99" }
    }
  }

  expect_failures = [var.alarms]
}

run "two_return_data_queries_fail" {
  command = plan

  variables {
    alarms = {
      bad = {
        comparison_operator = "GreaterThanThreshold"
        threshold           = 1
        evaluation_periods  = 1
        metric_queries = [
          { id = "m1", metric = { namespace = "Custom/App", metric_name = "Errors", stat = "Sum" }, return_data = true },
          { id = "e1", expression = "m1 * 2", return_data = true },
        ]
      }
    }
  }

  expect_failures = [var.alarms]
}

run "query_with_expression_and_metric_fails" {
  command = plan

  variables {
    alarms = {
      bad = {
        comparison_operator = "GreaterThanThreshold"
        threshold           = 1
        evaluation_periods  = 1
        metric_queries = [
          { id = "m1", expression = "m1 * 2", metric = { namespace = "Custom/App", metric_name = "Errors", stat = "Sum" }, return_data = true },
        ]
      }
    }
  }

  expect_failures = [var.alarms]
}

run "invalid_query_id_fails" {
  command = plan

  variables {
    alarms = {
      bad = {
        comparison_operator = "GreaterThanThreshold"
        threshold           = 1
        evaluation_periods  = 1
        metric_queries = [
          { id = "Errors", metric = { namespace = "Custom/App", metric_name = "Errors", stat = "Sum" }, return_data = true },
        ]
      }
    }
  }

  expect_failures = [var.alarms]
}

run "invalid_lambda_event_source_fails" {
  command = plan

  variables {
    lambda_functions = {
      bad = { function_name = "core-prod-orders", timeout_seconds = 30, event_source = "kinesis" }
    }
  }

  expect_failures = [var.lambda_functions]
}

run "invalid_lambda_timeout_fails" {
  command = plan

  variables {
    lambda_functions = {
      bad = { function_name = "core-prod-orders", timeout_seconds = 901 }
    }
  }

  expect_failures = [var.lambda_functions]
}

run "lambda_duration_without_timeout_or_threshold_fails" {
  command = plan

  variables {
    lambda_functions = {
      bad = { function_name = "core-prod-orders" }
    }
  }

  expect_failures = [var.lambda_functions]
}

run "alb_full_arn_instead_of_suffix_fails" {
  command = plan

  variables {
    albs = {
      bad = { load_balancer_arn_suffix = "arn:aws:elasticloadbalancing:eu-west-1:123456789012:loadbalancer/app/core-prod-web/50dc6c495c0c9188" }
    }
  }

  expect_failures = [var.albs]
}

run "nlb_http_api_and_scheduler_presets" {
  command = plan

  assert {
    condition     = output.presets["nlbs"] == tolist(["nlb-edge-tcp-no-healthy-hosts", "nlb-edge-tcp-unhealthy-hosts"]) && aws_cloudwatch_metric_alarm.this["nlb-edge-tcp-no-healthy-hosts"].comparison_operator == "LessThanThreshold" && aws_cloudwatch_metric_alarm.this["nlb-edge-tcp-unhealthy-hosts"].dimensions["TargetGroup"] == "targetgroup/core-prod-tcp/73e2d6bc24d8a067" && aws_cloudwatch_metric_alarm.this["nlb-edge-tcp-unhealthy-hosts"].namespace == "AWS/NetworkELB"
    error_message = "NLB target groups alarm on unhealthy and missing healthy hosts."
  }

  assert {
    condition     = output.presets["http_apis"] == tolist(["httpapi-public-5xx-rate", "httpapi-public-latency-p99"]) && aws_cloudwatch_metric_alarm.this["httpapi-public-latency-p99"].dimensions == tomap({ ApiId = "a1b2c3d4e5", Stage = "$default" })
    error_message = "HTTP APIs alarm on the 5xx rate and p99 latency of the $default stage."
  }

  assert {
    condition     = output.presets["schedule_groups"] == tolist(["scheduler-jobs-dlq-send-failures", "scheduler-jobs-invocations-dropped", "scheduler-jobs-target-errors"]) && aws_cloudwatch_metric_alarm.this["scheduler-jobs-invocations-dropped"].dimensions["ScheduleGroup"] == "core-prod-jobs" && aws_cloudwatch_metric_alarm.this["scheduler-jobs-invocations-dropped"].namespace == "AWS/Scheduler"
    error_message = "Schedule groups alarm on target errors, dropped invocations and DLQ send failures."
  }
}

run "nlb_alb_suffix_fails" {
  command = plan

  variables {
    nlbs = {
      bad = { load_balancer_arn_suffix = "app/core-prod-web/50dc6c495c0c9188" }
    }
  }

  expect_failures = [var.nlbs]
}

run "rds_free_storage_without_size_fails" {
  command = plan

  variables {
    rds_instances = {
      bad = { db_instance_identifier = "core-prod-db" }
    }
  }

  expect_failures = [var.rds_instances]
}

run "dynamodb_invalid_operations_fail" {
  command = plan

  variables {
    dynamodb_tables = {
      bad = { table_name = "core-prod-orders", system_error_operations = ["GetItem", "ListTables"] }
    }
  }

  expect_failures = [var.dynamodb_tables]
}

run "elasticache_without_members_fails" {
  command = plan

  variables {
    elasticache_clusters = {
      bad = { replication_group_id = "core-prod-cache", cache_cluster_ids = [] }
    }
  }

  expect_failures = [var.elasticache_clusters]
}

run "sqs_age_threshold_required" {
  command = plan

  variables {
    sqs_queues = {
      bad = { queue_name = "core-prod-jobs" }
    }
  }

  expect_failures = [var.sqs_queues]
}

run "efs_invalid_throughput_mode_fails" {
  command = plan

  variables {
    efs_file_systems = {
      bad = { file_system_id = "fs-0123456789abcdef0", throughput_mode = "burst" }
    }
  }

  expect_failures = [var.efs_file_systems]
}

run "waf_invalid_scope_fails" {
  command = plan

  variables {
    waf_web_acls = {
      bad = { web_acl_metric_name = "core-prod-waf-acl-metric", scope = "GLOBAL", alarms = { blocked_requests = { threshold = 10 } } }
    }
  }

  expect_failures = [var.waf_web_acls]
}

run "waf_threshold_required" {
  command = plan

  variables {
    waf_web_acls = {
      bad = { web_acl_metric_name = "core-prod-waf-acl-metric" }
    }
  }

  expect_failures = [var.waf_web_acls]
}

run "s3_threshold_required" {
  command = plan

  variables {
    s3_buckets = {
      bad = { bucket_name = "core-prod-assets" }
    }
  }

  expect_failures = [var.s3_buckets]
}

run "log_filter_invalid_alarm_settings_fail" {
  command = plan

  variables {
    log_metric_filters = {
      bad = { log_group_name = "/aws/lambda/core-prod-orders", pattern = "ERROR", alarm = { comparison_operator = "Above" } }
    }
  }

  expect_failures = [var.log_metric_filters]
}

run "topic_in_another_region_fails" {
  command = plan

  variables {
    notifications = {
      enabled    = true
      topic_arns = { "us-east-1" = { critical = "arn:aws:sns:eu-west-1:123456789012:core-prod-alerts-critical" } }
    }
  }

  expect_failures = [var.notifications]
}

run "cis_enabled_without_log_group_fails" {
  command = plan

  variables {
    cis_cloudtrail_metric_filters = { enabled = true }
    notifications = {
      enabled = true
      topic_arns = {
        "eu-west-1" = {
          critical = "arn:aws:sns:eu-west-1:123456789012:core-prod-alerts-critical"
          warning  = "arn:aws:sns:eu-west-1:123456789012:core-prod-alerts-warning"
          info     = "arn:aws:sns:eu-west-1:123456789012:core-prod-alerts-info"
        }
        "us-east-1" = {
          critical = "arn:aws:sns:us-east-1:123456789012:core-prod-alerts-critical"
          warning  = "arn:aws:sns:us-east-1:123456789012:core-prod-alerts-warning"
          info     = "arn:aws:sns:us-east-1:123456789012:core-prod-alerts-info"
        }
      }
    }
  }

  expect_failures = [var.cis_cloudtrail_metric_filters]
}

run "cis_enabled_without_notifications_fails" {
  command = plan

  variables {
    cis_cloudtrail_metric_filters = { enabled = true, log_group_name = "core-prod-cloudtrail" }
  }

  expect_failures = [var.cis_cloudtrail_metric_filters]
}

run "enabled_alarm_without_threshold_fails" {
  command = plan

  variables {
    rds_instances = {
      main = { db_instance_identifier = "core-prod-db", allocated_storage_gib = 20, alarms = { freeable_memory = { enabled = true } } }
    }
  }

  expect_failures = [aws_cloudwatch_metric_alarm.this]
}

run "datapoints_above_evaluation_periods_fails" {
  command = plan

  variables {
    lambda_functions = {
      orders = { function_name = "core-prod-orders", timeout_seconds = 30, alarms = { throttles = { evaluation_periods = 2 } } }
    }
  }

  expect_failures = [aws_cloudwatch_metric_alarm.this]
}

run "duplicate_alarm_keys_fail" {
  command = plan

  variables {
    alarms = {
      lambda-orders-throttles = { comparison_operator = "GreaterThanThreshold", threshold = 1, evaluation_periods = 1, namespace = "Custom/App", metric_name = "Errors", statistic = "Sum" }
    }
  }

  expect_failures = [aws_cloudwatch_metric_alarm.this]
}
