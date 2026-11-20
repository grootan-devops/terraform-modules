variable "application" {
  description = "Application name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,23}$", var.application))
    error_message = "application: 2-24 chars, a-z 0-9 -, starts with a letter."
  }
}

variable "environment" {
  description = "Environment name."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,11}$", var.environment))
    error_message = "environment: 2-12 chars, a-z 0-9 -, starts with a letter."
  }
}

variable "name" {
  description = "Instance name."
  type        = string
  default     = null

  validation {
    condition     = var.name == null || can(regex("^[a-z0-9][a-z0-9-]{0,31}$", var.name))
    error_message = "name: 1-32 chars, a-z 0-9 -."
  }
}

variable "tags" {
  description = "Extra tags; governance tags win."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "notifications" {
  description = "Alarm actions: off by default; topic ARN by Region and severity."
  type = object({
    enabled                     = optional(bool, false)
    topic_arns                  = optional(map(map(string)), {})
    notify_on_ok                = optional(bool, true)
    notify_on_insufficient_data = optional(bool, false)
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue(flatten([
      for region, topics in var.notifications.topic_arns : [
        for severity, arn in topics : can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_-]+(\\.fifo)?$", arn)) && split(":", arn)[3] == region
      ]
    ]))
    error_message = "notifications.topic_arns: SNS ARNs in their Region."
  }
}

variable "alarms" {
  description = "Generic metric or metric-math alarms by key."
  type = map(object({
    enabled             = optional(bool, true)
    severity            = optional(string, "warning")
    description         = optional(string)
    region              = optional(string)
    comparison_operator = string
    threshold           = number
    evaluation_periods  = number
    datapoints_to_alarm = optional(number)
    period              = optional(number, 60)
    treat_missing_data  = optional(string, "missing")
    namespace           = optional(string)
    metric_name         = optional(string)
    dimensions          = optional(map(string), {})
    statistic           = optional(string)
    extended_statistic  = optional(string)
    unit                = optional(string)
    metric_queries = optional(list(object({
      id          = string
      expression  = optional(string)
      label       = optional(string)
      return_data = optional(bool, false)
      period      = optional(number)
      metric = optional(object({
        namespace   = string
        metric_name = string
        dimensions  = optional(map(string), {})
        stat        = string
        period      = optional(number)
        unit        = optional(string)
      }))
    })), [])
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for k, a in var.alarms : contains(["GreaterThanOrEqualToThreshold", "GreaterThanThreshold", "LessThanThreshold", "LessThanOrEqualToThreshold"], a.comparison_operator)
    ])
    error_message = "alarms: static comparison operators only."
  }

  validation {
    condition = alltrue([
      for k, a in var.alarms : contains(["missing", "ignore", "breaching", "notBreaching"], a.treat_missing_data)
    ])
    error_message = "alarms: treat_missing_data missing, ignore, breaching or notBreaching."
  }

  validation {
    condition = alltrue([
      for k, a in var.alarms : (a.metric_name != null) != (length(a.metric_queries) > 0) && (a.metric_name != null ? a.namespace != null : true)
    ])
    error_message = "alarms: set namespace with metric_name, or metric_queries."
  }

  validation {
    condition = alltrue([
      for k, a in var.alarms : a.metric_name == null ? true : (a.statistic != null) != (a.extended_statistic != null)
    ])
    error_message = "alarms: set statistic or extended_statistic."
  }

  validation {
    condition = alltrue([
      for k, a in var.alarms : length(a.metric_queries) == 0 ? true : length([for q in a.metric_queries : q.id if q.return_data]) == 1
    ])
    error_message = "alarms: exactly one query with return_data."
  }

  validation {
    condition = alltrue(flatten([
      for k, a in var.alarms : [for q in a.metric_queries : (q.expression != null) != (q.metric != null)]
    ]))
    error_message = "alarms: each query sets expression or metric."
  }

  validation {
    condition = alltrue(flatten([
      for k, a in var.alarms : [for q in a.metric_queries : can(regex("^[a-z][a-zA-Z0-9_]*$", q.id))]
    ]))
    error_message = "alarms: query id starts lowercase; letters, digits, _."
  }
}

variable "lambda_functions" {
  description = "Lambda functions by key: function name and timeout."
  type = map(object({
    function_name   = string
    timeout_seconds = optional(number)
    event_source    = optional(string, "none")
    region          = optional(string)
    alarms = optional(object({
      error_rate            = optional(object({ enabled = optional(bool, true), threshold = optional(number, 5), evaluation_periods = optional(number, 3), datapoints_to_alarm = optional(number, 3), period = optional(number, 60), severity = optional(string, "critical") }), {})
      throttles             = optional(object({ enabled = optional(bool, true), threshold = optional(number, 0), evaluation_periods = optional(number, 5), datapoints_to_alarm = optional(number, 5), period = optional(number, 60), severity = optional(string, "warning") }), {})
      duration_p99          = optional(object({ enabled = optional(bool, true), threshold = optional(number), evaluation_periods = optional(number, 15), datapoints_to_alarm = optional(number, 15), period = optional(number, 60), severity = optional(string, "warning") }), {})
      concurrent_executions = optional(object({ enabled = optional(bool, false), threshold = optional(number, 900), evaluation_periods = optional(number, 10), datapoints_to_alarm = optional(number, 10), period = optional(number, 60), severity = optional(string, "warning") }), {})
      iterator_age          = optional(object({ enabled = optional(bool, true), threshold = optional(number, 60000), evaluation_periods = optional(number, 5), datapoints_to_alarm = optional(number, 5), period = optional(number, 60), severity = optional(string, "warning") }), {})
    }), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k, f in var.lambda_functions : contains(["none", "queue", "stream"], f.event_source)])
    error_message = "lambda_functions: event_source none, queue or stream."
  }

  validation {
    condition     = alltrue([for k, f in var.lambda_functions : f.timeout_seconds == null ? true : f.timeout_seconds >= 1 && f.timeout_seconds <= 900])
    error_message = "lambda_functions: timeout_seconds 1-900."
  }

  validation {
    condition     = alltrue([for k, f in var.lambda_functions : f.alarms.duration_p99.enabled ? (f.alarms.duration_p99.threshold != null || f.timeout_seconds != null) : true])
    error_message = "lambda_functions: duration_p99 needs timeout_seconds or a threshold."
  }
}

variable "api_gateways" {
  description = "REST API stages by key: API name and stage."
  type = map(object({
    api_name = string
    stage    = string
    region   = optional(string)
    alarms = optional(object({
      server_error_rate       = optional(object({ enabled = optional(bool, true), threshold = optional(number, 5), evaluation_periods = optional(number, 3), datapoints_to_alarm = optional(number, 3), period = optional(number, 60), severity = optional(string, "critical") }), {})
      client_error_rate       = optional(object({ enabled = optional(bool, true), threshold = optional(number, 5), evaluation_periods = optional(number, 5), datapoints_to_alarm = optional(number, 5), period = optional(number, 60), severity = optional(string, "warning") }), {})
      latency_p99             = optional(object({ enabled = optional(bool, true), threshold = optional(number, 2500), evaluation_periods = optional(number, 5), datapoints_to_alarm = optional(number, 5), period = optional(number, 60), severity = optional(string, "warning") }), {})
      integration_latency_p99 = optional(object({ enabled = optional(bool, true), threshold = optional(number, 2000), evaluation_periods = optional(number, 5), datapoints_to_alarm = optional(number, 5), period = optional(number, 60), severity = optional(string, "warning") }), {})
    }), {})
  }))
  default  = {}
  nullable = false
}

variable "albs" {
  description = "Application Load Balancers by key: ARN suffixes."
  type = map(object({
    load_balancer_arn_suffix = string
    target_groups            = optional(map(string), {})
    idle_timeout_seconds     = optional(number, 60)
    region                   = optional(string)
    alarms = optional(object({
      unhealthy_hosts          = optional(object({ enabled = optional(bool, true), threshold = optional(number, 0), evaluation_periods = optional(number, 3), datapoints_to_alarm = optional(number, 3), period = optional(number, 60), severity = optional(string, "critical") }), {})
      target_5xx_rate          = optional(object({ enabled = optional(bool, true), threshold = optional(number, 5), evaluation_periods = optional(number, 3), datapoints_to_alarm = optional(number, 3), period = optional(number, 60), severity = optional(string, "critical") }), {})
      elb_5xx_count            = optional(object({ enabled = optional(bool, true), threshold = optional(number, 0), evaluation_periods = optional(number, 3), datapoints_to_alarm = optional(number, 3), period = optional(number, 60), severity = optional(string, "critical") }), {})
      target_response_time_p99 = optional(object({ enabled = optional(bool, true), threshold = optional(number), evaluation_periods = optional(number, 5), datapoints_to_alarm = optional(number, 5), period = optional(number, 60), severity = optional(string, "warning") }), {})
      rejected_connections     = optional(object({ enabled = optional(bool, true), threshold = optional(number, 0), evaluation_periods = optional(number, 1), datapoints_to_alarm = optional(number, 1), period = optional(number, 60), severity = optional(string, "critical") }), {})
    }), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for k, l in var.albs : startswith(l.load_balancer_arn_suffix, "app/") && alltrue([for t, s in l.target_groups : startswith(s, "targetgroup/")])
    ])
    error_message = "albs: ARN suffixes (app/..., targetgroup/...)."
  }
}

variable "nlbs" {
  description = "Network Load Balancers by key: ARN suffixes."
  type = map(object({
    load_balancer_arn_suffix = string
    target_groups            = optional(map(string), {})
    region                   = optional(string)
    alarms = optional(object({
      unhealthy_hosts  = optional(object({ enabled = optional(bool, true), threshold = optional(number, 0), evaluation_periods = optional(number, 3), datapoints_to_alarm = optional(number, 3), period = optional(number, 60), severity = optional(string, "critical") }), {})
      no_healthy_hosts = optional(object({ enabled = optional(bool, true), threshold = optional(number, 1), evaluation_periods = optional(number, 2), datapoints_to_alarm = optional(number, 2), period = optional(number, 60), severity = optional(string, "critical") }), {})
    }), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for k, l in var.nlbs : startswith(l.load_balancer_arn_suffix, "net/") && alltrue([for t, s in l.target_groups : startswith(s, "targetgroup/")])
    ])
    error_message = "nlbs: ARN suffixes (net/..., targetgroup/...)."
  }
}

variable "http_apis" {
  description = "HTTP APIs by key: API ID and stage."
  type = map(object({
    api_id = string
    stage  = optional(string, "$default")
    region = optional(string)
    alarms = optional(object({
      server_error_rate = optional(object({ enabled = optional(bool, true), threshold = optional(number, 5), evaluation_periods = optional(number, 3), datapoints_to_alarm = optional(number, 3), period = optional(number, 60), severity = optional(string, "critical") }), {})
      latency_p99       = optional(object({ enabled = optional(bool, true), threshold = optional(number, 2500), evaluation_periods = optional(number, 5), datapoints_to_alarm = optional(number, 5), period = optional(number, 60), severity = optional(string, "warning") }), {})
    }), {})
  }))
  default  = {}
  nullable = false
}

variable "schedule_groups" {
  description = "EventBridge Scheduler schedule groups by key: group name."
  type = map(object({
    schedule_group_name = string
    region              = optional(string)
    alarms = optional(object({
      target_errors             = optional(object({ enabled = optional(bool, true), threshold = optional(number, 0), evaluation_periods = optional(number, 3), datapoints_to_alarm = optional(number, 3), period = optional(number, 60), severity = optional(string, "warning") }), {})
      invocations_dropped       = optional(object({ enabled = optional(bool, true), threshold = optional(number, 0), evaluation_periods = optional(number, 1), datapoints_to_alarm = optional(number, 1), period = optional(number, 60), severity = optional(string, "critical") }), {})
      invocations_failed_to_dlq = optional(object({ enabled = optional(bool, true), threshold = optional(number, 0), evaluation_periods = optional(number, 1), datapoints_to_alarm = optional(number, 1), period = optional(number, 60), severity = optional(string, "critical") }), {})
    }), {})
  }))
  default  = {}
  nullable = false
}

variable "ecs_services" {
  description = "ECS services by key: cluster and service names."
  type = map(object({
    cluster_name       = string
    service_name       = string
    container_insights = optional(bool, false)
    region             = optional(string)
    alarms = optional(object({
      cpu           = optional(object({ enabled = optional(bool, true), threshold = optional(number, 80), evaluation_periods = optional(number, 5), datapoints_to_alarm = optional(number, 5), period = optional(number, 60), severity = optional(string, "warning") }), {})
      memory        = optional(object({ enabled = optional(bool, true), threshold = optional(number, 80), evaluation_periods = optional(number, 5), datapoints_to_alarm = optional(number, 5), period = optional(number, 60), severity = optional(string, "warning") }), {})
      running_tasks = optional(object({ enabled = optional(bool, true), threshold = optional(number, 0), evaluation_periods = optional(number, 5), datapoints_to_alarm = optional(number, 5), period = optional(number, 60), severity = optional(string, "critical") }), {})
    }), {})
  }))
  default  = {}
  nullable = false
}

variable "eks_clusters" {
  description = "EKS clusters by key: Container Insights alarms."
  type = map(object({
    cluster_name       = string
    container_insights = optional(bool, false)
    region             = optional(string)
    alarms = optional(object({
      node_cpu     = optional(object({ enabled = optional(bool, true), threshold = optional(number, 80), evaluation_periods = optional(number, 5), datapoints_to_alarm = optional(number, 5), period = optional(number, 60), severity = optional(string, "warning") }), {})
      node_memory  = optional(object({ enabled = optional(bool, true), threshold = optional(number, 80), evaluation_periods = optional(number, 5), datapoints_to_alarm = optional(number, 5), period = optional(number, 60), severity = optional(string, "warning") }), {})
      failed_nodes = optional(object({ enabled = optional(bool, true), threshold = optional(number, 0), evaluation_periods = optional(number, 5), datapoints_to_alarm = optional(number, 5), period = optional(number, 60), severity = optional(string, "critical") }), {})
    }), {})
  }))
  default  = {}
  nullable = false
}

variable "auto_scaling_groups" {
  description = "Auto Scaling groups by key."
  type = map(object({
    auto_scaling_group_name = string
    region                  = optional(string)
    alarms = optional(object({
      cpu                 = optional(object({ enabled = optional(bool, true), threshold = optional(number, 80), evaluation_periods = optional(number, 3), datapoints_to_alarm = optional(number, 3), period = optional(number, 300), severity = optional(string, "warning") }), {})
      status_check_failed = optional(object({ enabled = optional(bool, true), threshold = optional(number, 0), evaluation_periods = optional(number, 2), datapoints_to_alarm = optional(number, 2), period = optional(number, 300), severity = optional(string, "critical") }), {})
    }), {})
  }))
  default  = {}
  nullable = false
}

variable "rds_instances" {
  description = "RDS DB instances by key: identifier and storage."
  type = map(object({
    db_instance_identifier = string
    allocated_storage_gib  = optional(number)
    region                 = optional(string)
    alarms = optional(object({
      cpu                  = optional(object({ enabled = optional(bool, true), threshold = optional(number, 80), evaluation_periods = optional(number, 5), datapoints_to_alarm = optional(number, 5), period = optional(number, 60), severity = optional(string, "warning") }), {})
      free_storage         = optional(object({ enabled = optional(bool, true), threshold = optional(number), evaluation_periods = optional(number, 5), datapoints_to_alarm = optional(number, 5), period = optional(number, 60), severity = optional(string, "warning") }), {})
      freeable_memory      = optional(object({ enabled = optional(bool, false), threshold = optional(number), evaluation_periods = optional(number, 15), datapoints_to_alarm = optional(number, 15), period = optional(number, 60), severity = optional(string, "warning") }), {})
      database_connections = optional(object({ enabled = optional(bool, false), threshold = optional(number), evaluation_periods = optional(number, 5), datapoints_to_alarm = optional(number, 5), period = optional(number, 60), severity = optional(string, "warning") }), {})
      read_latency_p99     = optional(object({ enabled = optional(bool, true), threshold = optional(number, 0.02), evaluation_periods = optional(number, 5), datapoints_to_alarm = optional(number, 5), period = optional(number, 60), severity = optional(string, "warning") }), {})
      write_latency_p99    = optional(object({ enabled = optional(bool, true), threshold = optional(number, 0.02), evaluation_periods = optional(number, 5), datapoints_to_alarm = optional(number, 5), period = optional(number, 60), severity = optional(string, "warning") }), {})
    }), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for k, d in var.rds_instances : d.alarms.free_storage.enabled ? (d.alarms.free_storage.threshold != null || (d.allocated_storage_gib == null ? false : d.allocated_storage_gib > 0)) : true
    ])
    error_message = "rds_instances: free_storage needs allocated_storage_gib or a threshold."
  }
}

variable "rds_proxies" {
  description = "RDS Proxies by key."
  type = map(object({
    proxy_name = string
    region     = optional(string)
    alarms = optional(object({
      connection_setup_failures = optional(object({ enabled = optional(bool, true), threshold = optional(number, 0), evaluation_periods = optional(number, 3), datapoints_to_alarm = optional(number, 3), period = optional(number, 60), severity = optional(string, "critical") }), {})
      client_auth_failures      = optional(object({ enabled = optional(bool, true), threshold = optional(number, 0), evaluation_periods = optional(number, 3), datapoints_to_alarm = optional(number, 3), period = optional(number, 60), severity = optional(string, "critical") }), {})
      borrowed_connections      = optional(object({ enabled = optional(bool, true), threshold = optional(number, 80), evaluation_periods = optional(number, 5), datapoints_to_alarm = optional(number, 5), period = optional(number, 60), severity = optional(string, "warning") }), {})
      client_connections        = optional(object({ enabled = optional(bool, false), threshold = optional(number), evaluation_periods = optional(number, 5), datapoints_to_alarm = optional(number, 5), period = optional(number, 60), severity = optional(string, "warning") }), {})
    }), {})
  }))
  default  = {}
  nullable = false
}

variable "dynamodb_tables" {
  description = "DynamoDB tables by key: table and index names."
  type = map(object({
    table_name                   = string
    global_secondary_index_names = optional(list(string), [])
    system_error_operations      = optional(list(string), ["GetItem", "PutItem", "UpdateItem", "DeleteItem", "Query", "Scan", "BatchGetItem", "BatchWriteItem", "TransactGetItems", "TransactWriteItems"])
    region                       = optional(string)
    alarms = optional(object({
      read_throttles          = optional(object({ enabled = optional(bool, true), threshold = optional(number, 0), evaluation_periods = optional(number, 5), datapoints_to_alarm = optional(number, 5), period = optional(number, 60), severity = optional(string, "warning") }), {})
      write_throttles         = optional(object({ enabled = optional(bool, true), threshold = optional(number, 0), evaluation_periods = optional(number, 5), datapoints_to_alarm = optional(number, 5), period = optional(number, 60), severity = optional(string, "warning") }), {})
      system_errors           = optional(object({ enabled = optional(bool, true), threshold = optional(number, 0), evaluation_periods = optional(number, 15), datapoints_to_alarm = optional(number, 15), period = optional(number, 60), severity = optional(string, "critical") }), {})
      consumed_read_capacity  = optional(object({ enabled = optional(bool, false), threshold = optional(number), evaluation_periods = optional(number, 5), datapoints_to_alarm = optional(number, 5), period = optional(number, 60), severity = optional(string, "info") }), {})
      consumed_write_capacity = optional(object({ enabled = optional(bool, false), threshold = optional(number), evaluation_periods = optional(number, 5), datapoints_to_alarm = optional(number, 5), period = optional(number, 60), severity = optional(string, "info") }), {})
    }), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for k, t in var.dynamodb_tables : length(t.system_error_operations) >= 1 && length(t.system_error_operations) <= 10 && alltrue([
        for o in t.system_error_operations : contains(["PutItem", "DeleteItem", "UpdateItem", "GetItem", "BatchGetItem", "Scan", "Query", "BatchWriteItem", "TransactWriteItems", "TransactGetItems", "ExecuteTransaction", "BatchExecuteStatement", "ExecuteStatement", "GetRecords"], o)
      ])
    ])
    error_message = "dynamodb_tables: 1-10 DynamoDB operations."
  }
}

variable "elasticache_clusters" {
  description = "Valkey or Redis OSS replication groups by key: member clusters."
  type = map(object({
    replication_group_id = string
    cache_cluster_ids    = list(string)
    cache_node_id        = optional(string, "0001")
    region               = optional(string)
    alarms = optional(object({
      cpu              = optional(object({ enabled = optional(bool, true), threshold = optional(number, 80), evaluation_periods = optional(number, 5), datapoints_to_alarm = optional(number, 5), period = optional(number, 60), severity = optional(string, "warning") }), {})
      engine_cpu       = optional(object({ enabled = optional(bool, true), threshold = optional(number, 80), evaluation_periods = optional(number, 5), datapoints_to_alarm = optional(number, 5), period = optional(number, 60), severity = optional(string, "warning") }), {})
      memory           = optional(object({ enabled = optional(bool, true), threshold = optional(number, 80), evaluation_periods = optional(number, 5), datapoints_to_alarm = optional(number, 5), period = optional(number, 60), severity = optional(string, "warning") }), {})
      evictions        = optional(object({ enabled = optional(bool, true), threshold = optional(number, 0), evaluation_periods = optional(number, 3), datapoints_to_alarm = optional(number, 3), period = optional(number, 60), severity = optional(string, "warning") }), {})
      curr_connections = optional(object({ enabled = optional(bool, false), threshold = optional(number), evaluation_periods = optional(number, 10), datapoints_to_alarm = optional(number, 10), period = optional(number, 60), severity = optional(string, "warning") }), {})
      replication_lag  = optional(object({ enabled = optional(bool, true), threshold = optional(number, 1), evaluation_periods = optional(number, 15), datapoints_to_alarm = optional(number, 15), period = optional(number, 60), severity = optional(string, "warning") }), {})
    }), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k, c in var.elasticache_clusters : length(c.cache_cluster_ids) > 0])
    error_message = "elasticache_clusters: at least one cache_cluster_id."
  }
}

variable "sqs_queues" {
  description = "SQS queues by key: queue and dead-letter queue names."
  type = map(object({
    queue_name = string
    dlq_name   = optional(string)
    region     = optional(string)
    alarms = optional(object({
      age_of_oldest_message = optional(object({ enabled = optional(bool, true), threshold = optional(number), evaluation_periods = optional(number, 15), datapoints_to_alarm = optional(number, 15), period = optional(number, 60), severity = optional(string, "warning") }), {})
      messages_visible      = optional(object({ enabled = optional(bool, false), threshold = optional(number), evaluation_periods = optional(number, 15), datapoints_to_alarm = optional(number, 15), period = optional(number, 60), severity = optional(string, "warning") }), {})
      dlq_messages_visible  = optional(object({ enabled = optional(bool, true), threshold = optional(number, 0), evaluation_periods = optional(number, 1), datapoints_to_alarm = optional(number, 1), period = optional(number, 60), severity = optional(string, "critical") }), {})
    }), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for k, q in var.sqs_queues : q.alarms.age_of_oldest_message.enabled ? (q.alarms.age_of_oldest_message.threshold == null ? false : q.alarms.age_of_oldest_message.threshold > 0) : true
    ])
    error_message = "sqs_queues: age_of_oldest_message threshold > 0."
  }
}

variable "eventbridge_rules" {
  description = "EventBridge rules by key: rule and bus names."
  type = map(object({
    rule_name      = string
    event_bus_name = optional(string, "default")
    region         = optional(string)
    alarms = optional(object({
      failed_invocations        = optional(object({ enabled = optional(bool, true), threshold = optional(number, 0), evaluation_periods = optional(number, 1), datapoints_to_alarm = optional(number, 1), period = optional(number, 60), severity = optional(string, "critical") }), {})
      throttled_rules           = optional(object({ enabled = optional(bool, true), threshold = optional(number, 0), evaluation_periods = optional(number, 3), datapoints_to_alarm = optional(number, 3), period = optional(number, 60), severity = optional(string, "warning") }), {})
      invocations_failed_to_dlq = optional(object({ enabled = optional(bool, true), threshold = optional(number, 0), evaluation_periods = optional(number, 1), datapoints_to_alarm = optional(number, 1), period = optional(number, 60), severity = optional(string, "critical") }), {})
    }), {})
  }))
  default  = {}
  nullable = false
}

variable "step_functions" {
  description = "Step Functions state machines by key."
  type = map(object({
    state_machine_arn = string
    region            = optional(string)
    alarms = optional(object({
      executions_failed    = optional(object({ enabled = optional(bool, true), threshold = optional(number, 0), evaluation_periods = optional(number, 1), datapoints_to_alarm = optional(number, 1), period = optional(number, 60), severity = optional(string, "critical") }), {})
      executions_timed_out = optional(object({ enabled = optional(bool, true), threshold = optional(number, 0), evaluation_periods = optional(number, 1), datapoints_to_alarm = optional(number, 1), period = optional(number, 60), severity = optional(string, "critical") }), {})
      executions_aborted   = optional(object({ enabled = optional(bool, true), threshold = optional(number, 0), evaluation_periods = optional(number, 1), datapoints_to_alarm = optional(number, 1), period = optional(number, 60), severity = optional(string, "warning") }), {})
      execution_throttled  = optional(object({ enabled = optional(bool, true), threshold = optional(number, 0), evaluation_periods = optional(number, 1), datapoints_to_alarm = optional(number, 1), period = optional(number, 60), severity = optional(string, "warning") }), {})
    }), {})
  }))
  default  = {}
  nullable = false
}

variable "cloudfront_distributions" {
  description = "CloudFront distributions by key; alarms in us-east-1."
  type = map(object({
    distribution_id = string
    alarms = optional(object({
      server_error_rate = optional(object({ enabled = optional(bool, true), threshold = optional(number, 5), evaluation_periods = optional(number, 5), datapoints_to_alarm = optional(number, 5), period = optional(number, 60), severity = optional(string, "critical") }), {})
      client_error_rate = optional(object({ enabled = optional(bool, false), threshold = optional(number), evaluation_periods = optional(number, 5), datapoints_to_alarm = optional(number, 5), period = optional(number, 60), severity = optional(string, "warning") }), {})
      requests          = optional(object({ enabled = optional(bool, false), threshold = optional(number), evaluation_periods = optional(number, 5), datapoints_to_alarm = optional(number, 5), period = optional(number, 60), severity = optional(string, "info") }), {})
    }), {})
  }))
  default  = {}
  nullable = false
}

variable "efs_file_systems" {
  description = "EFS file systems by key."
  type = map(object({
    file_system_id  = string
    throughput_mode = optional(string, "elastic")
    region          = optional(string)
    alarms = optional(object({
      percent_io_limit     = optional(object({ enabled = optional(bool, true), threshold = optional(number, 95), evaluation_periods = optional(number, 15), datapoints_to_alarm = optional(number, 15), period = optional(number, 60), severity = optional(string, "warning") }), {})
      burst_credit_balance = optional(object({ enabled = optional(bool, true), threshold = optional(number, 0), evaluation_periods = optional(number, 15), datapoints_to_alarm = optional(number, 15), period = optional(number, 60), severity = optional(string, "warning") }), {})
      client_connections   = optional(object({ enabled = optional(bool, false), threshold = optional(number), evaluation_periods = optional(number, 5), datapoints_to_alarm = optional(number, 5), period = optional(number, 60), severity = optional(string, "warning") }), {})
    }), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k, f in var.efs_file_systems : contains(["elastic", "bursting", "provisioned"], f.throughput_mode)])
    error_message = "efs_file_systems: throughput_mode elastic, bursting or provisioned."
  }
}

variable "waf_web_acls" {
  description = "WAF web ACLs by key: metric names and scope."
  type = map(object({
    web_acl_metric_name = string
    rule_metric_name    = optional(string, "ALL")
    scope               = optional(string, "REGIONAL")
    region              = optional(string)
    alarms = optional(object({
      blocked_requests = optional(object({ enabled = optional(bool, true), threshold = optional(number), evaluation_periods = optional(number, 1), datapoints_to_alarm = optional(number, 1), period = optional(number, 300), severity = optional(string, "warning") }), {})
    }), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k, w in var.waf_web_acls : contains(["REGIONAL", "CLOUDFRONT"], w.scope)])
    error_message = "waf_web_acls: scope REGIONAL or CLOUDFRONT."
  }

  validation {
    condition     = alltrue([for k, w in var.waf_web_acls : w.alarms.blocked_requests.enabled ? (w.alarms.blocked_requests.threshold == null ? false : w.alarms.blocked_requests.threshold >= 0) : true])
    error_message = "waf_web_acls: blocked_requests threshold >= 0."
  }
}

variable "s3_buckets" {
  description = "S3 buckets by key: bucket name and size threshold."
  type = map(object({
    bucket_name = string
    region      = optional(string)
    alarms = optional(object({
      bucket_size = optional(object({ enabled = optional(bool, true), threshold = optional(number), evaluation_periods = optional(number, 1), datapoints_to_alarm = optional(number, 1), period = optional(number, 86400), severity = optional(string, "info") }), {})
    }), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k, b in var.s3_buckets : b.alarms.bucket_size.enabled ? (b.alarms.bucket_size.threshold == null ? false : b.alarms.bucket_size.threshold > 0) : true])
    error_message = "s3_buckets: bucket_size threshold > 0."
  }
}

variable "nat_gateways" {
  description = "NAT gateways by key."
  type = map(object({
    nat_gateway_id     = string
    availability_zones = optional(list(string), [])
    region             = optional(string)
    alarms = optional(object({
      error_port_allocation = optional(object({ enabled = optional(bool, true), threshold = optional(number, 0), evaluation_periods = optional(number, 15), datapoints_to_alarm = optional(number, 15), period = optional(number, 60), severity = optional(string, "critical") }), {})
      packets_drop_rate     = optional(object({ enabled = optional(bool, true), threshold = optional(number, 0.01), evaluation_periods = optional(number, 5), datapoints_to_alarm = optional(number, 5), period = optional(number, 60), severity = optional(string, "warning") }), {})
    }), {})
  }))
  default  = {}
  nullable = false
}

variable "log_metric_filters" {
  description = "Log metric filters by key, each with an alarm."
  type = map(object({
    log_group_name = string
    pattern        = string
    metric_name    = optional(string)
    namespace      = optional(string)
    metric_value   = optional(string, "1")
    default_value  = optional(string)
    unit           = optional(string)
    region         = optional(string)
    alarm = optional(object({
      enabled             = optional(bool, true)
      severity            = optional(string, "warning")
      description         = optional(string)
      comparison_operator = optional(string, "GreaterThanOrEqualToThreshold")
      threshold           = optional(number, 1)
      evaluation_periods  = optional(number, 1)
      datapoints_to_alarm = optional(number)
      period              = optional(number, 300)
      statistic           = optional(string, "Sum")
      treat_missing_data  = optional(string, "notBreaching")
    }), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for k, f in var.log_metric_filters : contains(["GreaterThanOrEqualToThreshold", "GreaterThanThreshold", "LessThanThreshold", "LessThanOrEqualToThreshold"], f.alarm.comparison_operator) && contains(["missing", "ignore", "breaching", "notBreaching"], f.alarm.treat_missing_data)
    ])
    error_message = "log_metric_filters: static operator and valid treat_missing_data."
  }
}

variable "cis_cloudtrail_metric_filters" {
  description = "CIS CloudWatch.1-14 metric filters and alarms on the CloudTrail log group."
  type = object({
    enabled        = optional(bool, false)
    severity       = optional(string, "critical")
    log_group_name = optional(string)
    namespace      = optional(string)
    region         = optional(string)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.cis_cloudtrail_metric_filters.enabled ? (var.cis_cloudtrail_metric_filters.log_group_name == null ? false : length(var.cis_cloudtrail_metric_filters.log_group_name) > 0) : true
    error_message = "cis_cloudtrail_metric_filters: log_group_name required."
  }

  validation {
    condition     = !var.cis_cloudtrail_metric_filters.enabled || var.notifications.enabled
    error_message = "cis_cloudtrail_metric_filters: needs notifications.enabled."
  }
}
