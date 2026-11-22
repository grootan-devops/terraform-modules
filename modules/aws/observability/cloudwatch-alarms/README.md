# AWS CloudWatch Alarms Module

Scope: `workload`

CloudWatch metric alarms and CloudWatch Logs metric filters for the resources the other modules create. Presets take
names and IDs (function names, ARN suffixes, queue names, DB identifiers) and expand into alarms with documented AWS
metrics and overridable thresholds; the CIS CloudWatch.1-14 metric filters are one switch. Alarms are detective-only by
default: actions stay off until `notifications.enabled` routes them to the SNS topics of
[`alarm-routing`](../alarm-routing). The module never creates a notification destination.

The AWS service modules build these presets in: each composes this module behind its `alarms` input
(`enabled`, `topic_arns` by severity, `overrides` per alarm), so a caller gets the alarms below without wiring IDs.
Call this module directly for custom alarms, log metric filters, the CIS filters, alarms across modules and
ElastiCache Valkey, whose member cluster IDs are only known after apply.

## Architecture & Managed Resources

- `aws_cloudwatch_metric_alarm.this`: one per enabled generic alarm, preset alarm, log metric filter and CIS filter,
  keyed `<preset>-<resource key>-<alarm>` (for example `lambda-orders-error-rate`) and named
  `<application>-<environment>[-<name>]-<key>`, cut to 255 characters with a 6-character hash.
- `aws_cloudwatch_log_metric_filter.this`: `log_metric_filters`, publishing to `<application>-<environment>[-<name>]/LogMetrics`.
- `aws_cloudwatch_log_metric_filter.cis`: the 14 CIS filters on the CloudTrail log group.
- `module.naming` ([`core/naming`](../../core/naming)): base name, tags and provider Region.

`cache_cluster_ids` names the alarms, so it must be known at plan: wire `module.valkey.member_clusters` once the cache
exists, or pass `"${module.valkey.id}-001"`-style IDs on the first apply. Every entry accepts `region`
(resource-level `region` argument). CloudFront and CLOUDFRONT-scope WAF alarms are always
created in `us-east-1`, the only Region with CloudFront metrics. Each preset entry has an `alarms` object with
`{ enabled, threshold, evaluation_periods, datapoints_to_alarm, period, severity }` per alarm; a field set to null
takes the preset default, and opt-in alarms need a threshold when enabled. Alarms with no default threshold (SQS
message age, WAF blocked requests, S3 bucket size) are on once a threshold is set. Rate alarms use `IF(denominator > 0, 100 * numerator / denominator, 0)`.

| Input | Alarms (key suffixes) |
| --- | --- |
| `lambda_functions` | `error-rate`, `throttles`, `duration-p99` (80 % of `timeout_seconds`), `concurrent-executions` (opt-in), `iterator-age` (streams) |
| `api_gateways` | `5xx-rate`, `4xx-rate`, `latency-p99`, `integration-latency-p99` |
| `albs` | `target-5xx-rate`, `elb-5xx-count`, `target-response-time-p99`, `rejected-connections`, `<target group>-unhealthy-hosts` |
| `nlbs` | `<target group>-unhealthy-hosts`, `<target group>-no-healthy-hosts` |
| `http_apis` | `5xx-rate`, `latency-p99` |
| `ecs_services` | `cpu`, `memory`, `running-tasks` (Container Insights) |
| `eks_clusters` | `node-cpu`, `node-memory`, `failed-nodes` (Container Insights only) |
| `auto_scaling_groups` | `cpu`, `status-check-failed` |
| `rds_instances` | `cpu`, `free-storage` (20 % of `allocated_storage_gib`), `read-latency-p99`, `write-latency-p99`, `freeable-memory` and `connections` (opt-in) |
| `rds_proxies` | `connection-setup-failures`, `client-auth-failures`, `borrowed-connections`, `client-connections` (opt-in) |
| `dynamodb_tables` | `read-throttles`, `write-throttles` (table and each GSI), `system-errors`, `consumed-rcu`/`consumed-wcu` (opt-in) |
| `elasticache_clusters` | per member: `cpu`, `engine-cpu`, `memory`, `evictions`, `replication-lag`, `curr-connections` (opt-in) |
| `sqs_queues` | `age-of-oldest-message` (on with a threshold), `dlq-messages-visible`, `messages-visible` (opt-in) |
| `eventbridge_rules` | `failed-invocations`, `throttled-rules`, `dlq-send-failures` |
| `schedule_groups` | `target-errors`, `invocations-dropped`, `dlq-send-failures` |
| `step_functions` | `executions-failed`, `executions-timed-out`, `executions-aborted`, `execution-throttled` |
| `cloudfront_distributions` | `5xx-error-rate`, `4xx-error-rate` and `requests` (opt-in) |
| `efs_file_systems` | `percent-io-limit` (`generalPurpose`), `burst-credit-balance` (bursting), `client-connections` (opt-in) |
| `waf_web_acls` | `blocked-requests` (on with a threshold) |
| `s3_buckets` | `bucket-size` (on with a threshold) |
| `nat_gateways` | `error-port-allocation`, `packets-drop-rate` (per AZ for regional gateways) |

