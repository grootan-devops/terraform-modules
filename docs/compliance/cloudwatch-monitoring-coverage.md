# CloudWatch monitoring coverage

The [`cloudwatch-alarms`](../../modules/aws/observability/cloudwatch-alarms) module defines every CloudWatch alarm
for the resources the other modules create. The service modules build their preset in: each composes
`cloudwatch-alarms` behind its `alarms` input (on by default, `topic_arns` by severity, `overrides` per alarm), so the
alarms exist without wiring identifiers. ElastiCache Valkey is the exception: its alarms are keyed by member cluster
IDs that are only known after apply, so callers pass them to `cloudwatch-alarms` directly. Every metric, dimension,
default threshold and the AWS documentation page it was checked against is listed in the `cloudwatch-alarms` README
under *Architecture & Managed Resources*.

## Alarm routing

Alarms are created with actions off. Routing is opt-in: the
[`alarm-routing`](../../modules/aws/observability/alarm-routing) module creates KMS-encrypted SNS topics per severity
(`critical`, `warning`, `info`) in each Region that has alarms (CloudFront alarms live in us-east-1), with email and
HTTPS webhook subscriptions (for example a OneUptime incoming-request monitor). `topic_arns["<region>"]` goes into
each service module's `alarms.topic_arns`, and the whole `topic_arns` output into the `notifications` input of a
direct `cloudwatch-alarms` call; each alarm then notifies the topic for its Region and severity, and OK
notifications follow `notify_on_ok`. `tests/test_cloudwatch_alarms_contract.py` keeps the split: the alarms module
creates no destinations and only uses caller-supplied topic ARNs.

What routing changes in the findings, recorded in the [gaps page](compliance-gaps-and-remediation.md):

- Security Hub CloudWatch.15 (alarms have actions) and CloudWatch.17 (alarm actions activated) pass once routing is
  enabled.
- CIS CloudWatch.1 to CloudWatch.14 (log metric filter and alarm for root use, IAM policy changes, and similar) pass
  when `cis_cloudtrail_metric_filters.enabled = true`, routing is enabled, and the topic has a confirmed subscriber.
  Email addresses and webhooks must confirm the SNS subscription before they receive anything.

## Thresholds and metric math

Defaults are starting points; every threshold, period, evaluation window and statistic is a typed, overrideable
input. Percentages are derived with metric math, with a guard against a zero denominator, for example the Lambda
error rate `IF(invocations > 0, 100 * errors / invocations, 0)`, the API Gateway 5XX rate over `Count`, the ALB
target 5XX rate over `RequestCount` and the NAT gateway drop rate. RDS free storage is compared in bytes:
20 % of the configured allocation (`allocated_storage_gib * 1073741824 * 0.2`), which goes stale when storage
autoscaling grows the volume. Thresholds that only the application can know (SQS message age, WAF blocked requests,
S3 bucket size) have no default; those alarms are on once a threshold is set.

## Coverage of every resource type

Every resource type the AWS modules create, directly or through a building block.

Legend: **Built-in** - a preset the creating module turns on by default through its `alarms` input; **Preset** - a typed preset input of `cloudwatch-alarms`, wired by the caller; **CIS metric filter** - change detection by the CloudWatch.1-14 preset (off by default, CloudTrail log group required); **Generic `alarms` only** - possible with the generic input or `log_metric_filters`, no preset; **Alternative** - not a metric, needs events; **None** - nothing meaningful to alarm on.

