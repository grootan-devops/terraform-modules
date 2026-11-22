# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.0.0] - 2026-11-20

### Added

- One standard for every AWS module (`docs/module-contract.md`): the same identity, `kms`, `security_group`, `iam_role`, `cloudwatch_logs` and `policy_statements` inputs, collision-free names, a declared scope (workload, account, organization) and a plan-time safety rule; enforced by `tests/verify_modules.py`.
- `docs/organizations-governance.md`: the account model, policy types, delegated administrators, read-only checks, rollout order and break-glass for an AWS organization.
- `examples/aws/`: cross-module scenarios planned under mocks that together call every AWS module (`static-site` is new); `examples/oneuptime/platform`: every OneUptime area in one inventory.
- `modules/aws/core/naming`, `core/encryption`, `core/policy-document`: shared helpers for names, governance tags, the three encryption modes and policy documents.
- `modules/aws/security/iam-role`: IAM role with trust conditions, inline policy, managed policies, permissions boundary and optional instance profile.
- `modules/aws/network/security-group`: security group with one rule resource per source; no open ingress, no default egress; `self = true` on a rule references the group itself.
- `modules/aws/observability/log-group`: CloudWatch log group with 365-day retention, deletion protection and optional KMS key.
- `modules/aws/compute/lambda`: event source mappings for SQS, Kinesis and DynamoDB streams, `allowed_triggers`, IAM-auth function URL, VPC security group, three encryption modes.
- `modules/aws/compute/ecr`: private repository with immutable tags, scan on push, AES256 or KMS encryption, a lifecycle policy (keep the last tagged images, expire untagged ones) and a repository policy from typed statements plus cross-account pull principals.
- `modules/aws/compute/eks`: access entries with access policy associations, EKS Pod Identity associations for workloads (your role or one built from statements), Fargate profiles, a control plane security group for API access, and add-on Pod Identity roles bound through the add-ons.
- `modules/aws/compute/ecs`: per-service `task_role`, `writable_paths`, `target_group_arns`, `autoscaling` (CPU and memory), `service_connect`, `tracing` and an ARM64 option; Fargate ephemeral storage encrypted with the module key; `efs_volumes` on each service mounts EFS with TLS, IAM authorization through an access point and mount permissions on the task role.
- `modules/aws/compute/batch`: EC2 and Spot compute environments with an IMDSv2 launch template, encrypted root volumes and an instance profile; typed container job definitions with secrets, user, scratch volumes, retries and timeouts; `efs_volumes` on each job definition mounts EFS the same way, with NFS egress to the VPC.
- `modules/aws/database/dynamodb`: `kms` modes (AWS managed key by default), autoscaling of global secondary indexes, `witness_region`, Contributor Insights on listed indexes, outputs `id`, `name`, `stream_arn`, `global_secondary_index_names` and `kms_key_arn`.
- `modules/aws/database/elasticache/valkey`: `kms` modes, `security_group` with ingress from security groups, CIDRs and prefix lists, slow and engine logs on by default, outputs `id`, `arn`, `port` and `kms_key_arn`.
- `modules/aws/database/rds/postgres`: `kms` modes, `backup_replication` through the resource `region` argument, `event_subscription` for instance and parameter group events (RDS.20, RDS.21), `iam_role` for the Enhanced Monitoring role, outputs `endpoint`, `security_group_id`, `monitoring_role_arn` and `kms_key_arn`; `extended_support` (default `false`) sets `engine_lifecycle_support`, so instances are not enrolled in paid RDS Extended Support; `allow_major_version_upgrade` and `apply_immediately` for a major version upgrade.
- `modules/aws/database/rds/proxy`: `target` with the database port and security groups, `iam_role`, `connection_pool` defaults, outputs `id`, `role_arn`, `role_name` and `endpoints`; outputs `port`, `resource_id` and `db_user_arn_prefix` for `rds-db:connect`.
- `modules/aws/network/route53`: public or private hosted zone with standard and alias records, failover records with tagged health checks, DNS query logging for public zones (us-east-1 log group and a resource policy scoped to the zone) and DNSSEC signing with a us-east-1 `ECC_NIST_P256` key, on by default for public zones; outputs `zone_id`, `name`, `arn`, `name_servers`, `ds_record`.
- `modules/aws/security/acm`: DNS-validated ACM certificate with `subject_alternative_names`, `key_algorithm`, validation records in a Route 53 zone, `aws_acm_certificate_validation` and a `region` input for us-east-1 CloudFront certificates; outputs `arn`, `domain_name`, `validation_record_fqdns`, `status`, `validation_records`.
- `modules/aws/network/vpc`: subnets computed from `cidr_block` and `az_count` (default 3) or `azs`, with optional CIDR lists per tier; `routes` for transit gateway and peering targets; `vpc_endpoints` for any interface or gateway endpoint with typed `policy_statements`; flow logs to S3 (`flow_logs.destination = "s3"`); `kms` modes and `iam_role` for the flow log role; outputs `vpc_arn`, `azs`, `*_subnet_ids`, `*_subnet_cidrs`, `*_route_table_ids`, `nat_public_ips`, `vpc_endpoint_ids`, `vpc_endpoint_security_group_id`.
- `modules/aws/network/alb`: `target_groups`, `default_target_group` and `listener_rules` (path and host conditions); extra SNI certificates through `https_listener.additional_certificate_arns`; connection logs with `access_logs`; outputs `id`, `arn`, `arn_suffix`, `name`, `dns_name`, `zone_id`, `https_listener_arn`, `http_listener_arn`, `target_group_arns`, `target_group_arn_suffixes`.
- `modules/aws/network/cloudfront`: `waf` object, Lambda function URL origins with origin access control, `ordered_cache_behaviors` and policies given as `Managed-*` names or IDs, `price_class`, `kms` modes for the us-east-1 log group; the default CloudFront certificate when `aliases` is empty; `logging` sends access logs to CloudWatch Logs (default) or an S3 bucket (`s3_bucket_arn`, `prefix`), `kms` only with CloudWatch Logs.
- `modules/aws/network/waf`: `scope = "CLOUDFRONT"` creates everything in us-east-1; `challenge` action on rate limits; `kms` modes for the log group; outputs `id`, `arn`, `name`, `metric_name`, `rule_metric_names`; `logging` sends logs to CloudWatch Logs (default) or an `aws-waf-logs-` S3 bucket (`s3_bucket_arn`), `kms` only with CloudWatch Logs.
- `modules/aws/integration/api-gateway`: `kms` for the log groups, `waf = { enabled, web_acl_arn }`, `tls` (security policy on the API endpoint as well as the domain), `lambda = { invoke_arn, alias_arn }` on routes and Lambda authorizers, outputs `id`, `arn`, `name`, `regional_domain_name`, `regional_zone_id`, `log_group_arn`, `kms_key_arn`.
- `modules/aws/integration/eventbridge`: `targets` input keyed by rule key, then target key (separate from `rules`, so a target may refer back to `rule_arns`), with typed targets (`lambda`, `sqs`, `step_functions`, `batch`, `ecs`, `kinesis`, `api_destination`), one target role with only the actions those targets need, per-target dead-letter queue and retry policy, `archive`, `policy_statements`, three encryption modes, outputs `rule_arns`, `rule_bus_names`, `role_arn`, `role_name`, `log_group_arn`, `kms_key_arn`; `scheduler = { enabled, schedules }` for EventBridge Scheduler: one tagged schedule group and schedules by key (`cron()`, `rate()` or `at()`, `UTC` by default, optional flexible window, start and end dates, `action_after_completion`) whose `target` has the rule target shape, for `lambda`, `sqs`, `step_functions`, `ecs`, `kinesis`, `batch` (through the `aws-sdk:batch:submitJob` universal target) and `event_bus` (defaults to the module bus); schedule payloads use the module key when one is set; an `event_bus` target type for rules; `sqs.kms_key_arn`, `dead_letter_queue.kms_key_arn`, `kinesis.partition_key` and `event_bus = { detail_type, source }` for schedules; outputs `schedule_group_name`, `schedule_group_arn`, `schedule_arns`.
- `modules/aws/integration/sqs`: `allowed_publishers` for EventBridge, SNS and S3 (`sqs:SendMessage` with `aws:SourceArn`), typed `policy_statements`, `fifo` object with high throughput, three encryption modes, outputs `id`, `arn`, `name`, `url`, `kms_key_arn`; `dead_letter_queue.allowed_publishers` for EventBridge rules and SNS topics that use the DLQ as their own dead-letter queue.
- `modules/aws/integration/step-functions`: `iam_role` to extend or bring the execution role, `tracing`, three encryption modes, outputs `role_name`, `log_group_arn`, `kms_key_arn`.
- `modules/aws/storage/log-bucket`: new S3 log bucket on `storage/s3` with SSE-S3, 365-day expiry, and bucket policy statements per log type: S3 server access logs, ELB logs (service principal and the documented legacy ELB account) and vended logs from `delivery.logs.amazonaws.com`, scoped with `aws:SourceAccount`, `aws:SourceArn` and `source_account_ids`.
- `modules/aws/storage/s3`: `kms` modes, `bucket_name`, typed `lifecycle_rules` and `noncurrent_version_expiration`, `access_logs`, `notifications` (EventBridge, SNS, SQS, Lambda), `object_lock`, `replication` with its role from `security/iam-role`, typed `policy_statements`, outputs `id`, `domain_name`, `regional_domain_name`, `kms_key_arn`, `replication_role_arn` and `policy_json`.
- `modules/aws/storage/efs`: `kms` modes, `security_group` on `network/security-group`, `client_access`, typed `policy_statements`, `throughput` and `lifecycle_policy` objects, outputs `name`, `access_point_ids`, `access_point_arns` and `kms_key_arn`.
- `modules/aws/storage/amplify`: `description`, branch `stage`, `framework` and `auto_build`, domain `wait_for_verification`, outputs `name`, `branch_names` and `domain_dns_records`; `domain_dns_records` entries are `{ name, type, value }` objects ready for Route 53.
- `modules/aws/security/cognito`: `kms` modes, `deletion_protection`, `threat_protection`, `web_authn`, `self_sign_up`, `verification_message`, `custom_attributes`, `domain` (derived prefix or custom domain), `cloudwatch_logs` on `observability/log-group`, outputs `name`, `domain_dns_name`, `domain_zone_id`, `log_group_name`, `log_group_arn` and `kms_key_arn`; one Cognito default managed login style (`aws_cognito_managed_login_branding`) per app client while the domain serves managed login, so API-created clients get working login pages; `clients[*].refresh_token_rotation = { enabled, retry_grace_period_seconds }` (off by default, grace 0-60 seconds, ESSENTIALS or PLUS, not with `ALLOW_REFRESH_TOKEN_AUTH`); validations for managed login version 2 on LITE and the `email.ses_identity_arn` format.
- `modules/aws/security/secrets-manager`: `kms` modes with a multi-Region module key for replicas, `replica_regions` with per-Region keys, `rotation`, typed `policy_statements`, output `kms_key_arn`.
- `modules/aws/security/cloudtrail`: module-owned KMS key by default (`kms`, CloudTrail has no AWS managed key), up to three delegated administrators (`organization_admin.account_ids`), typed `bucket.policy_statements` and an extensible or caller-supplied delivery role (`iam_role`).
- `modules/aws/security/config`: standard `kms` input (SSE-S3 by default, module key with the AWS Config grants, or your key), `organization_admin.manage_trusted_access`, SSE-C blocked on the delivery bucket, and a member-account check on the delegated administrator.
- `modules/aws/security/security-hub`: `tags` input (passed to `core/naming`, governance tags last; no Security Hub CSPM resource accepts tags yet); `standards` map over the defaults; account-only mode (`organization_configuration.enabled = false`) subscribes them in the home Region and every Region of `regions`.
- `modules/aws/security/guardduty`: standard `kms` input for the findings export (`kms.create` builds a key that grants only GuardDuty in this account), `publishing_destination.policies_only` to output the bucket and key policies before the export exists; account-only mode (`organization_configuration.enabled = false`): detectors, plans, filters and export without the organization configuration.
- `modules/aws/security/inspector`: validations for member account IDs, filter actions and filter comparisons; `scan_types`; account-only mode (`organization_configuration.enabled = false`) activates them for this account, with its own suppression rules.
- `modules/aws/security/detective`: account-only mode (`organization_configuration.enabled = false`): one behavior graph, listed members invited instead of enabled.
- `modules/aws/security/iam-access-analyzer`: account-only mode (`organization_configuration.enabled = false`): `ACCOUNT`, `ACCOUNT_UNUSED_ACCESS` and `ACCOUNT_INTERNAL_ACCESS` analyzers with the same settings and archive rules.
- `tests/verify_modules.py` fails when two modules give `security/iam-role` the same `purpose`, so two modules with the same `name` in one environment never share a role name.
- `modules/aws/storage/backup`: `regions` list (vault, plan, selection, framework, report plan, notifications and Region settings per Region), `kms` input (AWS managed `aws/backup` key by default, a module key per Region, or your key), `deletion_protection`, per-Region notification topics, and outputs by Region.
- `modules/aws/security/identity-center`: permission sets (AWS managed, customer managed and inline policies, permissions boundary, one-hour sessions by default), account assignments to groups or users, optional identity store groups and memberships; the instance is discovered.
- `modules/aws/governance/account-baseline`: per-Region EC2 instance metadata defaults (IMDSv2, hop limit 2), EBS snapshot and AMI block public access, serial console access off, optional VPC block public access, the API Gateway CloudWatch Logs role, ECR enhanced registry scanning, optional ECR replication and pull through cache rules; outputs `api_gateway_role_arn` and `api_gateway_role_name`.
- `modules/aws/governance/systems-manager`: `kms` input (AWS managed encryption, a module key per Region, or your key; an `mrk-` key ID for several Regions), `cloudwatch_logs` settings, `session_manager.s3_logs` and `inventory_bucket.access_logs` switches, `kms_key_arns` and log group ARN outputs; one Quick Setup patch policy (`AWSQuickSetupType-PatchPolicy`) for this account or `patching.target_organizational_units`, in every Region of `regions`; `patching` settings `operation`, `scan_schedule`, `install_schedule`, `reboot_option`, `baselines` (`use_default`, `custom`), `target` (`*`, tags, resource group or instance IDs), `target_organizational_units`, `output_logs` and `attach_instance_policies`; the Quick Setup local deployment administration and execution roles, built on `security/iam-role`; outputs `patch_policy_manager_arn`, `patch_policy_administration_role_arn` and `patch_policy_execution_role_arn`.
- `modules/aws/observability/alarm-routing`: `kms` input with a module key per Region by default (`create = true`); output `kms_key_arns`.
- `modules/aws/security/kms`: `KEY_AGREEMENT` key usage and the `ECC_NIST_EDWARDS25519` key spec.
- `modules/aws/governance/cost-guardrails`: new account module for AWS Budgets (actual 80 %, actual 100 % and forecasted 100 % alerts by default, filters by tag, service and linked account, optional auto-adjust), Cost Anomaly Detection (AWS services monitor, customer managed monitors, immediate SNS and daily email alerts with absolute or percentage thresholds) and optional activation of cost allocation tags.
- `modules/aws/integration/http-api`: API Gateway v2 HTTP API with an auto-deployed `$default` stage, `integrations` of type `lambda` (AWS_PROXY, payload 2.0), `http` (HTTPS only) and `private` (module VPC link to an ALB/NLB listener or Cloud Map service, TLS required for APIGateway.10), JWT and Lambda `authorizers`, `routes` that must name an authorizer or set `authorization = "NONE"` or `"AWS_IAM"` (APIGateway.8), CORS with explicit origins, stage throttling guardrails (2,000 burst, 1,000 requests per second) and per-route throttling, always-on JSON access logs for 365 days (APIGateway.9) with the three `kms` modes, Lambda invoke permissions scoped to the API and to each authorizer, an optional VPC link security group with exclusive egress rules, and an optional Regional custom domain (`TLS_1_2`, mutual TLS, execute-api endpoint off); outputs `id`, `arn`, `name`, `api_endpoint`, `execution_arn`, `stage_name`, `invoke_url`, `authorizer_ids`, `log_group_name`, `log_group_arn`, `kms_key_arn`, `vpc_link_id`, `security_group_id`, `domain_target_name`, `domain_zone_id`.
- `modules/aws/network/nlb`: Network Load Balancer, internal by default, with an always-attached security group (ingress only on listener ports and protocols, egress only to target ports, in the VPC unless destinations are listed); names end in `-nlb`, TCP, UDP, TCP_UDP and TLS `listeners` (ELB.17 TLS policy list, default `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09`, extra certificates), `target_groups` of type `instance`, `ip` or `alb` with optional static `targets`, `static_ips` Elastic IPs for internet-facing NLBs, TLS `access_logs`, an optional PrivateLink `endpoint_service`, deletion protection, cross-zone load balancing and zonal shift on by default; outputs `id`, `arn`, `arn_suffix`, `name`, `dns_name`, `zone_id`, `security_group_id`, `listener_arns`, `target_group_arns`, `target_group_arn_suffixes`, `endpoint_service_name`, `endpoint_service_id`; `target_group_arns` waits for the listeners.
- `modules/oneuptime`: `extra_criteria[*].order` places an extra criterion before or after the generated ones; root outputs `monitor_group_memberships`, `on_call_schedule_ids`, `status_page_group_ids` and the sensitive `incoming_request_secret_keys`, `incoming_email_secret_keys` and `server_monitor_secret_keys`.