Severity picks the topic: errors, unhealthy capacity, dead-letter queues and CIS alarms are `critical`; latency,
saturation, throttling, generic and log alarms are `warning`; capacity planning (consumed capacity, CloudFront requests,
S3 size) is `info`. Thresholds follow the CloudWatch
[recommended alarms](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Best_Practice_Recommended_Alarms_AWS_Services.html)
where AWS lists one.

## Security & Compliance Guardrails

- **Actions only through `notifications`:** `actions_enabled = var.notifications.enabled`; the action lists are empty
  unless it is on, and the only value is the caller's topic for the alarm's Region and severity
  (`tests/test_cloudwatch_alarms_contract.py`). A precondition fails an enabled alarm with no topic.
- **CIS CloudWatch.1-14:** patterns copied verbatim from the Security Hub remediation; Sum >= 1 over 300 s. The preset
  requires `notifications.enabled`, because the controls pass only when the alarm has a subscribed topic.
- **CloudWatch.15, CloudWatch.17:** routed alarms have an ALARM action and actions enabled.
- **Validated inputs:** static comparison operators, one metric form per alarm, one returned query, ARN suffixes (not
  ARNs), required workload-specific thresholds.
- **Tags:** governance tags on every alarm; metric filters have no tags.

## Requirements & Providers

| Requirement | Version |
| --- | --- |
| `terraform` | `>= 1.17.0` |
| `aws` | `>= 6.73.0` |

## Usage Examples

### Minimal Working Example

```hcl
module "alarms" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/observability/cloudwatch-alarms?ref=<version>"

  application = "core"
  environment = "prod"

  lambda_functions = {
    orders = { function_name = module.lambda.name, timeout_seconds = 30 }
  }
}
```

### Complete Production Example

```hcl
module "alarms" {
  source = "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/observability/cloudwatch-alarms?ref=<version>"

  application = "core"
  environment = "prod"

  lambda_functions = {
    orders = { function_name = module.lambda.name, timeout_seconds = 30 }
  }
  albs = {
    web = {
      load_balancer_arn_suffix = module.alb.arn_suffix
      target_groups            = { api = module.alb.target_group_arn_suffixes["api"] }
    }
  }
  sqs_queues = {
    jobs = { queue_name = module.queue.name, dlq_name = module.queue.dlq_name, alarms = { age_of_oldest_message = { threshold = 300 } } }
  }
  rds_instances = {
    main = { db_instance_identifier = module.postgres.id, allocated_storage_gib = 100 }
  }
  rds_proxies = {
    main = { proxy_name = module.proxy.name }
  }
  dynamodb_tables = {
    orders = { table_name = module.orders_table.name }
  }
  elasticache_clusters = {
    sessions = { replication_group_id = module.valkey.id, cache_cluster_ids = module.valkey.member_clusters }
  }
  cloudfront_distributions = {
    site = { distribution_id = module.cdn.id }
  }
  cis_cloudtrail_metric_filters = {
    enabled        = true
    log_group_name = module.cloudtrail.log_group_name
  }

  notifications = {
    enabled    = true
    topic_arns = module.alarm_routing.topic_arns
  }
}
```