| Resource type | Created by | Coverage | Metrics or alternative |
| --- | --- | --- | --- |
| `aws_accessanalyzer_analyzer` | `security/iam-access-analyzer` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_accessanalyzer_archive_rule` | `security/iam-access-analyzer` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_account_alternate_contact` | `governance/account-baseline` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_acm_certificate` | `security/acm` | Generic `alarms` only | `DaysToExpiry` (AWS/CertificateManager, CertificateArn); ACM renews DNS-validated certificates automatically |
| `aws_acm_certificate_validation` | `security/acm` | None | Validation step; no CloudWatch metric |
| `aws_amplify_app` | `storage/amplify` | Generic `alarms` only | No preset. `AWS/AmplifyHosting` namespace exists (CloudWatch namespace list); metrics not verified in this change |
| `aws_amplify_branch` | `storage/amplify` | Generic `alarms` only | Same as `aws_amplify_app` |
| `aws_amplify_domain_association` | `storage/amplify` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_api_gateway_account` | `governance/account-baseline` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_api_gateway_base_path_mapping` | `integration/api-gateway` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_api_gateway_deployment` | `integration/api-gateway` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_api_gateway_domain_name` | `integration/api-gateway` | None | Custom domain; certificate expiry belongs to ACM, which no module here creates |
| `aws_api_gateway_method_settings` | `integration/api-gateway` | None | Enables per-method detailed metrics (extra cost); per-method alarms possible via generic `alarms` with ApiName, Method, Resource, Stage |
| `aws_api_gateway_rest_api` | `integration/api-gateway` | Built-in | `api_gateways`: 5XX and 4XX rate % (math over Count), Latency p99, IntegrationLatency p99 (AWS/ApiGateway, ApiName + Stage) |
| `aws_api_gateway_stage` | `integration/api-gateway` | Built-in | Covered through `api_gateways` (Stage dimension) |
| `aws_apigatewayv2_api` | `integration/http-api` | Built-in | `http_apis`: 5xx rate % (math over Count), Latency p99 (AWS/ApiGateway, ApiId + Stage) |
| `aws_apigatewayv2_api_mapping` | `integration/http-api` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_apigatewayv2_authorizer` | `integration/http-api` | None | Authorizer failures show up in the API's 4xx and 5xx counts (`http_apis`) |
| `aws_apigatewayv2_domain_name` | `integration/http-api` | None | Custom domain; certificate expiry belongs to ACM (`DaysToExpiry` through generic `alarms`) |
| `aws_apigatewayv2_integration` | `integration/http-api` | Generic `alarms` only | IntegrationLatency (AWS/ApiGateway, ApiId + Stage); backend errors in the `http_apis` 5xx rate |
| `aws_apigatewayv2_route` | `integration/http-api` | Generic `alarms` only | Per-route metrics need `detailed_metrics` (ApiId, Stage, Method, Resource) |
| `aws_apigatewayv2_stage` | `integration/http-api` | Built-in | Covered through `http_apis` (Stage dimension, `$default`) |
| `aws_apigatewayv2_vpc_link` | `integration/http-api` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_appautoscaling_policy` | `compute/ecs`, `database/dynamodb` | None | Target-tracking policies own their alarms; scaling outcomes are visible through the ECS/DynamoDB presets |
| `aws_appautoscaling_target` | `compute/ecs`, `database/dynamodb` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_backup_framework` | `storage/backup` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_backup_global_settings` | `storage/backup` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_backup_plan` | `storage/backup` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_backup_region_settings` | `storage/backup` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_backup_report_plan` | `storage/backup` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_backup_selection` | `storage/backup` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_backup_vault` | `storage/backup` | Alternative | Failed backup and restore jobs go to SNS through `vault_notifications` |
| `aws_backup_vault_lock_configuration` | `storage/backup` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_backup_vault_notifications` | `storage/backup` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_backup_vault_policy` | `storage/backup` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_batch_compute_environment` | `compute/batch` | Preset | Partial: the ECS-managed Auto Scaling group can be passed to `auto_scaling_groups` (CPU, StatusCheckFailed). AWS Batch has no namespace in the CloudWatch namespace list |
| `aws_batch_job_definition` | `compute/batch` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_batch_job_queue` | `compute/batch` | Alternative | No CloudWatch metrics. Job failures surface as EventBridge job state-change events (not implemented here: the module creates no EventBridge rules by requirement) |
| `aws_batch_scheduling_policy` | `compute/batch` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_budgets_budget` | `governance/cost-guardrails` | Alternative | Actual and forecast alerts go to SNS and email through `notifications` |
| `aws_ce_anomaly_monitor` | `governance/cost-guardrails` | Alternative | Anomalies go to SNS (immediate) and email (daily) through the anomaly subscriptions |
| `aws_ce_anomaly_subscription` | `governance/cost-guardrails` | None | The notification channel for anomaly alerts |
| `aws_ce_cost_allocation_tag` | `governance/cost-guardrails` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_cloudfront_distribution` | `network/cloudfront` | Built-in | `cloudfront_distributions`: 5xxErrorRate, opt-in 4xxErrorRate and Requests (AWS/CloudFront, DistributionId + Region=Global, alarms in us-east-1) |
| `aws_cloudfront_origin_access_control` | `network/cloudfront` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_cloudtrail` | `security/cloudtrail` | CIS metric filter | `cis_cloudtrail_metric_filters` puts the CloudWatch.1-14 filters and alarms on the trail's log group |
| `aws_cloudtrail_organization_delegated_admin_account` | `security/cloudtrail` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_cloudwatch_event_archive` | `integration/eventbridge` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_cloudwatch_event_bus` | `integration/eventbridge` | Built-in | Partial: rule-level metrics via `eventbridge_rules` (EventBusName + RuleName); bus-level metrics (MatchedEvents, PutEvents*) only through generic `alarms` |
| `aws_cloudwatch_event_bus_policy` | `integration/eventbridge` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_cloudwatch_event_rule` | `integration/eventbridge` | Built-in | `eventbridge_rules`: FailedInvocations, ThrottledRules, InvocationsFailedToBeSentToDlq (AWS/Events). Batch's internal rule can be passed too |
| `aws_cloudwatch_event_target` | `integration/eventbridge` | Built-in | Covered through the rule's FailedInvocations / DLQ metrics in `eventbridge_rules` |
| `aws_cloudwatch_log_delivery` | `integration/eventbridge`, `network/cloudfront` | None | Vended log delivery; no alarm defined here |
| `aws_cloudwatch_log_delivery_destination` | `integration/eventbridge`, `network/cloudfront` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_cloudwatch_log_delivery_source` | `integration/eventbridge`, `network/cloudfront` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_cloudwatch_log_group` | `observability/log-group` (composed by 18 modules) | Generic `alarms` only | Content is alarmable through `log_metric_filters`; the CloudTrail log group through the CIS preset. Ingestion metrics live in `AWS/Logs` (generic `alarms`, not verified here) |
| `aws_cloudwatch_log_metric_filter` | `observability/cloudwatch-alarms` | Generic `alarms` only | The RDS module's PostgreSQL error/auth-failure filters publish metrics that generic `alarms` can target; this module does not reference them by name |
| `aws_cloudwatch_log_resource_policy` | `integration/eventbridge`, `network/route53` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_cloudwatch_metric_alarm` | `observability/cloudwatch-alarms` | — | The alarms themselves (`cloudwatch-alarms`) |
| `aws_cloudwatch_query_definition` | `database/rds/postgres` | None | Saved Logs Insights query; not a metric source |
| `aws_cognito_log_delivery_configuration` | `security/cognito` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_cognito_managed_login_branding` | `security/cognito` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_cognito_risk_configuration` | `security/cognito` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_cognito_user_group` | `security/cognito` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_cognito_user_pool` | `security/cognito` | Generic `alarms` only | No preset. `AWS/Cognito` namespace exists (CloudWatch namespace list); metrics not verified in this change |
| `aws_cognito_user_pool_client` | `security/cognito` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_cognito_user_pool_domain` | `security/cognito` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_config_config_rule` | `security/config` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_config_configuration_aggregator` | `security/config` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_config_configuration_recorder` | `security/config` | Alternative | Recorder status and rule compliance are reported by Security Hub (Config.1) |
| `aws_config_configuration_recorder_status` | `security/config` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_config_delivery_channel` | `security/config` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_config_organization_conformance_pack` | `security/config` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_config_organization_managed_rule` | `security/config` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_config_remediation_configuration` | `security/config` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_config_retention_configuration` | `security/config` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_db_event_subscription` | `database/rds/postgres` | Alternative | Sends RDS events to the caller's SNS topic |
| `aws_db_instance` | `database/rds/postgres` | Built-in | `rds_instances`: CPU, FreeStorageSpace < 20 %, Read/WriteLatency p99, opt-in FreeableMemory and DatabaseConnections (AWS/RDS, DBInstanceIdentifier) |
| `aws_db_instance_automated_backups_replication` | `database/rds/postgres` | None | No CloudWatch metric; replication failures appear as RDS events |
| `aws_db_parameter_group` | `database/rds/postgres` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_db_proxy` | `database/rds/proxy` | Built-in | `rds_proxies`: DatabaseConnectionsSetupFailed, ClientConnectionsSetupFailedAuth, borrowed / max connections %, opt-in ClientConnections (AWS/RDS, ProxyName) |
| `aws_db_proxy_default_target_group` | `database/rds/proxy` | None | AvailabilityPercentage needs TargetGroup + TargetRole dimension values the docs do not enumerate; not implemented |
| `aws_db_proxy_endpoint` | `database/rds/proxy` | Generic `alarms` only | Per-endpoint metrics (ProxyName + EndpointName) through generic `alarms` |
| `aws_db_proxy_target` | `database/rds/proxy` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_db_subnet_group` | `database/rds/postgres` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_default_network_acl` | `network/vpc` | CIS metric filter | CloudWatch.11 (NACL changes) when the CIS preset is enabled |
| `aws_default_route_table` | `network/vpc` | CIS metric filter | CloudWatch.13 (route table changes) |
| `aws_default_security_group` | `network/vpc` | CIS metric filter | CloudWatch.10 (security group changes) |
| `aws_detective_graph` | `security/detective` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_detective_member` | `security/detective` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_detective_organization_admin_account` | `security/detective` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_detective_organization_configuration` | `security/detective` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_dynamodb_contributor_insights` | `database/dynamodb` | None | Contributor Insights rules are not metric alarms; not covered |
| `aws_dynamodb_table` | `database/dynamodb` | Built-in | `dynamodb_tables`: Read/WriteThrottleEvents (table and GSIs), SystemErrors summed per Operation, opt-in consumed capacity (AWS/DynamoDB) |
| `aws_ebs_default_kms_key` | `governance/account-baseline` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_ebs_encryption_by_default` | `governance/account-baseline` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_ebs_snapshot_block_public_access` | `governance/account-baseline` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_ec2_image_block_public_access` | `governance/account-baseline` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_ec2_instance_metadata_defaults` | `governance/account-baseline` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_ec2_serial_console_access` | `governance/account-baseline` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_ecr_lifecycle_policy` | `compute/ecr` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_ecr_pull_through_cache_rule` | `governance/account-baseline` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_ecr_registry_scanning_configuration` | `governance/account-baseline` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_ecr_replication_configuration` | `governance/account-baseline` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_ecr_repository` | `compute/ecr` | None | No repository metrics worth an alarm; image findings go to Inspector and Security Hub |
| `aws_ecr_repository_policy` | `compute/ecr` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_ecs_cluster` | `compute/ecs` | Built-in | Through `ecs_services`; cluster-level CPU/MemoryReservation only via generic `alarms` |
| `aws_ecs_service` | `compute/ecs` | Built-in | `ecs_services`: CPUUtilization, MemoryUtilization (AWS/ECS); DesiredTaskCount - RunningTaskCount with Container Insights (ECS/ContainerInsights) |
| `aws_ecs_task_definition` | `compute/ecs` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_efs_access_point` | `storage/efs` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_efs_backup_policy` | `storage/efs` | None | Backup job outcomes belong to AWS Backup; not covered |
| `aws_efs_file_system` | `storage/efs` | Built-in | `efs_file_systems`: PercentIOLimit, BurstCreditBalance (bursting mode), opt-in ClientConnections (AWS/EFS, FileSystemId) |
| `aws_efs_file_system_policy` | `storage/efs` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_efs_mount_target` | `storage/efs` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_eip` | `network/vpc` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_eks_access_entry` | `compute/eks` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_eks_access_policy_association` | `compute/eks` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_eks_addon` | `compute/eks` | None | Add-on health is not a CloudWatch metric; not covered |
| `aws_eks_cluster` | `compute/eks` | Built-in | `eks_clusters` with `container_insights.enabled` (the `amazon-cloudwatch-observability` add-on, off by default): node_cpu_utilization, node_memory_utilization, cluster_failed_node_count (ContainerInsights, ClusterName) |
| `aws_eks_fargate_profile` | `compute/eks` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_eks_node_group` | `compute/eks` | Built-in | `auto_scaling_groups` on each node group's Auto Scaling group: CPUUtilization, StatusCheckFailed (AWS/EC2); node health also via `eks_clusters` failed nodes |
| `aws_eks_pod_identity_association` | `compute/eks` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_elasticache_parameter_group` | `database/elasticache/valkey` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_elasticache_replication_group` | `database/elasticache/valkey` | Preset | `elasticache_clusters` per member: CPUUtilization, EngineCPUUtilization, DatabaseMemoryUsagePercentage, Evictions, ReplicationLag, opt-in CurrConnections (AWS/ElastiCache) |
| `aws_elasticache_subnet_group` | `database/elasticache/valkey` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_flow_log` | `network/vpc` | Generic `alarms` only | Flow log content can feed `log_metric_filters`; delivery health not covered |
| `aws_guardduty_detector` | `security/guardduty` | Alternative | Findings flow to Security Hub; route them with EventBridge rules |
| `aws_guardduty_detector_feature` | `security/guardduty` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_guardduty_filter` | `security/guardduty` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_guardduty_organization_admin_account` | `security/guardduty` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_guardduty_organization_configuration` | `security/guardduty` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_guardduty_organization_configuration_feature` | `security/guardduty` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_guardduty_publishing_destination` | `security/guardduty` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_iam_account_password_policy` | `governance/account-baseline` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_iam_instance_profile` | `security/iam-role` (composed by 15 modules) | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_iam_organizations_features` | `governance/organizations` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_iam_role` | `security/iam-role` (composed by 15 modules) | CIS metric filter | CloudWatch.4 covers role policy attach/detach/put/delete; role creation itself is not in the CIS pattern |
| `aws_iam_role_policies_exclusive` | `security/iam-role` (composed by 15 modules) | CIS metric filter | CloudWatch.4 (PutRolePolicy / DeleteRolePolicy); out-of-band policies are also removed on the next apply |
| `aws_iam_role_policy` | `security/iam-role` (composed by 15 modules) | CIS metric filter | CloudWatch.4 (PutRolePolicy / DeleteRolePolicy) |
| `aws_iam_role_policy_attachment` | `security/iam-role` (composed by 15 modules) | CIS metric filter | CloudWatch.4 (AttachRolePolicy / DetachRolePolicy) |
| `aws_iam_role_policy_attachments_exclusive` | `security/iam-role` (composed by 15 modules) | CIS metric filter | CloudWatch.4 (AttachRolePolicy / DetachRolePolicy); out-of-band attachments are also removed on the next apply |
| `aws_iam_service_linked_role` | `security/config` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_identitystore_group` | `security/identity-center` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_identitystore_group_membership` | `security/identity-center` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_inspector2_delegated_admin_account` | `security/inspector` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_inspector2_enabler` | `security/inspector` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_inspector2_filter` | `security/inspector` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_inspector2_member_association` | `security/inspector` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_inspector2_organization_configuration` | `security/inspector` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_internet_gateway` | `network/vpc` | CIS metric filter | CloudWatch.12 (network gateway changes) |
| `aws_kms_alias` | `security/kms` (composed by 3 modules) | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_kms_key` | `security/kms` (composed by 3 modules) | CIS metric filter | CloudWatch.7 (DisableKey / ScheduleKeyDeletion). `AWS/KMS` namespace exists for generic `alarms`; not verified here |
| `aws_kms_replica_key` | `security/kms` (composed by 3 modules) | CIS metric filter | CloudWatch.7 in the replica Region if the trail log group covers it |
| `aws_lambda_alias` | `compute/lambda` | Generic `alarms` only | Alias-level metrics (Resource dimension) through generic `alarms`; presets use FunctionName |
| `aws_lambda_event_source_mapping` | `compute/lambda` | Built-in | IteratorAge via `lambda_functions` with event_source = stream; ESM metrics such as FailedInvokeEventCount need ESM metrics enabled and generic `alarms` |
| `aws_lambda_function` | `compute/lambda` | Built-in | `lambda_functions`: error rate % (math), Throttles, Duration p99, opt-in ConcurrentExecutions, IteratorAge for streams (AWS/Lambda, FunctionName) |
| `aws_lambda_function_event_invoke_config` | `compute/lambda` | Generic `alarms` only | Async delivery metrics (AsyncEventsDropped, DestinationDeliveryFailures) through generic `alarms` |
| `aws_lambda_function_recursion_config` | `compute/lambda` | Generic `alarms` only | RecursiveInvocationsDropped through generic `alarms` |
| `aws_lambda_function_url` | `compute/lambda` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_lambda_permission` | `compute/lambda`, `integration/api-gateway`, `integration/http-api` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_lambda_provisioned_concurrency_config` | `compute/lambda` | Generic `alarms` only | ProvisionedConcurrencySpilloverInvocations / Utilization through generic `alarms` |
| `aws_lambda_runtime_management_config` | `compute/lambda` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_launch_template` | `compute/batch`, `compute/eks` | None | Template only; instance metrics via `auto_scaling_groups` |
| `aws_lb` | `network/alb`, `network/nlb` | Built-in | `albs`: target 5XX rate % (math), HTTPCode_ELB_5XX_Count, TargetResponseTime p99, RejectedConnectionCount (AWS/ApplicationELB, LoadBalancer); NLB: `nlbs` per target group |
| `aws_lb_listener` | `network/alb`, `network/nlb` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_lb_listener_certificate` | `network/alb`, `network/nlb` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_lb_listener_rule` | `network/alb` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_lb_target_group` | `network/alb`, `network/nlb` | Built-in | `albs`: UnHealthyHostCount per target group (LoadBalancer + TargetGroup); NLB: `nlbs` UnHealthyHostCount and HealthyHostCount (AWS/NetworkELB) |
| `aws_lb_target_group_attachment` | `network/nlb` | Built-in | Covered through the target group's host counts (`nlbs`) |
| `aws_nat_gateway` | `network/vpc` | Built-in | `nat_gateways`: ErrorPortAllocation, packet drop rate % (AWS/NATGateway; per AZ for regional NAT gateways) |
| `aws_network_acl` | `network/vpc` | CIS metric filter | CloudWatch.11 |
| `aws_network_acl_association` | `network/vpc` | CIS metric filter | CloudWatch.11 (ReplaceNetworkAclAssociation) |
| `aws_network_acl_rule` | `network/vpc` | CIS metric filter | CloudWatch.11 (Create/Delete/ReplaceNetworkAclEntry) |
| `aws_organizations_aws_service_access` | `governance/organizations`, `governance/systems-manager`, `security/cloudtrail`, `security/config`, `security/guardduty`, `security/iam-access-analyzer`, `storage/backup` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_organizations_delegated_administrator` | `governance/organizations`, `governance/systems-manager`, `security/config`, `security/iam-access-analyzer`, `storage/backup` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_organizations_organization` | `governance/organizations` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_organizations_policy` | `governance/organizations` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_organizations_policy_attachment` | `governance/organizations` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_organizations_resource_policy` | `governance/organizations` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_route` | `network/vpc` | CIS metric filter | CloudWatch.13 |
| `aws_route53_health_check` | `network/route53` | Generic `alarms` only | `HealthCheckStatus` (AWS/Route53, HealthCheckId, us-east-1) |
| `aws_route53_hosted_zone_dnssec` | `network/route53` | Generic `alarms` only | Same as `aws_route53_key_signing_key` |
| `aws_route53_key_signing_key` | `network/route53` | Generic `alarms` only | `DNSSECInternalFailure`, `DNSSECKeySigningKeysNeedingAction` (AWS/Route53, HostedZoneId) |
| `aws_route53_query_log` | `network/route53` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_route53_record` | `network/route53`, `security/acm` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_route53_zone` | `network/route53` | None | DNS query logs go to the query log group; no zone-level metric worth an alarm |
| `aws_route_table` | `network/vpc` | CIS metric filter | CloudWatch.13 |
| `aws_route_table_association` | `network/vpc` | CIS metric filter | CloudWatch.13 (ReplaceRouteTableAssociation, DisassociateRouteTable; AssociateRouteTable is not in the CIS pattern) |
| `aws_s3_account_public_access_block` | `governance/account-baseline` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_s3_bucket` | `storage/s3` (composed by 4 modules) | Built-in | `s3_buckets`: BucketSizeBytes StandardStorage (daily). Bucket policy/ACL/CORS/lifecycle/replication changes via CloudWatch.8 |
| `aws_s3_bucket_cors_configuration` | `storage/s3` (composed by 4 modules) | CIS metric filter | CloudWatch.8 (PutBucketCors / DeleteBucketCors) |
| `aws_s3_bucket_lifecycle_configuration` | `storage/s3` (composed by 4 modules) | CIS metric filter | CloudWatch.8 (PutBucketLifecycle / DeleteBucketLifecycle) |
| `aws_s3_bucket_logging` | `storage/s3` (composed by 4 modules) | None | Not in a CIS pattern; not covered |
| `aws_s3_bucket_notification` | `storage/s3` (composed by 4 modules) | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_s3_bucket_object_lock_configuration` | `storage/s3` (composed by 4 modules) | None | Not in a CIS pattern; not covered |
| `aws_s3_bucket_ownership_controls` | `storage/s3` (composed by 4 modules) | None | Not in a CIS pattern; not covered |
| `aws_s3_bucket_policy` | `storage/s3` (composed by 4 modules) | CIS metric filter | CloudWatch.8 (PutBucketPolicy / DeleteBucketPolicy) |
| `aws_s3_bucket_public_access_block` | `storage/s3` (composed by 4 modules) | None | Not in a CIS pattern; not covered |
| `aws_s3_bucket_replication_configuration` | `storage/s3` (composed by 4 modules) | CIS metric filter | CloudWatch.8 (PutBucketReplication / DeleteBucketReplication); replication failure metrics need S3 replication metrics and generic `alarms` |
| `aws_s3_bucket_server_side_encryption_configuration` | `storage/s3` (composed by 4 modules) | None | Not in a CIS pattern; not covered |
| `aws_s3_bucket_versioning` | `storage/s3` (composed by 4 modules) | None | Not in a CIS pattern; not covered |
| `aws_scheduler_schedule` | `integration/eventbridge` | Built-in | `schedule_groups`: TargetErrorCount, InvocationDroppedCount, InvocationsFailedToBeSentToDeadLetterCount (AWS/Scheduler, ScheduleGroup) |
| `aws_scheduler_schedule_group` | `integration/eventbridge` | Built-in | Covered through `schedule_groups` (ScheduleGroup dimension) |
| `aws_secretsmanager_secret` | `security/secrets-manager` | Generic `alarms` only | No preset. `AWS/SecretsManager` namespace exists; rotation failures are CloudTrail/EventBridge events (not implemented) |
| `aws_secretsmanager_secret_policy` | `security/secrets-manager` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_secretsmanager_secret_rotation` | `security/secrets-manager` | Alternative | Rotation failure is an event, not a metric; would need a CloudTrail metric filter (`log_metric_filters`) or EventBridge (not implemented) |
| `aws_secretsmanager_secret_version` | `security/secrets-manager` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_security_group` | `network/security-group` (composed by 12 modules) | CIS metric filter | CloudWatch.10 |
| `aws_securityhub_account` | `security/security-hub` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_securityhub_configuration_policy` | `security/security-hub` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_securityhub_configuration_policy_association` | `security/security-hub` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_securityhub_finding_aggregator` | `security/security-hub` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_securityhub_organization_admin_account` | `security/security-hub` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_securityhub_organization_configuration` | `security/security-hub` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_securityhub_product_subscription` | `security/security-hub` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_service_discovery_private_dns_namespace` | `compute/ecs` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_service_discovery_service` | `compute/ecs` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_sesv2_email_identity_policy` | `security/cognito` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_sfn_state_machine` | `integration/step-functions` | Built-in | `step_functions`: ExecutionsFailed, ExecutionsTimedOut, ExecutionsAborted, ExecutionThrottled (AWS/States, StateMachineArn) |
| `aws_sns_topic` | `observability/alarm-routing` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_sns_topic_policy` | `observability/alarm-routing` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_sns_topic_subscription` | `observability/alarm-routing` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_sqs_queue` | `integration/sqs` | Built-in | `sqs_queues`: ApproximateAgeOfOldestMessage (threshold required), opt-in ApproximateNumberOfMessagesVisible, DLQ ApproximateNumberOfMessagesVisible > 0 (AWS/SQS, QueueName) |
| `aws_sqs_queue_policy` | `integration/sqs` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_sqs_queue_redrive_allow_policy` | `integration/sqs` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_sqs_queue_redrive_policy` | `integration/sqs` | Built-in | Its DLQ via `sqs_queues` dlq_name |
| `aws_ssm_association` | `governance/systems-manager` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_ssm_document` | `governance/systems-manager` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_ssm_patch_baseline` | `governance/systems-manager` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_ssm_resource_data_sync` | `governance/systems-manager` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_ssm_service_setting` | `governance/systems-manager` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_ssmquicksetup_configuration_manager` | `governance/systems-manager` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_ssoadmin_account_assignment` | `security/identity-center` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_ssoadmin_customer_managed_policy_attachment` | `security/identity-center` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_ssoadmin_customer_managed_policy_attachments_exclusive` | `security/identity-center` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_ssoadmin_managed_policy_attachment` | `security/identity-center` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_ssoadmin_managed_policy_attachments_exclusive` | `security/identity-center` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_ssoadmin_permission_set` | `security/identity-center` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_ssoadmin_permission_set_inline_policy` | `security/identity-center` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_ssoadmin_permissions_boundary_attachment` | `security/identity-center` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_subnet` | `network/vpc` | None | Subnet changes are not in a CIS pattern; IP exhaustion is not a CloudWatch metric here |
| `aws_vpc` | `network/vpc` | CIS metric filter | CloudWatch.14 (VPC changes) |
| `aws_vpc_block_public_access_options` | `governance/account-baseline` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_vpc_dhcp_options` | `network/vpc` | None | Not in a CIS pattern; not covered |
| `aws_vpc_dhcp_options_association` | `network/vpc` | None | Not in a CIS pattern; not covered |
| `aws_vpc_endpoint` | `network/vpc` | Generic `alarms` only | Interface endpoints publish `AWS/PrivateLinkEndpoints` metrics (generic `alarms`; not verified here); gateway endpoints none |
| `aws_vpc_endpoint_service` | `network/nlb` | Generic `alarms` only | `AWS/PrivateLinkServices` metrics by service; no preset |
| `aws_vpc_security_group_egress_rule` | `network/security-group` (composed by 12 modules) | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_vpc_security_group_ingress_rule` | `network/security-group` (composed by 12 modules) | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_vpc_security_group_rules_exclusive` | `network/security-group` (composed by 12 modules) | CIS metric filter | CloudWatch.10 (security group changes); out-of-band rules are also removed on the next apply |
| `aws_wafv2_ip_set` | `network/waf` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_wafv2_regex_pattern_set` | `network/waf` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_wafv2_web_acl` | `network/waf` | Built-in | `waf_web_acls`: BlockedRequests spike (AWS/WAFV2, WebACL metric name + Rule [+ Region]) |
| `aws_wafv2_web_acl_association` | `integration/api-gateway`, `network/alb` | None | Configuration object with no CloudWatch metrics; nothing to alarm on |
| `aws_wafv2_web_acl_logging_configuration` | `network/waf` | Generic `alarms` only | WAF log content can feed `log_metric_filters` |

Totals: Alternative: 8, CIS metric filter: 25, Generic `alarms` only: 21, None: 169, Preset: 31, —: 1 (255 resource types).

Modules added by other 3.0.0 tasks (`security/cloudtrail`, `security/config`, `security/security-hub`, `security/inspector`, `security/iam-access-analyzer`, `governance/organizations`) are outside this table; their CloudTrail log group is the input for the CIS preset.

[Compliance documentation](README.md)