### Changed

- CI uses github-ci-library 1.9.4: TFLint through `terraform.yml`, the Trivy IaC scan through `scan.yml`, and `make verify` (every module's `terraform test`) in `grootantech/toolkit:2.1.0`.
- `Makefile` keeps `contracts`, `validate`, `test` and `verify`, with a `MODULES=` filter.
- `modules/aws/security/kms`: replicas through the `region` argument (no `aws.replica` provider), typed `policy_statements`, rotation always on for symmetric keys, outputs `arn` and `id`.
- `modules/aws/compute/lambda`: rebuilt on the building blocks; `package`, `concurrency`, `kms`, `iam_role`, `cloudwatch_logs`, `security_group` inputs; role names end in `lambda` and the Region, alias names include the Region; logs kept 365 days; default runtime `python3.14`; allowed runtimes are the generally available Amazon Linux 2023 runtimes, including `java17.al2023`, `java11.al2023` and `java8.al2023`; `lambda_insights.layer_arn` replaces the fixed layer version.
- `modules/aws/compute/eks`: one module instead of the `cluster` and `node_group` submodules; `API` authentication only, creator admin access on by default, public endpoint only through `endpoint_public_access_cidrs`, `kms`, `iam_role` (node role), `security_group`, `cloudwatch_logs` and `addons` inputs; node groups use name prefixes and follow the cluster version; README and example on Kubernetes 1.37; AL2 node AMI types are rejected.
- `modules/aws/compute/ecs`: rebuilt on the building blocks with the standard `kms`, `iam_role`, `security_group` and `cloudwatch_logs` inputs; ingress only on each service's container port from the listed sources; outputs `arn` and `name`; logs kept 365 days; service-to-service ports are `self` rules in the task security group; execution role names end in `ecs-exec` and the Region.
- `modules/aws/compute/batch`: rebuilt on the building blocks with the standard `kms`, `iam_role`, `security_group` and `cloudwatch_logs` inputs; roles and log group only exist when job definitions do; logs kept 365 days; EC2 compute environments default to `default_x86_64` instead of `optimal`; execution role names end in `batch-exec` and the Region; security group egress is HTTPS to `security_group.egress_cidr_blocks`, other ports only to listed security groups and prefix lists.
- `modules/aws/database/dynamodb`: rebuilt on the building blocks; only `name` and `hash_key` are required; on demand, `STANDARD`, 35-day point-in-time recovery and deletion protection by default; key attributes derived from the keys (`attributes` sets types); indexes are maps keyed by name; autoscaling on by default for `PROVISIONED` tables.
- `modules/aws/database/elasticache/valkey`: rebuilt on the building blocks; `name` required; two nodes with failover and Multi-AZ by default; TLS mode `required`; replication group ID cut to 40 characters through `core/naming`; parameter group family follows `engine_version`; `user_group_id` replaces `user_group_ids`; default Valkey `9.1`; versions below 7.2 are rejected.
- `modules/aws/database/rds/postgres`: rebuilt on the building blocks; only `name`, `engine_version`, `vpc_id` and `subnet_ids` are required; Multi-AZ, 14-day backups, Enhanced Monitoring every 60 s, Performance Insights for 7 days and 365-day log groups by default; master password managed in Secrets Manager by default for user `dbadmin`; `parameters` is a map; security group ingress from security groups, CIDRs and prefix lists; `engine_version` is a major version, 15 or later, so automatic minor upgrades do not drift; README and example on PostgreSQL 18.
- `modules/aws/database/rds/proxy`: rebuilt on the building blocks; `name` required; role from `security/iam-role`; security group egress limited to the database port and HTTPS; `subnet_ids` replaces `vpc_subnet_ids`, `auth` replaces `auth_blocks`, `cloudwatch_logs.enabled` replaces `cloudwatch_logs.create`; endpoints use the proxy subnets and groups unless given their own; `target.security_group_ids` is required while the module creates its security group.
- `modules/aws/network/vpc`: rebuilt on the building blocks; `name` optional; `nat = { mode = "single" | "per_az" | "none" }` (default `single`); route tables, network ACLs and the internet gateway exist only for tiers with subnets; typed `nacl_rules` map; flow log group through `observability/log-group` (365 days, deletion protection) and role through `security/iam-role`; interface endpoint security group through `network/security-group`; one private route table per AZ.
- `modules/aws/network/alb`: rebuilt on the building blocks; `subnet_ids` replaces `subnets`; `security_group` object built on `network/security-group` (listener ports to the listed sources, egress only on target ports); `https_listener` and `http_listener` objects (HTTP redirects unless `http_listener.forward = true`); `waf = { enabled, web_acl_arn, fail_open }`; `access_logs = { enabled, bucket, prefix }`; `deletion_protection` replaces `deletion_protection_enabled`; names cut to 32 characters through `core/naming`; default TLS policy `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09`; `ssl_policy` must be on the ELB.17 list.
- `modules/aws/network/cloudfront`: rebuilt on the building blocks; `name` optional; `origins` is a map keyed by origin ID with `type` (`s3`, `lambda`, `custom`); `default_cache_behavior` object; access log group always in us-east-1 through `observability/log-group` (365 days, deletion protection); managed policies looked up only when used; `minimum_protocol_version` accepts only `TLSv1.2_2025` and `TLSv1.3_2025`.
- `modules/aws/network/waf`: rebuilt on the building blocks; rules named `<type>-<key>`; IP and regex sets named `<base>-<key>`; log group through `observability/log-group` (365 days, deletion protection); `token_domains` sets the web ACL token domains.
- `modules/aws/integration/api-gateway`: rebuilt on the building blocks; `name` optional; logs on `observability/log-group` with 365 days; `cloudwatch_logs` replaces `access_logs`; models and request validators keyed by name; cross-input checks are preconditions on the REST API; custom domains are Regional; enhanced TLS policies by default (`SecurityPolicy_TLS13_1_2_PFS_PQ_2025_09` for Regional APIs and the custom domain, `SecurityPolicy_TLS12_PFS_2025_EDGE` for edge-optimized APIs) with `endpoint_access_mode = "STRICT"`; `tls.domain_security_policy` sets the domain policy.
- `modules/aws/integration/eventbridge`: rebuilt on the building blocks; `bus = { enabled }` replaces `create_bus`; rule names are `<application>-<environment>[-<name>]-<key>`; bus logs on `observability/log-group` at `/aws/vendedlogs/events/event-bus/<bus>`, 365 days, on by default; rules are event-pattern only (`event_pattern` required, a JSON object) and always run on the module bus, or the default bus when `bus.enabled = false`; the target role is shared by rules and schedules, trusts `events` and `scheduler.amazonaws.com` with `aws:SourceAccount`, exists when a rule target needs it or the scheduler is on, and adds `lambda:InvokeFunction`, `sqs:SendMessage`, `events:PutEvents`, dead-letter `sqs:SendMessage`, queue-key `kms:GenerateDataKey`/`kms:Decrypt` through SQS and module-key `kms:Decrypt` only for the schedules and targets that need them; `sqs.message_group_id`, `kinesis.partition_key_path` and target `arn` are optional in the type (rule targets still need `arn`).
- `modules/aws/integration/sqs`: rebuilt on the building blocks; SSE-SQS by default, a KMS key only through `kms`; `dead_letter_queue` object replaces `create_dlq` and `max_receive_count`; outputs renamed to `arn`, `name`, `url`.
- `modules/aws/integration/step-functions`: rebuilt on the building blocks; AWS owned key by default; logs at `/aws/vendedlogs/states/<name>`, level `ERROR`, 365 days; role trust limited to this state machine; outputs renamed to `arn`, `name`; role names end in `sfn` and the Region.
- `modules/aws/storage/s3`: rebuilt on the building blocks; `name` required; bucket named `<application>-<environment>-<name>-<account>-<region>` (63 characters); SSE-S3 by default and SSE-KMS with a bucket key when a key is set; SSE-C blocked; versioning always on; TLS guard statements first, caller statements keep their `Resource`; incomplete uploads aborted after 7 days in every bucket.
- `modules/aws/storage/efs`: rebuilt on the building blocks; `name` required; AWS managed key by default; NFS ingress only from listed groups, CIDRs and prefix lists, no egress; file system policy enforces TLS and root squash; access points always enforce a POSIX user and a root directory; EFS automatic backups off by default (`backup = { enabled = false }`, `storage/backup` owns backups); mount targets planned by subnet count.
- `modules/aws/storage/amplify`: names, tags and validations from the standard; `branches` is a map keyed by branch name; `custom_headers = { enabled, yaml }` replaces `custom_headers` and `default_security_headers`; `basic_auth.enabled` replaces `basic_auth.enable` and needs an 8-character password; domain `certificate_arn` replaces `acm_certificate_arn`; outputs `id` and `arn` replace `app_id` and `app_arn`.
- `modules/aws/security/cognito`: `name` optional; password minimum length 14 enforced; MFA `ON` and `PASSWORD`-only first factor by default; `lambda_triggers` is a map of `{ arn, version }`, custom senders use the module key; `clients` and `groups` are maps keyed by name; `email.ses_identity_arn` replaces `email.ses_arn`; log levels follow the event source; log group `/aws/vendedlogs/cognito/<pool>` kept 365 days; outputs `id`, `arn` and `endpoint` replace `user_pool_id`, `user_pool_arn` and `user_pool_endpoint`; the hosted domain defaults to managed login (version 2) on ESSENTIALS and PLUS and to the classic hosted UI (version 1) on LITE; `domain.managed_login_version` still overrides it. The SES sending policy is now `aws_sesv2_email_identity_policy` on the identity name from `email.ses_identity_arn`, created in that ARN's Region.
- `modules/aws/security/secrets-manager`: `name` required and derived through `core/naming`; `aws/secretsmanager` by default; the value is write-only (`secret_string_wo`, ephemeral, with `secret_string_wo_version`); the resource policy always blocks public policies.
- `modules/aws/security/cloudtrail`: account scope (`application` defaults to `platform`, no `name`); built on `core/naming`, `core/encryption`, `observability/log-group`, `security/iam-role` and `storage/s3` (the log bucket, now with SSE-C blocked and incomplete uploads always aborted); switches are `trail.enabled`, `bucket.enabled`, `organization_admin.enabled`, `bucket.object_lock.enabled`, `bucket.access_logs` and `trail.data_events.*.enabled`; the bucket is `<application>-<environment>-cloudtrail-<account>-<region>`; outputs `arn`, `name`, `role_arn`, `role_name`, `kms_key_arn`.
- `modules/aws/security/config`: account scope with `application` defaulting to `platform` and no `name`; names through `core/naming` (bucket `<application>-<environment>-config-<account>-<region>`, rules and packs `<application>-<environment>-<key>`); aggregator role built on `security/iam-role` and the delivery bucket on `storage/s3`; `bucket.enabled`/`bucket.name` replace `create`/`name`/`existing_name`, `bucket.access_logs` replaces `access_logging`, `service_linked_role.enabled` replaces `create_service_linked_role`, `recorder.recording_mode_override.enabled` replaces the null object; policies rendered without `aws_iam_policy_document`; short descriptions and messages.
- `modules/aws/security/security-hub`: account scope with `application` defaulting to `platform` and no `name`; `hub.enabled` and `organization_admin.enabled` replace `hub_enabled` and the null `organization_admin`; one default standards map; CRI Profile v2.2 only with `cri_profile = { enabled, standard_arn }`; a configuration policy (the default `baseline` included) is created only when it has `targets`; associations keyed by policy and index so targets may be unknown at plan; short descriptions and messages; `aws_securityhub_account.this` keyed by Region; configuration policy targets and `self_managed_targets` need central configuration.
- `modules/aws/security/guardduty`: account scope (`application` defaults to `platform`, no `name`); `detector = { enabled, finding_publishing_frequency }` and `organization_admin = { enabled, account_id, manage_trusted_access }` switches; `publishing_destination` takes `enabled` and its key from `kms`; filter keys are lowercase names (`<application>-<environment>-<key>`, 64 characters max); policies rendered without `aws_iam_policy_document`; short descriptions and messages; `organization_configuration = { enabled, auto_enable_members }`.
- `modules/aws/security/inspector`: account scope with `application` defaulting to `platform` and no `name`; suppression rules named `<application>-<environment>-<key>` through `core/naming` (keys a-z 0-9 -); `organization_admin.enabled` replaces the null object; `organization_configuration.activate_admin_account` replaces `enable_admin_account`; `member_associations` reports the relationship status only; short descriptions and messages; `organization_configuration = { enabled, activate_admin_account, member_account_ids }`; suppression rules are rejected only in the management account call.
- `modules/aws/security/detective`: account scope (`application` defaults to `platform`, no `name`); `behavior_graph = { enabled, member_accounts }`, `organization_configuration = { enabled, auto_enable }` and `organization_admin = { enabled, account_id }` switches instead of null objects; README states that GuardDuty must be enabled first; short descriptions and messages.
- `modules/aws/security/iam-access-analyzer`: account scope with `application` defaulting to `platform` and no `name`; analyzers named `<application>-<environment>-external|unused|internal` through `core/naming`; `analyzers.enabled` replaces `analyzers_enabled`; `organization_admin.enabled` replaces the null object; short descriptions and messages; `organization_configuration.enabled` chooses organization or account analyzers; account ID exclusions and inclusions need the organization.
- `modules/aws/storage/backup`: account scope with `application` default `platform` and no `name`; `vault`, `plan` and `organization_admin` switches are objects with `enabled`; the service role comes from `security/iam-role`; policies are built as JSON locals; `resource_types` no longer selects EC2 instances by default (EBS covers attached volumes); the Vault Lock audit control is added only while Vault Lock is on.
- `modules/aws/governance/organizations`: organization scope (`application` defaults to `platform`, no `name`); a library or custom policy, and its policy type, exists only while it has `targets`; policies named `<application>-<environment>-<key>` through `core/naming`; `policy_management_delegation`, `ec2.vpc_block_public_access` and `ec2.allowed_images_settings` are switched with `enabled`; short descriptions.
- `modules/aws/governance/account-baseline`: account scope (`application` defaults to `platform`, no `name`); per-Region settings through `regions`; roles built on `security/iam-role` and named with the Region; EBS encryption by default uses `aws/ebs` unless a Region has a key in `kms_key_arns`; one `permissions_boundary_arn` for both roles.
- `modules/aws/governance/systems-manager`: account scope with `application` defaulting to `platform` and no `name`; names from `core/naming` (roles end in the Region, the inventory bucket is `<application>-<environment>-ssm-inventory-<account>-<region>`); roles built on `security/iam-role`, log groups on `observability/log-group`; `permissions_boundary` is now `permissions_boundary_arn`, `inventory_bucket.create` is `inventory_bucket.enabled`, `organization_admin` is `{ enabled, account_id, manage_trusted_access }`; the resource data sync is opt-in; Quick Setup host management is rejected while inventory, agent update or patch scan run; the inventory bucket is built on `storage/s3` (SSE-S3 unless `kms` sets a key) with the Systems Manager delivery statements added to its policy; patching uses the AWS default baselines unless `patching.baselines.use_default = false`; custom baselines move to `patching.baselines.custom` and are created once, in the provider Region; the Default Host Management role gets `AWSQuickSetupPatchPolicyBaselineAccess` while patching is on, and S3 writes for `patching.output_logs`; Quick Setup host management can run with the patch policy and stops its own patch scan while the policy runs; an OU-targeted patch policy may share the `organization_admin` call.
- `modules/aws/observability/alarm-routing`: account scope (`application` defaults to `platform`, no `name`); topics named `<application>-<environment>-<severity>`; key policy built by the module; topic policy rendered without IAM data sources; short descriptions.
- `modules/aws/observability/cloudwatch-alarms`: names and tags from `core/naming`; `application`, `environment` and `name` validated; long names cut to 255 characters with a 6-character hash; the CIS CloudWatch.1-14 preset requires `notifications.enabled`; CloudFront and CLOUDFRONT-scope WAF alarms always in `us-east-1`; short descriptions.
- Every AWS module and example requires Terraform `>= 1.17.0`; `compute/lambda` and the examples that package code require `hashicorp/archive >= 2.8.1`.
- `docs/terragrunt.md`: account and organization layers beside the environment stack, `dependency` outputs with mocks, native S3 locking, Terraform `>= 1.17.0`, one provider in the composition root, offline plans under a mocked provider; `docs/consumption.md` runs each module at its scope; `docs/AWS.md` lists account layouts (one account, an organization).
- README examples: api-gateway reads `module.cognito.arn`; the eventbridge ECS schedule reads the `compute/ecs` outputs; API domains point at the API through `network/route53` records; account-baseline links `integration/api-gateway`; backup explains `region_settings`; log-bucket names the CloudFront and WAF settings that deliver to it; `docs/testing.md` states the `>= 1.17.0` AWS floor.

### Removed

- Checkov, the `make scan*` and `make compliance` targets, `.tflint.hcl`, `docs/state-migration.md`, `docs/assets/`, the compliance documentation (`docs/compliance/`) and its scripts (`scripts/compliance/`); scanner suppressions are explained in each module README.
- `modules/aws/compute/lambda`: the deployer role, Application Signals input and configurable placeholder message; `lambda_insights.layer_version`; the `java17`, `java11` and `python3.11` (Amazon Linux 2), `ruby3.3` and preview `nodejs26.x` and `python3.15` runtimes.
- `modules/aws/security/kms`: `policy_json`, `is_enabled`, `enable_key_rotation`, `replica_key`.
- `modules/aws/compute/eks`: the `cluster` and `node_group` submodules, `authentication_mode`, `endpoint_public_access`, `enable_*` inputs and the standalone add-on Pod Identity associations.
- `modules/aws/compute/ecs`: `cluster_id`, `alb_security_group_id`, `create_alb_ingress_rule`, `security_group_ids`, `task_execution_role_arn`, `secret_arns` and the module-wide autoscaling inputs; `aws_vpc_security_group_ingress_rule.internal`.
- `modules/aws/compute/batch`: EventBridge rules, targets and role (use `integration/eventbridge` with the job queue outputs) and the `custom_*_policies` inputs.
- `modules/aws/database/dynamodb`: `kms_key_arn`, `enable_contributor_insights`, `contributor_insights_index_name`, `pitr_recovery_period_in_days`, `read_capacity`/`write_capacity`, per-replica point-in-time recovery and deletion protection switches, outputs `table_name` and `table_arn`.
- `modules/aws/database/elasticache/valkey`: `kms_key_id`, `allowed_cidr_blocks`, `egress_cidr_blocks`, `log_delivery`, `parameter_group_family`, `automatic_failover_enabled`, `multi_az_enabled`, outputs `configuration_endpoint_address` and `replication_group_id`.
- `modules/aws/database/rds/postgres`: the `aws.replica` provider alias, `kms_key_id`, `allowed_cidr_blocks`, `egress_cidr_blocks`, `availability_zone`, `enable_automated_backup_replication`, `automated_backup_replication_kms_key_arn`, the CloudWatch metric filters (owned by `observability/cloudwatch-alarms`), output `username`.
- `modules/aws/database/rds/proxy`: `kms_key_arn`, `allowed_cidr_blocks`, `vpc_subnet_ids`, `endpoint_network_type`, `target_connection_network_type`, endpoint `target_role`, the security groups the module created per endpoint and per-endpoint tags, outputs `proxy_name`, `default_target_group_name` and `endpoint_names`.
- `modules/aws/network/vpc`: `aws_availability_zone_names`, `public_subnet_cidrs`, `private_subnet_cidrs`, `intra_subnet_cidrs` (replaced by the tier objects), `kms_key_arn`, `dns`, `nat.enabled`, `nat.eip_allocation_ids`, the regional NAT mode, `private_subnet_internet_gateway`, `intra_subnet_internet_gateway`, untyped `nacl` and `additional_routes`, outputs `public_subnets`, `private_subnets`, `intra_subnets`, `route_table_ids`, `flow_log_group_name`, `default_security_group_id`.
- `modules/aws/network/alb`: `subnets`, `security_groups`, `allowed_cidr_blocks`, `listener_port`, `listener_protocol`, `allow_plain_http`, `certificate_arn`, `ssl_policy`, `enable_waf_fail_open`, `web_acl_arn`, `connection_logs`, the `default_*` target group inputs and `extra_routes`, outputs `lb_arn`, `lb_arn_suffix`, `lb_name`, `lb_dns`, `listener_arn`, `default_target_group_arn*`, `extra_target_group_arn*`.
- `modules/aws/network/cloudfront`: `kms_key_arn`, `log_delivery_region`, `web_acl_id`, `origin_access_controls`, `default_s3_origin_access_control`, `default_cache_behavior_origin_id`, `static_paths`, `response_headers_policy_id`, `attach_managed_security_headers_policy`, `cache_tag_config_header_name`.
- `modules/aws/network/waf`: `association_arns` (the protected resource associates), the unused `name` fields of rules, IP sets and regex sets, `kms_key_arn`, the `aws_wafv2_api_key` resource, outputs `web_acl_arn`, `web_acl_id`, `web_acl_name`, `web_acl_capacity`, `web_acl_metric_name`.
- `modules/aws/integration/api-gateway`: `kms_key_arn`, `access_logs`, `waf_web_acl_arn`, `tracing_enabled`, `rate_limiting` (use `method_settings`), `execution_logging.create_log_group` and `retention_in_days`, `authorizers[*].name`, `models[*].description` and `content_type`, `integration.response_transfer_mode`, `integration.tls_config`, `lambda_function_arn`, the `PRIVATE` endpoint type, the `terraform_data` validation resource, outputs `rest_api_id`, `api_name`, `execution_log_group_name`; the legacy `TLS_1_2` policy and the 2021 `SecurityPolicy_TLS13_1_2_2021_06` policy.
- `modules/aws/integration/eventbridge`: `kms_key_arn`, `create_bus`, `bus_name`, `bus_tags`, the flat `targets` map with `rule_name`, `require_target_dlq`, `bus_policy`, `organization_id`, rule `role_arn` and `force_destroy`, output `event_rules`; `rules[*].schedule_expression` (scheduled rules); use `scheduler.schedules`.
- `modules/aws/integration/sqs`: `kms_key_arn`, `create_dlq`, `max_receive_count`, `redrive_policy`, `redrive_allow_policy`, `policy`, `allow_eventbridge`, `eventbridge_source_arns`, `fifo_queue`, `content_based_deduplication`, outputs `queue_arn`, `queue_url`, `queue_name`.
- `modules/aws/integration/step-functions`: `kms_key_arn`, `tracing_enabled`, outputs `state_machine_arn`, `state_machine_name`.
- `modules/aws/storage/s3`: `kms_key_arn`, `bucket_name_override`, `enable_versioning`, `object_ownership`, `access_control_policy` and the ACL resource, `custom_policy_statements`, `replication_configuration`, `access_logging`, `noncurrent_version_expiration_days`, outputs `bucket_arn`, `bucket_name`, `bucket_id` and `bucket_regional_domain_name`.
- `modules/aws/storage/efs`: `kms_key_arn`, `security_group_ids`, `allowed_security_group_ids`, `allowed_cidr_blocks`, `allowed_client_role_arns`, `allow_root_access`, `mount_target_egress_cidr_blocks`, `allow_unenforced_access_points`, `enable_backup`, `throughput_mode`, `provisioned_throughput_in_mibps`, `transition_to_ia`, `transition_to_archive`, outputs `mount_target_ids` and `access_points`.
- `modules/aws/storage/amplify`: `default_security_headers`, outputs `app_id`, `app_arn` and `branch_arns`.
- `modules/aws/security/cognito`: `kms_key_arn`, `advanced_security_mode`, `enable_risk_configuration`, `email_verification`, `invite_email`, `web_authn_relying_party_id`, `web_authn_user_verification`, `allow_admin_create_user_only`, `custom_schema_attributes`, `certificate_arn`, the hard-coded invitation SMS message and the legacy `email_verification_message`/`email_verification_subject` arguments, outputs `user_pool_id`, `user_pool_arn` and `user_pool_endpoint`; the SES v1 `aws_ses_identity_policy` resource.
- `modules/aws/security/secrets-manager`: `kms_key_arn`, `name_prefix`, `region`, `type`, `policy`, `block_public_policy`, `rotation_config`, `secret_string`, `secret_binary`, `version_stages`, `force_overwrite_replica_secret`, outputs `id` and `policy_id`.
- `modules/aws/security/cloudtrail`: `name`, `kms_key_arn`, `bucket.additional_policy_json`, `cloudwatch_logs.restrict_role_trust` and `role_permissions_boundary_arn`, and the `trail_home_region` and `delegated_admin_account_id` outputs.
- `modules/aws/security/config`: `name`, `kms_key_arn`, `aggregator.name` inputs and the `regions`, `global_resource_region`, `delivery_bucket_name`, `delivery_channel_names`, `organization_rule_names`, `rule_identifiers` and `delegated_administrator_service_principals` outputs.
- `modules/aws/security/security-hub`: the `name` input, the CRI `check` warning, and the `hub_arn` (now `arn`), `organization_configuration_type`, `organization_admin_account_id`, `associations`, `enabled_standard_arns`, `cri_profile_included` and `governance_tags` outputs.
- `modules/aws/security/guardduty`: `name`, `delegated_admin_enabled`, `finding_publishing_frequency`, `publishing_destination.kms_key_arn` and `create`; outputs `regions`, `delegated_admin_account_id`, `enabled_features`, `filter_names`.
- `modules/aws/security/inspector`: `name` input and the `delegated_admin_account_id`, `regions`, `auto_enable` and `enabled_resource_types` outputs.
- `modules/aws/security/detective`: `name`; outputs `delegated_admin_account_id`, `regions`, `organization_admin_regions`, `auto_enable`.
- `modules/aws/security/iam-access-analyzer`: `name` and `analyzers_enabled` inputs and the `archive_rule_names` and `delegated_admin_account_id` outputs.
- `modules/aws/storage/backup`: `name`, `region`, `kms_key_arn`, `backup_enabled`, `plan_enabled`, `vault.force_destroy`, `iam_role.source_account_condition` and the `region`, `vault_lock`, `rules`, `selected_resources`, `framework_controls` and `delegated_administrator_account_id` outputs.
- `modules/aws/governance/organizations`: the `inspector`, `guardduty`, `securityhub` and `backup` policies and those policy types for custom policies and delegation (the service modules own enablement); the `protect_s3_account_public_access_block` SCP (the `s3` declarative policy locks the setting); the `enabled` flag of library policies; the `name` input; outputs `trusted_access_principals`, `delegated_administrators` and `root_access_features`.
- `modules/aws/governance/account-baseline`: `name` input, `support_role.permissions_boundary_arn`; outputs `password_policy`, `s3_account_public_access_block`, `alternate_contacts_account_id`, `alternate_contact_types`, `ebs_default_kms_key_arns` and `ebs_encryption_by_default_regions`.
- `modules/aws/governance/systems-manager`: `name`, `kms_key_arn`, `kms_key_arns`, log group name and retention overrides, `default_host_management.role_name`, `inventory_bucket.name`; outputs `regions`, `service_settings`, `session_document_name`, `resource_data_sync_bucket_name`, `kms_key_policy_json`, `delegated_administrator_account_id`; patch maintenance windows, their targets and tasks, patch groups, default baseline registration and the maintenance window role; `patch_baselines` input and `patching` settings `patch_group`, `patch_group_tag_key`, `register_default_baselines`, `schedule_timezone`, `max_concurrency`, `max_errors` and the `scan`/`install` window objects; outputs `maintenance_window_role_arn`, `maintenance_window_role_name`, `patch_group` and `maintenance_window_ids`.
- `modules/aws/observability/alarm-routing`: `name`, `kms_key_arn` and `regional_kms_key_arns` inputs (use `kms`, with an `mrk-` key ID across Regions); outputs `regions`, `topic_names` and `kms_key_policy_json`.
- `modules/aws/observability/cloudwatch-alarms`: `cloudfront_metrics_region` input and `enabled_alarm_count` output.

### Fixed

- `modules/aws/compute/ecs`: the default ingress rule had no source and opened TCP 8000-8004; SSM parameter secrets now get `ssm:GetParameters`; Cloud Map services are created only for services that use discovery; task definitions no longer ignore tag changes.
- `modules/aws/database/dynamodb`: Contributor Insights on an index no longer replaces the table-level configuration.
- `modules/aws/database/rds/postgres`: a major version upgrade is possible (it was always refused at apply), and the README wires `event_subscription` to an alarm-routing topic that allows `events.rds.amazonaws.com`.
- `modules/aws/database/rds/proxy`: the connection pool block is always rendered with its documented defaults.
- `modules/aws/network/vpc`: `nat.mode = "none"` plans cleanly; no unused network ACLs or route tables for empty tiers.
- `modules/aws/network/alb`: the web ACL association and listener resources no longer depend on null tests of ARNs, so they plan with ARNs from other modules; `arn` and `target_group_arns` wait for the listeners, so an ECS service or an NLB `alb` target no longer registers before a listener exists.
- `modules/aws/integration/api-gateway`: Lambda permissions for `ANY` methods used `ANY` instead of `*` in the source ARN; permissions now target the alias through `qualifier`, so they no longer drift.
- `modules/aws/integration/eventbridge`: the log resource policy grants only `delivery.logs.amazonaws.com` and exists only while bus logging is on.
- `modules/aws/integration/sqs`: the queue policy no longer uses `count = 1`; FIFO names keep the `.fifo` suffix (`<base>-dlq.fifo` for the DLQ); turning `fifo.high_throughput` off sets the queue-wide deduplication scope and throughput limit back; a dead-letter queue used by an EventBridge rule or SNS topic can admit it (its policy only had the TLS guard, so failed events were dropped).
- `modules/aws/integration/step-functions`: the log delivery key statement uses `StringLike` for its wildcard source ARN.
- `modules/aws/security/cognito`: log export now follows the plan: `userNotification` errors on every tier, `userAuthEvents` only on PLUS with threat protection; threat protection and risk configuration only on PLUS.
- `modules/aws/storage/efs`: mount targets and security group rules no longer depend on subnet or group IDs being known at plan.
- `modules/oneuptime`: every monitor joins its component's monitor group (`oneuptime_monitor_group_resource`); the stack-wide `custom_fields` is merged into each monitor's and status page's own fields, with validation; the README's rate-limit criterion example can fire; `docs/ONEUPTIME.md` gives the current on-call defaults (10 minutes, 10 repeats); grouping rule descriptions corrected.

### Security

- `modules/aws/compute/ecs`: the execution role writes logs, pulls only from the ECR repositories in the images and decrypts secrets only through Secrets Manager or SSM; task roles have no log permissions, X-Ray only with tracing, and trust ECS tasks in this account only.
- `modules/aws/compute/batch`: least-privilege execution role, job role trusted by ECS tasks in this account only, credential-like environment names and root users rejected; default egress is HTTPS only.
- `modules/aws/compute/eks`: the node role drops `AmazonEKS_CNI_Policy` when the VPC CNI has its own Pod Identity role; nodes use `AmazonEC2ContainerRegistryPullOnly`.
- `modules/aws/compute/ecr`: `*` pull principals rejected; an `Allow` to `*` needs a condition.
- `modules/aws/database/dynamodb`: replicas always keep point-in-time recovery and follow `deletion_protection`.
- `modules/aws/database/elasticache/valkey`: `/0` ingress rejected; snapshots cannot be turned off; AUTH token validated (16-128 characters, not with a user group).
- `modules/aws/database/rds/postgres`: `/0` ingress rejected; `rds.force_ssl` cannot be overridden; more default admin names rejected; the master password is never a plain input.
- `modules/aws/database/rds/proxy`: `/0` ingress rejected; egress no longer open on every port; the role decrypts only through Secrets Manager.
- `modules/aws/network/vpc`: `nacl_rules` rejects 22 and 3389 from the internet (EC2.21); private network ACLs no longer allow 80, 443 and 53 from the internet; flow log group kept 365 days with deletion protection.
- `modules/aws/network/alb`: only `ELBSecurityPolicy-TLS13-*` policies (ELB.17); `monitor` desync mode rejected (ELB.12); `/0` ingress only on internet-facing load balancers; egress limited to target ports.
- `modules/aws/network/cloudfront`: every S3 and Lambda URL origin is signed with origin access control (CloudFront.13, CloudFront.16); only TLS 1.2 or 1.3 viewer policies; access logs always on.
- `modules/aws/network/waf`: logging always on with `authorization` and `cookie` redacted; a web ACL without rules is rejected (WAF.10); logs kept 365 days.
- `modules/aws/integration/api-gateway`: the execute-api endpoint requires TLS 1.2; authorizer invoke permissions are limited to the API's authorizers; HTTP integrations can no longer skip TLS verification.
- `modules/aws/integration/eventbridge`: the target role exists only when a target needs it and holds only those targets' actions on their ARNs.
- `modules/aws/integration/sqs`: publisher grants are limited by `aws:SourceArn` and module key grants by `aws:SourceAccount`; caller statements cannot remove the TLS-only guard.
- `modules/aws/integration/step-functions`: the role trust policy names this state machine (with versions and aliases) instead of every state machine in the account; X-Ray permissions only when tracing is on.
- `modules/aws/storage/s3`: the replication role trusts S3 only for this bucket (`aws:SourceAccount`, `aws:SourceArn`) and decrypts the source key only through S3.
- `modules/aws/storage/efs`: `0.0.0.0/0` and `::/0` NFS ingress rejected; anonymous NFS access blocked by the file system policy.
- `modules/aws/security/secrets-manager`: secret values never reach Terraform state.
- `modules/aws/security/cloudtrail`: policies are rendered as JSON locals; caller bucket statements can no longer replace the CloudTrail grants or TLS denies.
- `modules/aws/governance/organizations`: no policy is created unattached; custom policies need targets.
- `modules/aws/governance/account-baseline`: IMDSv2 defaults, snapshot and AMI public sharing blocked, serial console off and ECR enhanced scanning on by default.
- `modules/aws/governance/systems-manager`: with `kms` set, the module key policy grants CloudWatch Logs only the module log groups and Systems Manager only this account's resource data syncs.
- `modules/aws/observability/alarm-routing`: topics can no longer fall back to `aws/sns`; `kms = {}` is rejected because CloudWatch alarms cannot publish to it; `budgets.amazonaws.com` and `costalerts.amazonaws.com` in `additional_publisher_service_principals` get their own topic and key policy statements limited by `aws:SourceAccount` and `aws:SourceArn`, so budget and cost anomaly alerts reach the encrypted topics; `events.rds.amazonaws.com` is documented and tested as a publisher for RDS event subscriptions.
- `modules/aws/security/iam-role`: inline policies and managed attachments are exclusive (`aws_iam_role_policies_exclusive`, `aws_iam_role_policy_attachments_exclusive`); a policy attached outside Terraform is removed on the next apply.
- `modules/aws/network/security-group`: rules are exclusive (`aws_vpc_security_group_rules_exclusive`); a rule added outside Terraform is removed on the next apply.
- `modules/aws/security/identity-center`: managed and customer managed policy attachments are exclusive per permission set.

## [2.4.0] - 2026-11-20

### Changed

- On-call schedules are per component and off by default. `on_call_overrides.<component>.schedule_enabled = true` gives that component its schedule, layer and binding to its escalation rule; every other component gets none, and its escalation rule pages only the owning teams. Rota membership cannot be set with a project-scoped API key, so a schedule nobody asked for would sit empty and OneUptime would flag it.

### Removed

- `on_call_schedules_enabled`, the all-components switch added in 2.2.0. Use `schedule_enabled` per component instead.

## [2.2.0] - 2026-11-20

### Added

- `on_call_schedules_enabled` (default `true`) switches off each component's on-call schedule, its layer and the binding to the escalation rule. The escalation rule keeps paging the owning teams, and OneUptime's Setup Health no longer flags a schedule nobody is in. Rota membership cannot be managed with a project-scoped API key, so a stack that pages whole teams has no use for the empty schedules.

## [2.1.0] - 2026-11-18

### Added

- On-call paging: each component's incidents run its on-call policy, through an `oneuptime_incident_on_call_rule` per component, and the policy's escalation rule pages every team that owns the component (`oneuptime_team_on_call_duty_escalation_rule`). Until now the policies existed but nothing reached them and nobody was on them.
- `on_call_overrides` gives a component its own on-call timings - how often its policy pages again and how many times - while every other component keeps the stack-wide `on_call_escalation_rules` and `on_call_policy_config`. A field left out keeps the stack-wide value, and a key that is not a component fails validation.
- `on_call_routing` chooses which records page: `incidents` (default `true`) and `alerts` (default `false`, through `oneuptime_alert_on_call_rule`), so one outage pages once.

### Changed

- On-call defaults: the escalation rule pages again every 10 minutes (was 30), and the policy repeats up to 10 times (was 3) while nobody acknowledges. Every field of `on_call_policy_config` and `on_call_escalation_rules` is now optional, so a stack sets only what differs.

## [2.0.1] - 2026-11-18

### Fixed

- Alert and incident grouping rules take distinct priorities - 10, 20, 30 and so on in component name order - instead of priority `1` each. OneUptime 14 keeps a project's grouping rules in one ordered list where two rules cannot share a number, so it moved the duplicates to 2, 3 and so on, and every apply failed with "Provider produced inconsistent result after apply". A number no other rule holds is kept as written, so the plan and the server now agree.
- A status page's `owner_group_names` skips a group that owns one of the page's component labels. The module's status page owner rule already makes that group an owner, and OneUptime 14 refuses the second, with "This team is already an owner of this status page".
- A status page carries the labels of the groups that own its component labels. The module's status page label rule adds those labels on the server as soon as the page is created, so a page planned without them failed the apply with an inconsistent `labels` value.

### Added

- A status page `domain` takes `domain_id` as an alternative to `domain_name`. OneUptime 14 cannot list domains by name ("Invalid column on Domain - name"), so the name lookup fails there; a page given the domain's id attaches it without a lookup. Exactly one of the two must be set. `subdomain = "@"` is sent as `""`, the value OneUptime stores for the domain itself, so the apply does not fail with an inconsistent `subdomain`.

### Changed

- CI calls the github-ci-library 1.9.1 reusable workflows instead of 1.7.0, and the repository verification job runs in `grootantech/toolkit:2.0.1` (Terraform 1.17, Trivy 0.76) instead of 1.2.0.

## [2.0.0] - 2026-10-27

### Added

- `docs/repository-layout.md`, `docs/terragrunt.md`, `docs/module-contract.md`, `docs/naming-and-tagging.md`, `docs/security-baselines.md`, `docs/module-readme.md` and `docs/versioning.md`: the README's sections 1 and 3–8, one task per page. Section 2 joins `docs/consumption.md` and section 9 `docs/testing.md`, now titled Development and testing.
- A Requirements section in the README (Terraform `>= 1.9.0`; provider bounds in each module's README) and, in `docs/versioning.md`, the deprecation policy: announced in the changelog and migration guide, and kept through at least the next MINOR release where practical.

### Changed

- The OneUptime areas — `alerts`, `incidents`, `monitors`, `oncall`, `status-pages`, `workflows` and `workflows-templates` — live directly under `modules/oneuptime/` instead of `modules/oneuptime/modules/`. The root module's calls keep their names, so no resource address changes.
- The Teams template's source is `//modules/oneuptime/workflows-templates/teams-notification`. A stack that calls it changes the path when it upgrades (MIGRATION.md).
- `tests/verify_modules.py` treats a module inside another module's directory as internal to it, instead of a module under a `modules/` directory. The areas still take their governance inputs and published examples from the root module.
- The README is a slim documentation index: the task table, requirements, a "Reading with an AI assistant" section that says which release to read, and the license. Reading the index no longer means reading every standard.
- The README header drops its hand-kept release line and the link to the ai-skills compatibility page: the tag is the release, and this library documents its own versioning and requirements.
- Examples in the docs and the module READMEs pin `?ref=<version>`, which shows the syntax, instead of the current release; a release no longer re-pins every example. `tests/verify_modules.py` accepts `<version>` as well as a stable SemVer tag, and still rejects relative paths, branches and pre-releases.
- The "current state" callouts in the module contract and naming pages describe the release they ship in rather than naming it.
- CI calls the github-ci-library 1.7.0 reusable workflows instead of 1.6.1.

## [1.5.0] - 2026-10-23

### Added

- `modules/oneuptime`, which turns an inventory of components, owning groups and monitors into OneUptime labels, teams, monitors, alert and incident rules, on-call policies, status pages and workflows, with one internal submodule per area under `modules/oneuptime/modules/`.
- Monitor probe steps and Offline / Degraded / Operational criteria generated from `monitor_type` for 15 monitor types, with module, stack and per-item defaults through `monitor_defaults` and `status_page_defaults`.
- Plan-time validation that names the offending monitors, status pages and workflows when inputs reference each other inconsistently.
- `modules/oneuptime/modules/workflows-templates/teams-notification`, which builds the five standard Microsoft Teams notification workflows without creating resources.
- A mock-provider `terraform test` suite for every module directory — the 24 AWS modules, the OneUptime module, its six submodules and the Teams template — covering naming, governance tags, security defaults, parameters and input validation. They run in CI with no credentials.
- `docs/ONEUPTIME.md`, the OneUptime counterpart of `docs/AWS.md`: module catalog, secret handling, monitoring baselines, naming and labelling standards, an end-to-end composition and a Terragrunt dev/prod layout.
- The OneUptime module guide, `modules/oneuptime/CONVENTIONS.md`, a OneUptime section in `docs/other-providers.md`, and a documentation index row.

### Changed

- `tests/verify_modules.py` checks each provider family against its own contract: AWS modules keep `hashicorp/aws`, `application`, `environment` and tag governance; OneUptime modules need `oneuptime/oneuptime`, `application` and label governance. Checks on AWS modules are unchanged.
- Internal submodules under a module's own `modules/` directory need a README and take their governance variables and published examples from the parent.
- Every module requires Terraform `>= 1.9.0`, raised from `>= 1.5.0` on the 23 AWS modules; `secrets-manager` keeps `>= 1.11.0`. Modules validate one input against another, which Terraform supports from 1.9 (`compute/lambda` already did), and `tests/verify_modules.py` rejects a lower floor.
- The OneUptime module and its submodules require `oneuptime/oneuptime` `>= 13.0.6, < 14.0.0`; 14.x removes the `name` argument of the `oneuptime_domain` data source.
- README §1, §4 and §9 describe the OneUptime family and the 32 module directories the gate now covers.
- Every usage example in the module READMEs, README and `docs/AWS.md` pins `?ref=1.5.0` instead of `1.0.0`, and the README's current-state notes are stamped `1.5.0`.
- Pinned repository CI reusable workflow callers to `github-ci-library` `@1.6.1`.
- `tests/verify_modules.py` fails a module without a `tests/*.tftest.hcl` suite.
- A test file no longer raises a module's `required_version`: test files load only under `terraform test`, in the CI toolkit image. README §4.4 and `docs/testing.md` say so, and `docs/testing.md` lists what a suite covers.

### Fixed

- Generated OneUptime monitor criteria create only what their preset promises: Offline opens an incident, Degraded raises an alert, and Operational creates neither. Previously Offline and Degraded both opened an incident and raised an alert, and Operational carried empty incident and alert blocks. `criteria.<preset>.create_incidents` / `create_alerts` still override the preset.
- The OneUptime `workflow_variable_contents` validation names the undeclared variables instead of failing with "Error message refers to sensitive values".
- The `docs/testing.md` example reads the S3 encryption rule with `one()`; `rule` is a set in AWS provider 6.x.

## [1.4.0] - 2026-10-23

### Changed

- Updated [`grootantech/toolkit`](https://github.com/grootan-devops/toolkit) from `1.1.0` to `1.2.0`

## [1.3.0] - 2026-10-01

### Added

- A documentation index in `README.md`, and guides for consuming modules (`docs/consumption.md`), deriving inputs and outputs from the provider schema (`docs/provider-schema.md`), state migration and the release plan gate (`docs/state-migration.md`), module test shapes (`docs/testing.md`), and naming and capability tables for providers other than AWS (`docs/other-providers.md`).
- The capability-status derivation procedure in README §6.1, and an architecture diagram template in `docs/assets/`.

### Fixed

- The README repository layout shows `docs/AWS.md` under `docs/`.
- The Terragrunt architecture headings in the README (§3) and `docs/AWS.md` (§6) no longer carry a pattern name, and the documentation index links §3 by its current anchor.

## [1.2.0] - 2026-09-25

### Added

- Added focused README source contract regressions to `make contracts`.

### Changed

- Bumped PR verification container image to `grootantech/toolkit:1.1.0`.
- Pinned repository CI reusable workflow callers to `github-ci-library` `@1.3.1`.
- Module interfaces and governance contracts remain fully backward compatible.

### Fixed

- Listed the existing `hashicorp/archive` provider requirement in the Lambda module README.
- Accepted any stable SemVer release tag in public Git module README examples instead of requiring `1.0.0`.
- Documented that the deprecated S3 `public_access_block` input is accepted but ignored while all four public access blocks remain enabled.
- Removed six unused context lookups from KMS, Batch, EKS cluster, and RDS/Postgres; no managed resource or public module API changed.
- The native contract gate now flags unreferenced data sources in any module Terraform file.

## [1.1.1] - 2026-09-23

### Changed

- Normalize the Docker Hub toolkit reference used by PR verification; module interfaces remain unchanged.

## [1.1.1] - 2026-09-23

### Changed

- Normalize the Docker Hub toolkit reference used by PR verification; module interfaces remain unchanged.

## [1.1.0] - 2026-09-22

### Changed

- Pinned the repository's GitHub Actions verification workflows to `github-ci-library` 1.0.0.
- Refreshed release metadata and documentation without changing module interfaces.

## [1.0.0] - 2026-09-19

### Added

- Initial public release.