## Inputs Specification

| Name | Description | Type | Default | Required |
| --- | --- | --- | --- | --- |
| `application` | Application name. | `string` | **Required** | Yes |
| `environment` | Environment name. | `string` | **Required** | Yes |
| `name` | Instance name. | `string` | `null` | No |
| `tags` | Extra tags; governance tags win. | `map(string)` | `{}` | No |
| `notifications` | Alarm actions: off by default; topic ARN by Region and severity. | `object({...})` | `{}` | No |
| `alarms` | Generic metric or metric-math alarms by key. | `map(object({...}))` | `{}` | No |
| `lambda_functions` | Lambda functions by key: function name and timeout. | `map(object({...}))` | `{}` | No |
| `api_gateways` | REST API stages by key: API name and stage. | `map(object({...}))` | `{}` | No |
| `albs` | Application Load Balancers by key: ARN suffixes. | `map(object({...}))` | `{}` | No |
| `nlbs` | Network Load Balancers by key: ARN suffixes. | `map(object({...}))` | `{}` | No |
| `http_apis` | HTTP APIs by key: API ID and stage. | `map(object({...}))` | `{}` | No |
| `schedule_groups` | EventBridge Scheduler schedule groups by key: group name. | `map(object({...}))` | `{}` | No |
| `ecs_services` | ECS services by key: cluster and service names. | `map(object({...}))` | `{}` | No |
| `eks_clusters` | EKS clusters by key: Container Insights alarms. | `map(object({...}))` | `{}` | No |
| `auto_scaling_groups` | Auto Scaling groups by key. | `map(object({...}))` | `{}` | No |
| `rds_instances` | RDS DB instances by key: identifier and storage. | `map(object({...}))` | `{}` | No |
| `rds_proxies` | RDS Proxies by key. | `map(object({...}))` | `{}` | No |
| `dynamodb_tables` | DynamoDB tables by key: table and index names. | `map(object({...}))` | `{}` | No |
| `elasticache_clusters` | Valkey or Redis OSS replication groups by key: member clusters. | `map(object({...}))` | `{}` | No |
| `sqs_queues` | SQS queues by key: queue and dead-letter queue names. | `map(object({...}))` | `{}` | No |
| `eventbridge_rules` | EventBridge rules by key: rule and bus names. | `map(object({...}))` | `{}` | No |
| `step_functions` | Step Functions state machines by key. | `map(object({...}))` | `{}` | No |
| `cloudfront_distributions` | CloudFront distributions by key; alarms in us-east-1. | `map(object({...}))` | `{}` | No |
| `efs_file_systems` | EFS file systems by key: ID and modes. | `map(object({...}))` | `{}` | No |
| `waf_web_acls` | WAF web ACLs by key: metric names and scope. | `map(object({...}))` | `{}` | No |
| `s3_buckets` | S3 buckets by key: bucket name and size threshold. | `map(object({...}))` | `{}` | No |
| `nat_gateways` | NAT gateways by key. | `map(object({...}))` | `{}` | No |
| `log_metric_filters` | Log metric filters by key, each with an alarm. | `map(object({...}))` | `{}` | No |
| `cis_cloudtrail_metric_filters` | CIS CloudWatch.1-14 metric filters and alarms on the CloudTrail log group. | `object({...})` | `{}` | No |

## Outputs Specification

| Name | Description | Sensitive |
| --- | --- | --- |
| `alarm_arns` | Alarm ARN by key. | No |
| `alarm_names` | Alarm name by key. | No |
| `metric_filter_names` | Metric filter name by key. | No |
| `presets` | Alarm keys created by each input. | No |
| `alarm_routes` | Region, severity and topic ARN by alarm key. | No |
| `alarm_settings` | Threshold, periods and datapoints by alarm key. | No |
