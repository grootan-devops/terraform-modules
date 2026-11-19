locals {
  lambda_alarm_defs = flatten([
    for k, f in var.lambda_functions : [
      {
        key                 = "lambda-${k}-error-rate"
        preset              = "lambda_functions"
        cfg                 = f.alarms.error_rate
        enabled             = f.alarms.error_rate.enabled
        threshold           = f.alarms.error_rate.threshold
        description         = "Lambda ${f.function_name}: error rate % (100 * Errors / Invocations, 0 when there are no invocations) above threshold."
        region              = f.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "notBreaching"
        namespace           = null
        metric_name         = null
        dimensions          = {}
        statistic           = null
        extended_statistic  = null
        queries = [
          { id = "errors", expression = null, label = "Errors", return_data = false, metric = { namespace = "AWS/Lambda", metric_name = "Errors", dimensions = { FunctionName = f.function_name }, stat = "Sum" } },
          { id = "invocations", expression = null, label = "Invocations", return_data = false, metric = { namespace = "AWS/Lambda", metric_name = "Invocations", dimensions = { FunctionName = f.function_name }, stat = "Sum" } },
          { id = "error_rate", expression = "IF(invocations > 0, 100 * errors / invocations, 0)", label = "Error rate (%)", return_data = true, metric = null },
        ]
      },
      {
        key                 = "lambda-${k}-throttles"
        preset              = "lambda_functions"
        cfg                 = f.alarms.throttles
        enabled             = f.alarms.throttles.enabled
        threshold           = f.alarms.throttles.threshold
        description         = "Lambda ${f.function_name}: throttled invocation requests (Throttles, Sum) above threshold."
        region              = f.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "notBreaching"
        namespace           = "AWS/Lambda"
        metric_name         = "Throttles"
        dimensions          = { FunctionName = f.function_name }
        statistic           = "Sum"
        extended_statistic  = null
        queries             = []
      },
      {
        key                 = "lambda-${k}-duration-p99"
        preset              = "lambda_functions"
        cfg                 = f.alarms.duration_p99
        enabled             = f.alarms.duration_p99.enabled
        threshold           = f.alarms.duration_p99.threshold != null ? f.alarms.duration_p99.threshold : (f.timeout_seconds == null ? null : f.timeout_seconds * 1000 * 0.8)
        description         = "Lambda ${f.function_name}: Duration p99 (ms) above threshold (default 80 % of the function timeout)."
        region              = f.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "notBreaching"
        namespace           = "AWS/Lambda"
        metric_name         = "Duration"
        dimensions          = { FunctionName = f.function_name }
        statistic           = null
        extended_statistic  = "p99"
        queries             = []
      },
      {
        key                 = "lambda-${k}-concurrent-executions"
        preset              = "lambda_functions"
        cfg                 = f.alarms.concurrent_executions
        enabled             = f.alarms.concurrent_executions.enabled
        threshold           = f.alarms.concurrent_executions.threshold
        description         = "Lambda ${f.function_name}: ConcurrentExecutions (Maximum) above threshold (default 90 % of the 1,000 default Regional concurrency quota)."
        region              = f.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "notBreaching"
        namespace           = "AWS/Lambda"
        metric_name         = "ConcurrentExecutions"
        dimensions          = { FunctionName = f.function_name }
        statistic           = "Maximum"
        extended_statistic  = null
        queries             = []
      },
      {
        key                 = "lambda-${k}-iterator-age"
        preset              = "lambda_functions"
        cfg                 = f.alarms.iterator_age
        enabled             = f.alarms.iterator_age.enabled && f.event_source == "stream"
        threshold           = f.alarms.iterator_age.threshold
        description         = "Lambda ${f.function_name}: stream IteratorAge (ms, Maximum) above threshold - the consumer is falling behind the stream."
        region              = f.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "notBreaching"
        namespace           = "AWS/Lambda"
        metric_name         = "IteratorAge"
        dimensions          = { FunctionName = f.function_name }
        statistic           = "Maximum"
        extended_statistic  = null
        queries             = []
      },
    ]
  ])

  apigw_alarm_defs = flatten([
    for k, a in var.api_gateways : [
      {
        key                 = "apigw-${k}-5xx-rate"
        preset              = "api_gateways"
        cfg                 = a.alarms.server_error_rate
        enabled             = a.alarms.server_error_rate.enabled
        threshold           = a.alarms.server_error_rate.threshold
        description         = "API Gateway ${a.api_name}/${a.stage}: 5XX error rate % (100 * 5XXError Sum / Count SampleCount) above threshold."
        region              = a.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "notBreaching"
        namespace           = null
        metric_name         = null
        dimensions          = {}
        statistic           = null
        extended_statistic  = null
        queries = [
          { id = "errors", expression = null, label = "5XXError", return_data = false, metric = { namespace = "AWS/ApiGateway", metric_name = "5XXError", dimensions = { ApiName = a.api_name, Stage = a.stage }, stat = "Sum" } },
          { id = "requests", expression = null, label = "Count", return_data = false, metric = { namespace = "AWS/ApiGateway", metric_name = "Count", dimensions = { ApiName = a.api_name, Stage = a.stage }, stat = "SampleCount" } },
          { id = "error_rate", expression = "IF(requests > 0, 100 * errors / requests, 0)", label = "5XX error rate (%)", return_data = true, metric = null },
        ]
      },
      {
        key                 = "apigw-${k}-4xx-rate"
        preset              = "api_gateways"
        cfg                 = a.alarms.client_error_rate
        enabled             = a.alarms.client_error_rate.enabled
        threshold           = a.alarms.client_error_rate.threshold
        description         = "API Gateway ${a.api_name}/${a.stage}: 4XX error rate % (100 * 4XXError Sum / Count SampleCount) above threshold."
        region              = a.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "notBreaching"
        namespace           = null
        metric_name         = null
        dimensions          = {}
        statistic           = null
        extended_statistic  = null
        queries = [
          { id = "errors", expression = null, label = "4XXError", return_data = false, metric = { namespace = "AWS/ApiGateway", metric_name = "4XXError", dimensions = { ApiName = a.api_name, Stage = a.stage }, stat = "Sum" } },
          { id = "requests", expression = null, label = "Count", return_data = false, metric = { namespace = "AWS/ApiGateway", metric_name = "Count", dimensions = { ApiName = a.api_name, Stage = a.stage }, stat = "SampleCount" } },
          { id = "error_rate", expression = "IF(requests > 0, 100 * errors / requests, 0)", label = "4XX error rate (%)", return_data = true, metric = null },
        ]
      },
      {
        key                 = "apigw-${k}-latency-p99"
        preset              = "api_gateways"
        cfg                 = a.alarms.latency_p99
        enabled             = a.alarms.latency_p99.enabled
        threshold           = a.alarms.latency_p99.threshold
        description         = "API Gateway ${a.api_name}/${a.stage}: Latency p99 (ms) above threshold."
        region              = a.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "notBreaching"
        namespace           = "AWS/ApiGateway"
        metric_name         = "Latency"
        dimensions          = { ApiName = a.api_name, Stage = a.stage }
        statistic           = null
        extended_statistic  = "p99"
        queries             = []
      },
      {
        key                 = "apigw-${k}-integration-latency-p99"
        preset              = "api_gateways"
        cfg                 = a.alarms.integration_latency_p99
        enabled             = a.alarms.integration_latency_p99.enabled
        threshold           = a.alarms.integration_latency_p99.threshold
        description         = "API Gateway ${a.api_name}/${a.stage}: IntegrationLatency p99 (ms) above threshold."
        region              = a.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "notBreaching"
        namespace           = "AWS/ApiGateway"
        metric_name         = "IntegrationLatency"
        dimensions          = { ApiName = a.api_name, Stage = a.stage }
        statistic           = null
        extended_statistic  = "p99"
        queries             = []
      },
    ]
  ])

  alb_alarm_defs = flatten([
    for k, l in var.albs : concat(
      [
        {
          key                 = "alb-${k}-target-5xx-rate"
          preset              = "albs"
          cfg                 = l.alarms.target_5xx_rate
          enabled             = l.alarms.target_5xx_rate.enabled
          threshold           = l.alarms.target_5xx_rate.threshold
          description         = "ALB ${l.load_balancer_arn_suffix}: target 5XX rate % (100 * HTTPCode_Target_5XX_Count / RequestCount) above threshold."
          region              = l.region
          comparison_operator = "GreaterThanThreshold"
          treat_missing_data  = "notBreaching"
          namespace           = null
          metric_name         = null
          dimensions          = {}
          statistic           = null
          extended_statistic  = null
          queries = [
            { id = "errors", expression = null, label = "HTTPCode_Target_5XX_Count", return_data = false, metric = { namespace = "AWS/ApplicationELB", metric_name = "HTTPCode_Target_5XX_Count", dimensions = { LoadBalancer = l.load_balancer_arn_suffix }, stat = "Sum" } },
            { id = "requests", expression = null, label = "RequestCount", return_data = false, metric = { namespace = "AWS/ApplicationELB", metric_name = "RequestCount", dimensions = { LoadBalancer = l.load_balancer_arn_suffix }, stat = "Sum" } },
            { id = "error_rate", expression = "IF(requests > 0, 100 * errors / requests, 0)", label = "Target 5XX rate (%)", return_data = true, metric = null },
          ]
        },
        {
          key                 = "alb-${k}-elb-5xx-count"
          preset              = "albs"
          cfg                 = l.alarms.elb_5xx_count
          enabled             = l.alarms.elb_5xx_count.enabled
          threshold           = l.alarms.elb_5xx_count.threshold
          description         = "ALB ${l.load_balancer_arn_suffix}: 5XX responses generated by the load balancer itself (HTTPCode_ELB_5XX_Count, Sum) above threshold."
          region              = l.region
          comparison_operator = "GreaterThanThreshold"
          treat_missing_data  = "notBreaching"
          namespace           = "AWS/ApplicationELB"
          metric_name         = "HTTPCode_ELB_5XX_Count"
          dimensions          = { LoadBalancer = l.load_balancer_arn_suffix }
          statistic           = "Sum"
          extended_statistic  = null
          queries             = []
        },
        {
          key                 = "alb-${k}-target-response-time-p99"
          preset              = "albs"
          cfg                 = l.alarms.target_response_time_p99
          enabled             = l.alarms.target_response_time_p99.enabled
          threshold           = l.alarms.target_response_time_p99.threshold != null ? l.alarms.target_response_time_p99.threshold : coalesce(l.idle_timeout_seconds, 60) * 0.8
          description         = "ALB ${l.load_balancer_arn_suffix}: TargetResponseTime p99 (seconds) above threshold (default 80 % of the idle timeout, after which the ALB returns 504)."
          region              = l.region
          comparison_operator = "GreaterThanThreshold"
          treat_missing_data  = "notBreaching"
          namespace           = "AWS/ApplicationELB"
          metric_name         = "TargetResponseTime"
          dimensions          = { LoadBalancer = l.load_balancer_arn_suffix }
          statistic           = null
          extended_statistic  = "p99"
          queries             = []
        },
        {
          key                 = "alb-${k}-rejected-connections"
          preset              = "albs"
          cfg                 = l.alarms.rejected_connections
          enabled             = l.alarms.rejected_connections.enabled
          threshold           = l.alarms.rejected_connections.threshold
          description         = "ALB ${l.load_balancer_arn_suffix}: connections rejected at the load balancer connection limit (RejectedConnectionCount, Sum) above threshold."
          region              = l.region
          comparison_operator = "GreaterThanThreshold"
          treat_missing_data  = "notBreaching"
          namespace           = "AWS/ApplicationELB"
          metric_name         = "RejectedConnectionCount"
          dimensions          = { LoadBalancer = l.load_balancer_arn_suffix }
          statistic           = "Sum"
          extended_statistic  = null
          queries             = []
        },
      ],
      [
        for t, s in l.target_groups : {
          key                 = "alb-${k}-${t}-unhealthy-hosts"
          preset              = "albs"
          cfg                 = l.alarms.unhealthy_hosts
          enabled             = l.alarms.unhealthy_hosts.enabled
          threshold           = l.alarms.unhealthy_hosts.threshold
          description         = "ALB ${l.load_balancer_arn_suffix} target group ${s}: UnHealthyHostCount (Maximum) above threshold."
          region              = l.region
          comparison_operator = "GreaterThanThreshold"
          treat_missing_data  = "notBreaching"
          namespace           = "AWS/ApplicationELB"
          metric_name         = "UnHealthyHostCount"
          dimensions          = { LoadBalancer = l.load_balancer_arn_suffix, TargetGroup = s }
          statistic           = "Maximum"
          extended_statistic  = null
          queries             = []
        }
      ],
    )
  ])

  nlb_alarm_defs = flatten([
    for k, l in var.nlbs : [
      for t, s in l.target_groups : [
        {
          key                 = "nlb-${k}-${t}-unhealthy-hosts"
          preset              = "nlbs"
          cfg                 = l.alarms.unhealthy_hosts
          enabled             = l.alarms.unhealthy_hosts.enabled
          threshold           = l.alarms.unhealthy_hosts.threshold
          description         = "NLB ${l.load_balancer_arn_suffix} target group ${s}: UnHealthyHostCount (Maximum) above threshold."
          region              = l.region
          comparison_operator = "GreaterThanThreshold"
          treat_missing_data  = "notBreaching"
          namespace           = "AWS/NetworkELB"
          metric_name         = "UnHealthyHostCount"
          dimensions          = { LoadBalancer = l.load_balancer_arn_suffix, TargetGroup = s }
          statistic           = "Maximum"
          extended_statistic  = null
          queries             = []
        },
        {
          key                 = "nlb-${k}-${t}-no-healthy-hosts"
          preset              = "nlbs"
          cfg                 = l.alarms.no_healthy_hosts
          enabled             = l.alarms.no_healthy_hosts.enabled
          threshold           = l.alarms.no_healthy_hosts.threshold
          description         = "NLB ${l.load_balancer_arn_suffix} target group ${s}: HealthyHostCount (Minimum) below threshold."
          region              = l.region
          comparison_operator = "LessThanThreshold"
          treat_missing_data  = "breaching"
          namespace           = "AWS/NetworkELB"
          metric_name         = "HealthyHostCount"
          dimensions          = { LoadBalancer = l.load_balancer_arn_suffix, TargetGroup = s }
          statistic           = "Minimum"
          extended_statistic  = null
          queries             = []
        },
      ]
    ]
  ])

  http_api_alarm_defs = flatten([
    for k, a in var.http_apis : [
      {
        key                 = "httpapi-${k}-5xx-rate"
        preset              = "http_apis"
        cfg                 = a.alarms.server_error_rate
        enabled             = a.alarms.server_error_rate.enabled
        threshold           = a.alarms.server_error_rate.threshold
        description         = "HTTP API ${a.api_id}/${a.stage}: 5xx rate % (100 * 5xx Sum / Count Sum) above threshold."
        region              = a.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "notBreaching"
        namespace           = null
        metric_name         = null
        dimensions          = {}
        statistic           = null
        extended_statistic  = null
        queries = [
          { id = "errors", expression = null, label = "5xx", return_data = false, metric = { namespace = "AWS/ApiGateway", metric_name = "5xx", dimensions = { ApiId = a.api_id, Stage = a.stage }, stat = "Sum" } },
          { id = "requests", expression = null, label = "Count", return_data = false, metric = { namespace = "AWS/ApiGateway", metric_name = "Count", dimensions = { ApiId = a.api_id, Stage = a.stage }, stat = "Sum" } },
          { id = "error_rate", expression = "IF(requests > 0, 100 * errors / requests, 0)", label = "5xx rate (%)", return_data = true, metric = null },
        ]
      },
      {
        key                 = "httpapi-${k}-latency-p99"
        preset              = "http_apis"
        cfg                 = a.alarms.latency_p99
        enabled             = a.alarms.latency_p99.enabled
        threshold           = a.alarms.latency_p99.threshold
        description         = "HTTP API ${a.api_id}/${a.stage}: Latency p99 (ms) above threshold."
        region              = a.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "notBreaching"
        namespace           = "AWS/ApiGateway"
        metric_name         = "Latency"
        dimensions          = { ApiId = a.api_id, Stage = a.stage }
        statistic           = null
        extended_statistic  = "p99"
        queries             = []
      },
    ]
  ])

  scheduler_alarm_defs = flatten([
    for k, g in var.schedule_groups : [
      for m in [
        { suffix = "target-errors", metric = "TargetErrorCount", cfg = g.alarms.target_errors, what = "target invocations that returned an error" },
        { suffix = "invocations-dropped", metric = "InvocationDroppedCount", cfg = g.alarms.invocations_dropped, what = "invocations dropped after the retry policy" },
        { suffix = "dlq-send-failures", metric = "InvocationsFailedToBeSentToDeadLetterCount", cfg = g.alarms.invocations_failed_to_dlq, what = "invocations that could not be sent to the dead-letter queue" },
        ] : {
        key                 = "scheduler-${k}-${m.suffix}"
        preset              = "schedule_groups"
        cfg                 = m.cfg
        enabled             = m.cfg.enabled
        threshold           = m.cfg.threshold
        description         = "EventBridge Scheduler group ${g.schedule_group_name}: ${m.what} (${m.metric}, Sum) above threshold."
        region              = g.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "notBreaching"
        namespace           = "AWS/Scheduler"
        metric_name         = m.metric
        dimensions          = { ScheduleGroup = g.schedule_group_name }
        statistic           = "Sum"
        extended_statistic  = null
        queries             = []
      }
    ]
  ])

  ecs_alarm_defs = flatten([
    for k, s in var.ecs_services : [
      {
        key                 = "ecs-${k}-cpu"
        preset              = "ecs_services"
        cfg                 = s.alarms.cpu
        enabled             = s.alarms.cpu.enabled
        threshold           = s.alarms.cpu.threshold
        description         = "ECS ${s.cluster_name}/${s.service_name}: service CPUUtilization % (Average) above threshold."
        region              = s.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "missing"
        namespace           = "AWS/ECS"
        metric_name         = "CPUUtilization"
        dimensions          = { ClusterName = s.cluster_name, ServiceName = s.service_name }
        statistic           = "Average"
        extended_statistic  = null
        queries             = []
      },
      {
        key                 = "ecs-${k}-memory"
        preset              = "ecs_services"
        cfg                 = s.alarms.memory
        enabled             = s.alarms.memory.enabled
        threshold           = s.alarms.memory.threshold
        description         = "ECS ${s.cluster_name}/${s.service_name}: service MemoryUtilization % (Average) above threshold."
        region              = s.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "missing"
        namespace           = "AWS/ECS"
        metric_name         = "MemoryUtilization"
        dimensions          = { ClusterName = s.cluster_name, ServiceName = s.service_name }
        statistic           = "Average"
        extended_statistic  = null
        queries             = []
      },
      {
        key                 = "ecs-${k}-running-tasks"
        preset              = "ecs_services"
        cfg                 = s.alarms.running_tasks
        enabled             = s.alarms.running_tasks.enabled && s.container_insights
        threshold           = s.alarms.running_tasks.threshold
        description         = "ECS ${s.cluster_name}/${s.service_name}: running tasks below desired (DesiredTaskCount - RunningTaskCount, Container Insights) above threshold."
        region              = s.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "missing"
        namespace           = null
        metric_name         = null
        dimensions          = {}
        statistic           = null
        extended_statistic  = null
        queries = [
          { id = "desired", expression = null, label = "DesiredTaskCount", return_data = false, metric = { namespace = "ECS/ContainerInsights", metric_name = "DesiredTaskCount", dimensions = { ClusterName = s.cluster_name, ServiceName = s.service_name }, stat = "Average" } },
          { id = "running", expression = null, label = "RunningTaskCount", return_data = false, metric = { namespace = "ECS/ContainerInsights", metric_name = "RunningTaskCount", dimensions = { ClusterName = s.cluster_name, ServiceName = s.service_name }, stat = "Average" } },
          { id = "tasks_short", expression = "desired - running", label = "Tasks below desired", return_data = true, metric = null },
        ]
      },
    ]
  ])

  eks_alarm_defs = flatten([
    for k, c in var.eks_clusters : [
      {
        key                 = "eks-${k}-node-cpu"
        preset              = "eks_clusters"
        cfg                 = c.alarms.node_cpu
        enabled             = c.alarms.node_cpu.enabled && c.container_insights
        threshold           = c.alarms.node_cpu.threshold
        description         = "EKS ${c.cluster_name}: node_cpu_utilization % (Maximum, Container Insights) above threshold."
        region              = c.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "missing"
        namespace           = "ContainerInsights"
        metric_name         = "node_cpu_utilization"
        dimensions          = { ClusterName = c.cluster_name }
        statistic           = "Maximum"
        extended_statistic  = null
        queries             = []
      },
      {
        key                 = "eks-${k}-node-memory"
        preset              = "eks_clusters"
        cfg                 = c.alarms.node_memory
        enabled             = c.alarms.node_memory.enabled && c.container_insights
        threshold           = c.alarms.node_memory.threshold
        description         = "EKS ${c.cluster_name}: node_memory_utilization % (Maximum, Container Insights) above threshold."
        region              = c.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "missing"
        namespace           = "ContainerInsights"
        metric_name         = "node_memory_utilization"
        dimensions          = { ClusterName = c.cluster_name }
        statistic           = "Maximum"
        extended_statistic  = null
        queries             = []
      },
      {
        key                 = "eks-${k}-failed-nodes"
        preset              = "eks_clusters"
        cfg                 = c.alarms.failed_nodes
        enabled             = c.alarms.failed_nodes.enabled && c.container_insights
        threshold           = c.alarms.failed_nodes.threshold
        description         = "EKS ${c.cluster_name}: cluster_failed_node_count (Maximum, Container Insights) above threshold."
        region              = c.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "missing"
        namespace           = "ContainerInsights"
        metric_name         = "cluster_failed_node_count"
        dimensions          = { ClusterName = c.cluster_name }
        statistic           = "Maximum"
        extended_statistic  = null
        queries             = []
      },
    ]
  ])

  asg_alarm_defs = flatten([
    for k, g in var.auto_scaling_groups : [
      {
        key                 = "asg-${k}-cpu"
        preset              = "auto_scaling_groups"
        cfg                 = g.alarms.cpu
        enabled             = g.alarms.cpu.enabled
        threshold           = g.alarms.cpu.threshold
        description         = "Auto Scaling group ${g.auto_scaling_group_name}: aggregate EC2 CPUUtilization % (Average) above threshold."
        region              = g.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "missing"
        namespace           = "AWS/EC2"
        metric_name         = "CPUUtilization"
        dimensions          = { AutoScalingGroupName = g.auto_scaling_group_name }
        statistic           = "Average"
        extended_statistic  = null
        queries             = []
      },
      {
        key                 = "asg-${k}-status-check-failed"
        preset              = "auto_scaling_groups"
        cfg                 = g.alarms.status_check_failed
        enabled             = g.alarms.status_check_failed.enabled
        threshold           = g.alarms.status_check_failed.threshold
        description         = "Auto Scaling group ${g.auto_scaling_group_name}: an instance failed EC2 status checks (StatusCheckFailed, Maximum) above threshold."
        region              = g.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "missing"
        namespace           = "AWS/EC2"
        metric_name         = "StatusCheckFailed"
        dimensions          = { AutoScalingGroupName = g.auto_scaling_group_name }
        statistic           = "Maximum"
        extended_statistic  = null
        queries             = []
      },
    ]
  ])

  rds_alarm_defs = flatten([
    for k, d in var.rds_instances : [
      {
        key                 = "rds-${k}-cpu"
        preset              = "rds_instances"
        cfg                 = d.alarms.cpu
        enabled             = d.alarms.cpu.enabled
        threshold           = d.alarms.cpu.threshold
        description         = "RDS ${d.db_instance_identifier}: CPUUtilization % (Average) above threshold."
        region              = d.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "missing"
        namespace           = "AWS/RDS"
        metric_name         = "CPUUtilization"
        dimensions          = { DBInstanceIdentifier = d.db_instance_identifier }
        statistic           = "Average"
        extended_statistic  = null
        queries             = []
      },
      {
        key                 = "rds-${k}-free-storage"
        preset              = "rds_instances"
        cfg                 = d.alarms.free_storage
        enabled             = d.alarms.free_storage.enabled
        threshold           = d.alarms.free_storage.threshold != null ? d.alarms.free_storage.threshold : (d.allocated_storage_gib == null ? null : d.allocated_storage_gib * local.bytes_per_gib * local.rds_free_storage_percent / 100)
        description         = "RDS ${d.db_instance_identifier}: FreeStorageSpace bytes (Minimum) below threshold (default 20 % of allocated storage; re-apply after storage autoscaling)."
        region              = d.region
        comparison_operator = "LessThanThreshold"
        treat_missing_data  = "missing"
        namespace           = "AWS/RDS"
        metric_name         = "FreeStorageSpace"
        dimensions          = { DBInstanceIdentifier = d.db_instance_identifier }
        statistic           = "Minimum"
        extended_statistic  = null
        queries             = []
      },
      {
        key                 = "rds-${k}-freeable-memory"
        preset              = "rds_instances"
        cfg                 = d.alarms.freeable_memory
        enabled             = d.alarms.freeable_memory.enabled
        threshold           = d.alarms.freeable_memory.threshold
        description         = "RDS ${d.db_instance_identifier}: FreeableMemory bytes (Average) below threshold."
        region              = d.region
        comparison_operator = "LessThanThreshold"
        treat_missing_data  = "missing"
        namespace           = "AWS/RDS"
        metric_name         = "FreeableMemory"
        dimensions          = { DBInstanceIdentifier = d.db_instance_identifier }
        statistic           = "Average"
        extended_statistic  = null
        queries             = []
      },
      {
        key                 = "rds-${k}-connections"
        preset              = "rds_instances"
        cfg                 = d.alarms.database_connections
        enabled             = d.alarms.database_connections.enabled
        threshold           = d.alarms.database_connections.threshold
        description         = "RDS ${d.db_instance_identifier}: DatabaseConnections (Average) above threshold (set 90-95 % of max_connections)."
        region              = d.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "missing"
        namespace           = "AWS/RDS"
        metric_name         = "DatabaseConnections"
        dimensions          = { DBInstanceIdentifier = d.db_instance_identifier }
        statistic           = "Average"
        extended_statistic  = null
        queries             = []
      },
      {
        key                 = "rds-${k}-read-latency-p99"
        preset              = "rds_instances"
        cfg                 = d.alarms.read_latency_p99
        enabled             = d.alarms.read_latency_p99.enabled
        threshold           = d.alarms.read_latency_p99.threshold
        description         = "RDS ${d.db_instance_identifier}: ReadLatency p99 (seconds per disk I/O) above threshold."
        region              = d.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "missing"
        namespace           = "AWS/RDS"
        metric_name         = "ReadLatency"
        dimensions          = { DBInstanceIdentifier = d.db_instance_identifier }
        statistic           = null
        extended_statistic  = "p99"
        queries             = []
      },
      {
        key                 = "rds-${k}-write-latency-p99"
        preset              = "rds_instances"
        cfg                 = d.alarms.write_latency_p99
        enabled             = d.alarms.write_latency_p99.enabled
        threshold           = d.alarms.write_latency_p99.threshold
        description         = "RDS ${d.db_instance_identifier}: WriteLatency p99 (seconds per disk I/O) above threshold."
        region              = d.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "missing"
        namespace           = "AWS/RDS"
        metric_name         = "WriteLatency"
        dimensions          = { DBInstanceIdentifier = d.db_instance_identifier }
        statistic           = null
        extended_statistic  = "p99"
        queries             = []
      },
    ]
  ])

  rds_proxy_alarm_defs = flatten([
    for k, p in var.rds_proxies : [
      {
        key                 = "rdsproxy-${k}-connection-setup-failures"
        preset              = "rds_proxies"
        cfg                 = p.alarms.connection_setup_failures
        enabled             = p.alarms.connection_setup_failures.enabled
        threshold           = p.alarms.connection_setup_failures.threshold
        description         = "RDS Proxy ${p.proxy_name}: failed database connection requests (DatabaseConnectionsSetupFailed, Sum) above threshold."
        region              = p.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "notBreaching"
        namespace           = "AWS/RDS"
        metric_name         = "DatabaseConnectionsSetupFailed"
        dimensions          = { ProxyName = p.proxy_name }
        statistic           = "Sum"
        extended_statistic  = null
        queries             = []
      },
      {
        key                 = "rdsproxy-${k}-client-auth-failures"
        preset              = "rds_proxies"
        cfg                 = p.alarms.client_auth_failures
        enabled             = p.alarms.client_auth_failures.enabled
        threshold           = p.alarms.client_auth_failures.threshold
        description         = "RDS Proxy ${p.proxy_name}: client connections failing authentication or TLS (ClientConnectionsSetupFailedAuth, Sum) above threshold."
        region              = p.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "notBreaching"
        namespace           = "AWS/RDS"
        metric_name         = "ClientConnectionsSetupFailedAuth"
        dimensions          = { ProxyName = p.proxy_name }
        statistic           = "Sum"
        extended_statistic  = null
        queries             = []
      },
      {
        key                 = "rdsproxy-${k}-borrowed-connections"
        preset              = "rds_proxies"
        cfg                 = p.alarms.borrowed_connections
        enabled             = p.alarms.borrowed_connections.enabled
        threshold           = p.alarms.borrowed_connections.threshold
        description         = "RDS Proxy ${p.proxy_name}: pool saturation % (100 * DatabaseConnectionsCurrentlyBorrowed / MaxDatabaseConnectionsAllowed) above threshold."
        region              = p.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "notBreaching"
        namespace           = null
        metric_name         = null
        dimensions          = {}
        statistic           = null
        extended_statistic  = null
        queries = [
          { id = "borrowed", expression = null, label = "DatabaseConnectionsCurrentlyBorrowed", return_data = false, metric = { namespace = "AWS/RDS", metric_name = "DatabaseConnectionsCurrentlyBorrowed", dimensions = { ProxyName = p.proxy_name }, stat = "Sum" } },
          { id = "max_allowed", expression = null, label = "MaxDatabaseConnectionsAllowed", return_data = false, metric = { namespace = "AWS/RDS", metric_name = "MaxDatabaseConnectionsAllowed", dimensions = { ProxyName = p.proxy_name }, stat = "Sum" } },
          { id = "borrowed_percent", expression = "IF(max_allowed > 0, 100 * borrowed / max_allowed, 0)", label = "Borrowed connections (%)", return_data = true, metric = null },
        ]
      },
      {
        key                 = "rdsproxy-${k}-client-connections"
        preset              = "rds_proxies"
        cfg                 = p.alarms.client_connections
        enabled             = p.alarms.client_connections.enabled
        threshold           = p.alarms.client_connections.threshold
        description         = "RDS Proxy ${p.proxy_name}: ClientConnections (Sum) above threshold."
        region              = p.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "notBreaching"
        namespace           = "AWS/RDS"
        metric_name         = "ClientConnections"
        dimensions          = { ProxyName = p.proxy_name }
        statistic           = "Sum"
        extended_statistic  = null
        queries             = []
      },
    ]
  ])

  dynamodb_alarm_defs = flatten([
    for k, t in var.dynamodb_tables : concat(
      [
        for kind in ["read", "write"] : {
          key                 = "dynamodb-${k}-${kind}-throttles"
          preset              = "dynamodb_tables"
          cfg                 = kind == "read" ? t.alarms.read_throttles : t.alarms.write_throttles
          enabled             = kind == "read" ? t.alarms.read_throttles.enabled : t.alarms.write_throttles.enabled
          threshold           = kind == "read" ? t.alarms.read_throttles.threshold : t.alarms.write_throttles.threshold
          description         = "DynamoDB ${t.table_name}: ${kind == "read" ? "ReadThrottleEvents" : "WriteThrottleEvents"} (Sum) above threshold."
          region              = t.region
          comparison_operator = "GreaterThanThreshold"
          treat_missing_data  = "notBreaching"
          namespace           = "AWS/DynamoDB"
          metric_name         = kind == "read" ? "ReadThrottleEvents" : "WriteThrottleEvents"
          dimensions          = { TableName = t.table_name }
          statistic           = "Sum"
          extended_statistic  = null
          queries             = []
        }
      ],
      flatten([
        for g in t.global_secondary_index_names : [
          for kind in ["read", "write"] : {
            key                 = "dynamodb-${k}-gsi-${g}-${kind}-throttles"
            preset              = "dynamodb_tables"
            cfg                 = kind == "read" ? t.alarms.read_throttles : t.alarms.write_throttles
            enabled             = kind == "read" ? t.alarms.read_throttles.enabled : t.alarms.write_throttles.enabled
            threshold           = kind == "read" ? t.alarms.read_throttles.threshold : t.alarms.write_throttles.threshold
            description         = "DynamoDB ${t.table_name} index ${g}: ${kind == "read" ? "ReadThrottleEvents" : "WriteThrottleEvents"} (Sum) above threshold."
            region              = t.region
            comparison_operator = "GreaterThanThreshold"
            treat_missing_data  = "notBreaching"
            namespace           = "AWS/DynamoDB"
            metric_name         = kind == "read" ? "ReadThrottleEvents" : "WriteThrottleEvents"
            dimensions          = { TableName = t.table_name, GlobalSecondaryIndexName = g }
            statistic           = "Sum"
            extended_statistic  = null
            queries             = []
          }
        ]
      ]),
      [
        {
          key                 = "dynamodb-${k}-system-errors"
          preset              = "dynamodb_tables"
          cfg                 = t.alarms.system_errors
          enabled             = t.alarms.system_errors.enabled
          threshold           = t.alarms.system_errors.threshold
          description         = "DynamoDB ${t.table_name}: SystemErrors (HTTP 500, Sum over the listed operations; published only per TableName + Operation) above threshold."
          region              = t.region
          comparison_operator = "GreaterThanThreshold"
          treat_missing_data  = "notBreaching"
          namespace           = null
          metric_name         = null
          dimensions          = {}
          statistic           = null
          extended_statistic  = null
          queries = concat(
            [
              for i, o in t.system_error_operations : {
                id          = "op${i}"
                expression  = null
                label       = "SystemErrors ${o}"
                return_data = false
                metric      = { namespace = "AWS/DynamoDB", metric_name = "SystemErrors", dimensions = { TableName = t.table_name, Operation = o }, stat = "Sum" }
              }
            ],
            [
              { id = "system_errors", expression = join(" + ", [for i, o in t.system_error_operations : "op${i}"]), label = "SystemErrors (all listed operations)", return_data = true, metric = null }
            ],
          )
        },
        {
          key                 = "dynamodb-${k}-consumed-rcu"
          preset              = "dynamodb_tables"
          cfg                 = t.alarms.consumed_read_capacity
          enabled             = t.alarms.consumed_read_capacity.enabled
          threshold           = t.alarms.consumed_read_capacity.threshold
          description         = "DynamoDB ${t.table_name}: ConsumedReadCapacityUnits (Sum per period) above threshold."
          region              = t.region
          comparison_operator = "GreaterThanThreshold"
          treat_missing_data  = "notBreaching"
          namespace           = "AWS/DynamoDB"
          metric_name         = "ConsumedReadCapacityUnits"
          dimensions          = { TableName = t.table_name }
          statistic           = "Sum"
          extended_statistic  = null
          queries             = []
        },
        {
          key                 = "dynamodb-${k}-consumed-wcu"
          preset              = "dynamodb_tables"
          cfg                 = t.alarms.consumed_write_capacity
          enabled             = t.alarms.consumed_write_capacity.enabled
          threshold           = t.alarms.consumed_write_capacity.threshold
          description         = "DynamoDB ${t.table_name}: ConsumedWriteCapacityUnits (Sum per period) above threshold."
          region              = t.region
          comparison_operator = "GreaterThanThreshold"
          treat_missing_data  = "notBreaching"
          namespace           = "AWS/DynamoDB"
          metric_name         = "ConsumedWriteCapacityUnits"
          dimensions          = { TableName = t.table_name }
          statistic           = "Sum"
          extended_statistic  = null
          queries             = []
        },
      ],
    )
  ])

  elasticache_alarm_defs = flatten([
    for k, c in var.elasticache_clusters : [
      for m in c.cache_cluster_ids : [
        {
          key                 = "elasticache-${k}-${m}-cpu"
          preset              = "elasticache_clusters"
          cfg                 = c.alarms.cpu
          enabled             = c.alarms.cpu.enabled
          threshold           = c.alarms.cpu.threshold
          description         = "ElastiCache ${c.replication_group_id} member ${m}: host CPUUtilization % (Average) above threshold."
          region              = c.region
          comparison_operator = "GreaterThanThreshold"
          treat_missing_data  = "missing"
          namespace           = "AWS/ElastiCache"
          metric_name         = "CPUUtilization"
          dimensions          = { CacheClusterId = m, CacheNodeId = c.cache_node_id }
          statistic           = "Average"
          extended_statistic  = null
          queries             = []
        },
        {
          key                 = "elasticache-${k}-${m}-engine-cpu"
          preset              = "elasticache_clusters"
          cfg                 = c.alarms.engine_cpu
          enabled             = c.alarms.engine_cpu.enabled
          threshold           = c.alarms.engine_cpu.threshold
          description         = "ElastiCache ${c.replication_group_id} member ${m}: EngineCPUUtilization % (Average) above threshold."
          region              = c.region
          comparison_operator = "GreaterThanThreshold"
          treat_missing_data  = "missing"
          namespace           = "AWS/ElastiCache"
          metric_name         = "EngineCPUUtilization"
          dimensions          = { CacheClusterId = m }
          statistic           = "Average"
          extended_statistic  = null
          queries             = []
        },
        {
          key                 = "elasticache-${k}-${m}-memory"
          preset              = "elasticache_clusters"
          cfg                 = c.alarms.memory
          enabled             = c.alarms.memory.enabled
          threshold           = c.alarms.memory.threshold
          description         = "ElastiCache ${c.replication_group_id} member ${m}: DatabaseMemoryUsagePercentage (Average) above threshold."
          region              = c.region
          comparison_operator = "GreaterThanThreshold"
          treat_missing_data  = "missing"
          namespace           = "AWS/ElastiCache"
          metric_name         = "DatabaseMemoryUsagePercentage"
          dimensions          = { CacheClusterId = m }
          statistic           = "Average"
          extended_statistic  = null
          queries             = []
        },
        {
          key                 = "elasticache-${k}-${m}-evictions"
          preset              = "elasticache_clusters"
          cfg                 = c.alarms.evictions
          enabled             = c.alarms.evictions.enabled
          threshold           = c.alarms.evictions.threshold
          description         = "ElastiCache ${c.replication_group_id} member ${m}: keys evicted at maxmemory (Evictions, Sum) above threshold."
          region              = c.region
          comparison_operator = "GreaterThanThreshold"
          treat_missing_data  = "notBreaching"
          namespace           = "AWS/ElastiCache"
          metric_name         = "Evictions"
          dimensions          = { CacheClusterId = m, CacheNodeId = c.cache_node_id }
          statistic           = "Sum"
          extended_statistic  = null
          queries             = []
        },
        {
          key                 = "elasticache-${k}-${m}-curr-connections"
          preset              = "elasticache_clusters"
          cfg                 = c.alarms.curr_connections
          enabled             = c.alarms.curr_connections.enabled
          threshold           = c.alarms.curr_connections.threshold
          description         = "ElastiCache ${c.replication_group_id} member ${m}: CurrConnections (Average) above threshold."
          region              = c.region
          comparison_operator = "GreaterThanThreshold"
          treat_missing_data  = "missing"
          namespace           = "AWS/ElastiCache"
          metric_name         = "CurrConnections"
          dimensions          = { CacheClusterId = m, CacheNodeId = c.cache_node_id }
          statistic           = "Average"
          extended_statistic  = null
          queries             = []
        },
        {
          key                 = "elasticache-${k}-${m}-replication-lag"
          preset              = "elasticache_clusters"
          cfg                 = c.alarms.replication_lag
          enabled             = c.alarms.replication_lag.enabled && length(c.cache_cluster_ids) > 1
          threshold           = c.alarms.replication_lag.threshold
          description         = "ElastiCache ${c.replication_group_id} member ${m}: ReplicationLag seconds (Average) above threshold; only replicas emit it, so the primary stays OK (missing data = not breaching) and the alarm follows failovers."
          region              = c.region
          comparison_operator = "GreaterThanThreshold"
          treat_missing_data  = "notBreaching"
          namespace           = "AWS/ElastiCache"
          metric_name         = "ReplicationLag"
          dimensions          = { CacheClusterId = m }
          statistic           = "Average"
          extended_statistic  = null
          queries             = []
        },
      ]
    ]
  ])

  sqs_alarm_defs = flatten([
    for k, q in var.sqs_queues : [
      {
        key                 = "sqs-${k}-age-of-oldest-message"
        preset              = "sqs_queues"
        cfg                 = q.alarms.age_of_oldest_message
        enabled             = coalesce(q.alarms.age_of_oldest_message.enabled, q.alarms.age_of_oldest_message.threshold != null)
        threshold           = q.alarms.age_of_oldest_message.threshold
        description         = "SQS ${q.queue_name}: ApproximateAgeOfOldestMessage seconds (Maximum) above threshold - consumers are not keeping up."
        region              = q.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "notBreaching"
        namespace           = "AWS/SQS"
        metric_name         = "ApproximateAgeOfOldestMessage"
        dimensions          = { QueueName = q.queue_name }
        statistic           = "Maximum"
        extended_statistic  = null
        queries             = []
      },
      {
        key                 = "sqs-${k}-messages-visible"
        preset              = "sqs_queues"
        cfg                 = q.alarms.messages_visible
        enabled             = q.alarms.messages_visible.enabled
        threshold           = q.alarms.messages_visible.threshold
        description         = "SQS ${q.queue_name}: ApproximateNumberOfMessagesVisible (Average) above threshold - backlog growing."
        region              = q.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "notBreaching"
        namespace           = "AWS/SQS"
        metric_name         = "ApproximateNumberOfMessagesVisible"
        dimensions          = { QueueName = q.queue_name }
        statistic           = "Average"
        extended_statistic  = null
        queries             = []
      },
      {
        key                 = "sqs-${k}-dlq-messages-visible"
        preset              = "sqs_queues"
        cfg                 = q.alarms.dlq_messages_visible
        enabled             = q.alarms.dlq_messages_visible.enabled && q.dlq_name != null
        threshold           = q.alarms.dlq_messages_visible.threshold
        description         = "SQS dead-letter queue ${coalesce(q.dlq_name, "-")} of ${q.queue_name}: ApproximateNumberOfMessagesVisible (Maximum) above threshold - messages failed processing."
        region              = q.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "notBreaching"
        namespace           = "AWS/SQS"
        metric_name         = "ApproximateNumberOfMessagesVisible"
        dimensions          = { QueueName = coalesce(q.dlq_name, q.queue_name) }
        statistic           = "Maximum"
        extended_statistic  = null
        queries             = []
      },
    ]
  ])

  eventbridge_alarm_defs = flatten([
    for k, r in var.eventbridge_rules : [
      for m in [
        { suffix = "failed-invocations", metric = "FailedInvocations", cfg = r.alarms.failed_invocations, what = "target invocations that failed permanently" },
        { suffix = "throttled-rules", metric = "ThrottledRules", cfg = r.alarms.throttled_rules, what = "throttled rule executions" },
        { suffix = "dlq-send-failures", metric = "InvocationsFailedToBeSentToDlq", cfg = r.alarms.invocations_failed_to_dlq, what = "invocations that could not be moved to the dead-letter queue" },
        ] : {
        key                 = "eventbridge-${k}-${m.suffix}"
        preset              = "eventbridge_rules"
        cfg                 = m.cfg
        enabled             = m.cfg.enabled
        threshold           = m.cfg.threshold
        description         = "EventBridge rule ${r.rule_name} on bus ${coalesce(r.event_bus_name, "default")}: ${m.what} (${m.metric}, Sum) above threshold."
        region              = r.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "notBreaching"
        namespace           = "AWS/Events"
        metric_name         = m.metric
        dimensions          = merge({ RuleName = r.rule_name }, coalesce(r.event_bus_name, "default") == "default" ? {} : { EventBusName = r.event_bus_name })
        statistic           = "Sum"
        extended_statistic  = null
        queries             = []
      }
    ]
  ])

  sfn_alarm_defs = flatten([
    for k, s in var.step_functions : [
      for m in [
        { suffix = "executions-failed", metric = "ExecutionsFailed", cfg = s.alarms.executions_failed },
        { suffix = "executions-timed-out", metric = "ExecutionsTimedOut", cfg = s.alarms.executions_timed_out },
        { suffix = "executions-aborted", metric = "ExecutionsAborted", cfg = s.alarms.executions_aborted },
        { suffix = "execution-throttled", metric = "ExecutionThrottled", cfg = s.alarms.execution_throttled },
        ] : {
        key                 = "sfn-${k}-${m.suffix}"
        preset              = "step_functions"
        cfg                 = m.cfg
        enabled             = m.cfg.enabled
        threshold           = m.cfg.threshold
        description         = "Step Functions ${s.state_machine_arn}: ${m.metric} (Sum) above threshold."
        region              = s.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "notBreaching"
        namespace           = "AWS/States"
        metric_name         = m.metric
        dimensions          = { StateMachineArn = s.state_machine_arn }
        statistic           = "Sum"
        extended_statistic  = null
        queries             = []
      }
    ]
  ])

  cloudfront_alarm_defs = flatten([
    for k, d in var.cloudfront_distributions : [
      for m in [
        { suffix = "5xx-error-rate", metric = "5xxErrorRate", statistic = "Average", cfg = d.alarms.server_error_rate, what = "5xx error rate %" },
        { suffix = "4xx-error-rate", metric = "4xxErrorRate", statistic = "Average", cfg = d.alarms.client_error_rate, what = "4xx error rate %" },
        { suffix = "requests", metric = "Requests", statistic = "Sum", cfg = d.alarms.requests, what = "viewer request volume" },
        ] : {
        key                 = "cloudfront-${k}-${m.suffix}"
        preset              = "cloudfront_distributions"
        cfg                 = m.cfg
        enabled             = m.cfg.enabled
        threshold           = m.cfg.threshold
        description         = "CloudFront ${d.distribution_id}: ${m.what} (${m.metric}, ${m.statistic}) above threshold."
        region              = local.cloudfront_region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "notBreaching"
        namespace           = "AWS/CloudFront"
        metric_name         = m.metric
        dimensions          = { DistributionId = d.distribution_id, Region = "Global" }
        statistic           = m.statistic
        extended_statistic  = null
        queries             = []
      }
    ]
  ])

  efs_alarm_defs = flatten([
    for k, f in var.efs_file_systems : [
      {
        key                 = "efs-${k}-percent-io-limit"
        preset              = "efs_file_systems"
        cfg                 = f.alarms.percent_io_limit
        enabled             = f.alarms.percent_io_limit.enabled && f.performance_mode == "generalPurpose"
        threshold           = f.alarms.percent_io_limit.threshold
        description         = "EFS ${f.file_system_id}: PercentIOLimit (Average, General Purpose mode) above threshold."
        region              = f.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "notBreaching"
        namespace           = "AWS/EFS"
        metric_name         = "PercentIOLimit"
        dimensions          = { FileSystemId = f.file_system_id }
        statistic           = "Average"
        extended_statistic  = null
        queries             = []
      },
      {
        key                 = "efs-${k}-burst-credit-balance"
        preset              = "efs_file_systems"
        cfg                 = f.alarms.burst_credit_balance
        enabled             = f.alarms.burst_credit_balance.enabled && f.throughput_mode == "bursting"
        threshold           = f.alarms.burst_credit_balance.threshold
        description         = "EFS ${f.file_system_id}: BurstCreditBalance bytes (Average) at or below threshold - throughput falls back to the baseline."
        region              = f.region
        comparison_operator = "LessThanOrEqualToThreshold"
        treat_missing_data  = "missing"
        namespace           = "AWS/EFS"
        metric_name         = "BurstCreditBalance"
        dimensions          = { FileSystemId = f.file_system_id }
        statistic           = "Average"
        extended_statistic  = null
        queries             = []
      },
      {
        key                 = "efs-${k}-client-connections"
        preset              = "efs_file_systems"
        cfg                 = f.alarms.client_connections
        enabled             = f.alarms.client_connections.enabled
        threshold           = f.alarms.client_connections.threshold
        description         = "EFS ${f.file_system_id}: ClientConnections (Sum per period) above threshold."
        region              = f.region
        comparison_operator = "GreaterThanThreshold"
        treat_missing_data  = "notBreaching"
        namespace           = "AWS/EFS"
        metric_name         = "ClientConnections"
        dimensions          = { FileSystemId = f.file_system_id }
        statistic           = "Sum"
        extended_statistic  = null
        queries             = []
      },
    ]
  ])

  waf_alarm_defs = [
    for k, w in var.waf_web_acls : {
      key                 = "waf-${k}-blocked-requests"
      preset              = "waf_web_acls"
      cfg                 = w.alarms.blocked_requests
      enabled             = coalesce(w.alarms.blocked_requests.enabled, w.alarms.blocked_requests.threshold != null)
      threshold           = w.alarms.blocked_requests.threshold
      description         = "WAF web ACL ${w.web_acl_metric_name} rule ${w.rule_metric_name}: BlockedRequests (Sum) above threshold - spike in blocked traffic."
      region              = w.scope == "CLOUDFRONT" ? local.cloudfront_region : w.region
      comparison_operator = "GreaterThanThreshold"
      treat_missing_data  = "notBreaching"
      namespace           = "AWS/WAFV2"
      metric_name         = "BlockedRequests"
      dimensions          = merge({ WebACL = w.web_acl_metric_name, Rule = w.rule_metric_name }, w.scope == "REGIONAL" ? { Region = coalesce(w.region, module.naming.region) } : {})
      statistic           = "Sum"
      extended_statistic  = null
      queries             = []
    }
  ]

  s3_alarm_defs = [
    for k, b in var.s3_buckets : {
      key                 = "s3-${k}-bucket-size"
      preset              = "s3_buckets"
      cfg                 = b.alarms.bucket_size
      enabled             = coalesce(b.alarms.bucket_size.enabled, b.alarms.bucket_size.threshold != null)
      threshold           = b.alarms.bucket_size.threshold
      description         = "S3 ${b.bucket_name}: BucketSizeBytes in StandardStorage (Average, daily metric) above threshold."
      region              = b.region
      comparison_operator = "GreaterThanThreshold"
      treat_missing_data  = "ignore"
      namespace           = "AWS/S3"
      metric_name         = "BucketSizeBytes"
      dimensions          = { BucketName = b.bucket_name, StorageType = "StandardStorage" }
      statistic           = "Average"
      extended_statistic  = null
      queries             = []
    }
  ]

  nat_alarm_defs = flatten([
    for k, n in var.nat_gateways : [
      for az in(length(n.availability_zones) == 0 ? [null] : n.availability_zones) : [
        {
          key                 = "nat-${k}${az == null ? "" : "-${az}"}-error-port-allocation"
          preset              = "nat_gateways"
          cfg                 = n.alarms.error_port_allocation
          enabled             = n.alarms.error_port_allocation.enabled
          threshold           = n.alarms.error_port_allocation.threshold
          description         = "NAT gateway ${n.nat_gateway_id}${az == null ? "" : " (${az})"}: source port allocation failures (ErrorPortAllocation, Sum) above threshold."
          region              = n.region
          comparison_operator = "GreaterThanThreshold"
          treat_missing_data  = "notBreaching"
          namespace           = "AWS/NATGateway"
          metric_name         = "ErrorPortAllocation"
          dimensions          = merge({ NatGatewayId = n.nat_gateway_id }, az == null ? {} : { AvailabilityZone = az })
          statistic           = "Sum"
          extended_statistic  = null
          queries             = []
        },
        {
          key                 = "nat-${k}${az == null ? "" : "-${az}"}-packets-drop-rate"
          preset              = "nat_gateways"
          cfg                 = n.alarms.packets_drop_rate
          enabled             = n.alarms.packets_drop_rate.enabled
          threshold           = n.alarms.packets_drop_rate.threshold
          description         = "NAT gateway ${n.nat_gateway_id}${az == null ? "" : " (${az})"}: dropped packets % (100 * PacketsDropCount / (PacketsInFromSource + PacketsInFromDestination)) above threshold."
          region              = n.region
          comparison_operator = "GreaterThanThreshold"
          treat_missing_data  = "notBreaching"
          namespace           = null
          metric_name         = null
          dimensions          = {}
          statistic           = null
          extended_statistic  = null
          queries = [
            { id = "drops", expression = null, label = "PacketsDropCount", return_data = false, metric = { namespace = "AWS/NATGateway", metric_name = "PacketsDropCount", dimensions = merge({ NatGatewayId = n.nat_gateway_id }, az == null ? {} : { AvailabilityZone = az }), stat = "Sum" } },
            { id = "in_src", expression = null, label = "PacketsInFromSource", return_data = false, metric = { namespace = "AWS/NATGateway", metric_name = "PacketsInFromSource", dimensions = merge({ NatGatewayId = n.nat_gateway_id }, az == null ? {} : { AvailabilityZone = az }), stat = "Sum" } },
            { id = "in_dst", expression = null, label = "PacketsInFromDestination", return_data = false, metric = { namespace = "AWS/NATGateway", metric_name = "PacketsInFromDestination", dimensions = merge({ NatGatewayId = n.nat_gateway_id }, az == null ? {} : { AvailabilityZone = az }), stat = "Sum" } },
            { id = "packets", expression = "in_src + in_dst", label = "Packets in", return_data = false, metric = null },
            { id = "drop_rate", expression = "IF(packets > 0, 100 * drops / packets, 0)", label = "Dropped packets (%)", return_data = true, metric = null },
          ]
        },
      ]
    ]
  ])

  log_filter_alarm_defs = [
    for k, f in var.log_metric_filters : {
      key                 = "log-${k}"
      preset              = "log_metric_filters"
      cfg                 = { evaluation_periods = f.alarm.evaluation_periods, datapoints_to_alarm = f.alarm.datapoints_to_alarm, period = f.alarm.period, severity = f.alarm.severity }
      enabled             = f.alarm.enabled
      threshold           = f.alarm.threshold
      description         = coalesce(f.alarm.description, "Log metric filter ${k} on ${f.log_group_name}: ${coalesce(f.metric_name, k)} (${f.alarm.statistic}) crossed the threshold.")
      region              = f.region
      comparison_operator = f.alarm.comparison_operator
      treat_missing_data  = f.alarm.treat_missing_data
      namespace           = coalesce(f.namespace, local.log_metrics_namespace)
      metric_name         = coalesce(f.metric_name, k)
      dimensions          = {}
      statistic           = f.alarm.statistic
      extended_statistic  = null
      queries             = []
    }
  ]

  cis_alarm_defs = [
    for k, c in local.cis_filters : {
      key                 = k
      preset              = "cis_cloudtrail_metric_filters"
      cfg                 = { evaluation_periods = 1, datapoints_to_alarm = 1, period = 300, severity = var.cis_cloudtrail_metric_filters.severity }
      enabled             = true
      threshold           = 1
      description         = "CIS ${c.control}: ${c.title}."
      region              = var.cis_cloudtrail_metric_filters.region
      comparison_operator = "GreaterThanOrEqualToThreshold"
      treat_missing_data  = "notBreaching"
      namespace           = local.cis_namespace
      metric_name         = c.metric_name
      dimensions          = {}
      statistic           = "Sum"
      extended_statistic  = null
      queries             = []
    }
  ]
}
