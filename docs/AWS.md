# AWS modules

The AWS modules live under [`modules/aws/`](../modules/aws/) and share one standard:
[module contract](module-contract.md), [naming and tagging](naming-and-tagging.md) and
[security baselines](security-baselines.md). Each module README names the Security Hub CSPM controls it meets.

## Catalog

`workload` modules are called once per application, environment and instance; `account` modules once per account
(all Regions through `regions`); `organization` modules once per organization; `helper` modules are composed by the
others.

### Core helpers

| Module | Scope | What it creates |
| --- | --- | --- |
| [`core/encryption`](../modules/aws/core/encryption) | `helper` | Turns the standard `kms` input into the key ARN a module uses: the AWS managed key (null), a key it creates through `security/kms`, or the caller's key. |
| [`core/naming`](../modules/aws/core/naming) | `helper` | Derives every resource name and the governance tags for the AWS modules, so names never collide across Regions, accounts or module instances. |
| [`core/policy-document`](../modules/aws/core/policy-document) | `helper` | Renders the library's typed `policy_statements` into IAM or resource policy JSON. No provider and no resources, so tests read every statement offline. |

### Security

| Module | Scope | What it creates |
| --- | --- | --- |
| [`security/acm`](../modules/aws/security/acm) | `workload` | A public ACM certificate validated through DNS records in a Route 53 hosted zone. |
| [`security/cloudtrail`](../modules/aws/security/cloudtrail) | `account` | One multi-Region CloudTrail trail (an organization trail by default) with log file validation, a KMS key, a CloudWatch Logs log group with its delivery role and a hardened S3 log bucket. |
| [`security/cognito`](../modules/aws/security/cognito) | `workload` | A Cognito user pool with required MFA, a 14-character password policy, app clients, groups, an optional hosted domain, Lambda triggers, notification-error logs and, on the Plus plan, threat protection with user activity logs. |
| [`security/config`](../modules/aws/security/config) | `account` | AWS Config for one account: a customer managed recorder, delivery channel and retention in every Region of `regions`, plus, in the account that needs them, the delivery bucket (log archive or single account), the organization aggregator, organization or account rules, conformance packs and remediations (delegated administrator), and trusted access and delegated administrator registration (management account). |
| [`security/detective`](../modules/aws/security/detective) | `account` | Amazon Detective for an organization: the management account call designates the Detective administrator in every Region of `regions`; the administrator account call manages the organization behavior graph, auto-enable for new accounts and existing member accounts in the same Regions. With `organization_configuration.enabled = false`, one account's behavior graph, with invited members. |
| [`security/guardduty`](../modules/aws/security/guardduty) | `account` | Amazon GuardDuty for an organization: the management account call enables trusted access and designates the delegated administrator; the delegated administrator call runs the detector, every protection plan, the organization auto-enable configuration, suppression rules and an optional findings export, in every Region of `regions`. With `organization_configuration.enabled = false`, one account's detector and plans. |
| [`security/iam-access-analyzer`](../modules/aws/security/iam-access-analyzer) | `account` | IAM Access Analyzer for an organization, or account analyzers with `organization_configuration.enabled = false`. |
| [`security/iam-role`](../modules/aws/security/iam-role) | `workload` | An IAM role with a trust policy, an inline policy, managed policy attachments, an optional permissions boundary and an optional instance profile. |
| [`security/identity-center`](../modules/aws/security/identity-center) | `organization` | Permission sets, account assignments and optional identity store groups for the organization's IAM Identity Center instance. |
| [`security/inspector`](../modules/aws/security/inspector) | `account` | Amazon Inspector (v2) for an organization, or one account with `organization_configuration.enabled = false`, in every Region of `regions`. |
| [`security/kms`](../modules/aws/security/kms) | `workload` | A customer managed key with an alias, an optional key policy extension and optional multi-Region replicas. |
| [`security/secrets-manager`](../modules/aws/security/secrets-manager) | `workload` | A Secrets Manager secret with an optional write-only value, Lambda rotation, a resource policy and replicas in other Regions. |
| [`security/security-hub`](../modules/aws/security/security-hub) | `account` | Security Hub CSPM for an AWS organization with central configuration, or one account's hub and standards subscriptions in every Region of `regions` with `organization_configuration.enabled = false`. |

### Network

| Module | Scope | What it creates |
| --- | --- | --- |
| [`network/alb`](../modules/aws/network/alb) | `workload` | An Application Load Balancer with its security group, HTTPS and HTTP listeners, target groups, listener rules, extra SNI certificates, S3 access and connection logs and an optional WAF web ACL association. |
| [`network/cloudfront`](../modules/aws/network/cloudfront) | `workload` | A CloudFront distribution with origin access control for S3 and Lambda URL origins, failover origin groups, cache behaviors built from managed or custom policies, standard logging (v2) to a CloudWatch log group in us-east-1 and an optional WAF web ACL association. |
| [`network/nlb`](../modules/aws/network/nlb) | `workload` | A Network Load Balancer (internal by default) with its security group, TCP, UDP, TCP_UDP and TLS listeners (ELB.17 policies), instance, IP and ALB target groups, optional Elastic IPs, TLS access logs and an optional PrivateLink endpoint service. |
| [`network/route53`](../modules/aws/network/route53) | `workload` | A public or private Route 53 hosted zone with its records, health checks, DNS query logging and DNSSEC signing. |
| [`network/security-group`](../modules/aws/network/security-group) | `workload` | A security group with one `aws_vpc_security_group_ingress_rule`/`egress_rule` per source. |
| [`network/vpc`](../modules/aws/network/vpc) | `workload` | A VPC from one CIDR: public, private and intra subnets in up to six Availability Zones, NAT gateways, per-tier route tables and network ACLs, flow logs, VPC endpoints and stripped default resources. |
| [`network/waf`](../modules/aws/network/waf) | `workload` | A WAFv2 web ACL with AWS managed rule groups, rate limits, IP set, geo and regex rules, CloudWatch metrics and logging with sensitive headers redacted. |

### Compute

| Module | Scope | What it creates |
| --- | --- | --- |
| [`compute/batch`](../modules/aws/compute/batch) | `workload` | AWS Batch compute environments (Fargate, Fargate Spot, EC2, Spot), job queues with an optional fair-share scheduling policy, and container job definitions with their job, execution and instance roles, log group and security group. |
| [`compute/ecr`](../modules/aws/compute/ecr) | `workload` | A private ECR repository with immutable tags, scan on push, encryption, an image lifecycle policy and an optional repository policy for cross-account pulls. |
| [`compute/ecs`](../modules/aws/compute/ecs) | `workload` | An ECS cluster with Fargate services: one task definition, service, log group and task role per service, a shared execution role, a task security group, optional Cloud Map discovery or Service Connect, target tracking autoscaling and ECS Exec. |
| [`compute/eks`](../modules/aws/compute/eks) | `workload` | An EKS cluster with managed node groups, optional Fargate profiles, access entries, EKS Pod Identity for workloads, the default add-ons with their own Pod Identity roles, a Load Balancer Controller role and a control plane log group. |
| [`compute/lambda`](../modules/aws/compute/lambda) | `workload` | A Lambda function with everything it needs to run: execution role, log group, alias, optional customer managed key, optional VPC security group, event source mappings, invoke permissions, function URL and async invocation settings. |

### Database

| Module | Scope | What it creates |
| --- | --- | --- |
| [`database/dynamodb`](../modules/aws/database/dynamodb) | `workload` | A DynamoDB table with secure defaults: on-demand capacity, point-in-time recovery for 35 days, deletion protection, server-side encryption with the AWS managed key (or a module or caller key), optional streams, secondary indexes, global table replicas with a strong-consistency witness, Contributor Insights, and target-tracking autoscaling for `PROVISIONED` tables. |
| [`database/elasticache/valkey`](../modules/aws/database/elasticache/valkey) | `workload` | A Valkey replication group (cluster mode disabled) in private subnets: two nodes with automatic failover and Multi-AZ, encryption at rest (AWS managed key, module key or your key) and TLS required, daily snapshots, slow and engine logs in CloudWatch Logs, a security group that admits only the listed sources on the Valkey port, and optional RBAC or a write-only AUTH token. |
| [`database/rds/postgres`](../modules/aws/database/rds/postgres) | `workload` | An RDS for PostgreSQL instance with secure defaults: Multi-AZ, private, storage encrypted with the AWS managed key (or a module or caller key), TLS forced, IAM database authentication, a master password managed in Secrets Manager, 14-day backups, deletion protection, Enhanced Monitoring every 60 seconds, Performance Insights, and `postgresql` and `upgrade` logs in CloudWatch Logs for 365 days. |
| [`database/rds/proxy`](../modules/aws/database/rds/proxy) | `workload` | An RDS Proxy in front of one RDS DB instance: TLS required, clients authenticate with IAM by default, the proxy reads the database credentials from Secrets Manager through its own role, connection pool settings on the default target group, a security group that admits only the listed clients and reaches only the database and AWS APIs, and optional extra read/write endpoints and a pre-created log group. |

### Integration

| Module | Scope | What it creates |
| --- | --- | --- |
| [`integration/api-gateway`](../modules/aws/integration/api-gateway) | `workload` | A REST API built from a generated OpenAPI definition (Lambda, HTTP, AWS and MOCK integrations, Cognito and Lambda authorizers, CORS, models, validators, gateway responses), with its deployment, stage, access and execution logs, method settings, Lambda invoke permissions, WAF association, optional Regional custom domain and optional customer managed key for the logs. |
| [`integration/eventbridge`](../modules/aws/integration/eventbridge) | `workload` | An EventBridge custom bus (or the default bus) with event-pattern rules, targets, EventBridge Scheduler schedules in a schedule group (`scheduler.enabled`), one target role for both, bus logging, an optional archive, an optional bus policy and an optional customer managed key. |
| [`integration/http-api`](../modules/aws/integration/http-api) | `workload` | An API Gateway v2 HTTP API with its `$default` stage, Lambda, HTTP and private (VPC link) integrations, JWT and Lambda authorizers, routes that need an authorizer unless marked public, throttling, JSON access logs, Lambda invoke permissions, an optional VPC link and an optional custom domain with mutual TLS (HTTP API domains accept only `TLS_1_2`, so APIGateway.11 fails by design; use `integration/api-gateway` when that control or WAF is required). |
| [`integration/sqs`](../modules/aws/integration/sqs) | `workload` | An SQS queue with its dead-letter queue, redrive, TLS-only queue policies, publisher grants for EventBridge, SNS and S3, and an optional customer managed key. |
| [`integration/step-functions`](../modules/aws/integration/step-functions) | `workload` | A Step Functions state machine with its execution role, execution log group and optional customer managed key. |

### Storage

| Module | Scope | What it creates |
| --- | --- | --- |
| [`storage/amplify`](../modules/aws/storage/amplify) | `workload` | An Amplify Hosting web app with its branches, custom domains, security response headers and optional app-wide basic auth for previews. |
| [`storage/backup`](../modules/aws/storage/backup) | `account` | AWS Backup for one account, in every Region of `regions`: a vault whose access policy denies manual deletion of recovery points, a plan with daily and monthly rules, an account-wide selection, the service role, an Audit Manager framework, and optional Vault Lock, report plan, notifications and Region settings. |
| [`storage/efs`](../modules/aws/storage/efs) | `workload` | An encrypted EFS file system with one mount target per subnet, a mount target security group that admits NFS only from the listed sources, a file system policy that enforces TLS and squashes root, and access points with an enforced POSIX identity. |
| [`storage/log-bucket`](../modules/aws/storage/log-bucket) | `workload` | An S3 bucket for AWS log delivery, built on `storage/s3`: SSE-S3, versioning, TLS-only policy, public access blocked, logs expired after 365 days, plus only the bucket policy statements each log delivery service needs, one switch per log type. |
| [`storage/s3`](../modules/aws/storage/s3) | `workload` | A private S3 bucket with encryption, versioning, a TLS-only bucket policy and lifecycle rules, plus optional server access logs, event notifications, Object Lock and replication with its own role. |

### Observability

| Module | Scope | What it creates |
| --- | --- | --- |
| [`observability/alarm-routing`](../modules/aws/observability/alarm-routing) | `account` | The notification side of CloudWatch alarms for one account: one KMS-encrypted SNS topic per severity (`critical`, `warning`, `info`) in every Region of `regions`, a topic policy that lets only this account's alarms (and named AWS services) publish, and email and HTTPS subscriptions. |
| [`observability/cloudwatch-alarms`](../modules/aws/observability/cloudwatch-alarms) | `workload` | CloudWatch metric alarms and CloudWatch Logs metric filters: the presets every service module builds in through its `alarms` input, plus custom alarms, log metric filters and the CIS filters. |
| [`observability/log-group`](../modules/aws/observability/log-group) | `workload` | A CloudWatch Logs log group with retention, encryption, class and deletion protection. |

### Governance

| Module | Scope | What it creates |
| --- | --- | --- |
| [`governance/account-baseline`](../modules/aws/governance/account-baseline) | `account` | Account-wide security settings, applied once per account: the IAM password policy, the AWS Support role, alternate contacts and the account S3 public access block, plus per-Region settings in every Region of `regions` through the resource-level `region` argument: EBS encryption by default, EC2 instance metadata defaults, EBS snapshot and AMI block public access, EC2 serial console access off, optional VPC block public access, the API Gateway CloudWatch Logs role, ECR registry scanning and optional ECR replication and pull through cache rules. |
| [`governance/cost-guardrails`](../modules/aws/governance/cost-guardrails) | `account` | Cost guardrails for one account: budgets with tag, service and account filters and actual and forecast alerts, Cost Anomaly Detection with the AWS services monitor (or the existing one) and custom monitors, immediate SNS and daily email anomaly alerts, and cost allocation tag activation in the management account. |
| [`governance/organizations`](../modules/aws/governance/organizations) | `organization` | Organization-wide governance from the management account: trusted access, delegated administrators, centralized root access, an optional policy-management delegation, an optional adopted organization that owns the enabled policy types, and a library of service control policies (SCPs), resource control policies (RCPs), declarative, tag and AI opt-out policies. |
| [`governance/systems-manager`](../modules/aws/governance/systems-manager) | `account` | A Systems Manager baseline for one account in every Region of `regions` (default: the provider Region): service settings (block public document sharing, Automation logging, Default Host Management), Session Manager preferences with session logs, Patch Manager through one Quick Setup patch policy (scan and install schedules, AWS default or custom baselines, local deployment roles), Inventory with an optional resource data sync and central bucket, and weekly SSM Agent updates. |

## Account layouts

| Layout | `organization` modules | `account` modules | `workload` modules |
| --- | --- | --- | --- |
| One account | Only when the account manages an organization: `governance/organizations`, `security/identity-center` | Once, in the account; guardduty, detective, inspector, iam-access-analyzer and security-hub with `organization_configuration = { enabled = false }` | Once per environment; names carry the environment |
| An organization | In the management account | In the management, security tooling and log archive accounts, in the [rollout](organizations-governance.md#rollout) order; `security/config` recording in every workload account | Once per environment, in each workload account |

With `organization_configuration.enabled = false` a security module covers only its own account: no delegated
administrator and no auto-enable for new accounts. The [Terragrunt architecture](terragrunt.md) runs each column in its
own unit.

## How the modules connect

A module creates its own role, security group, log group, optional key and built-in CloudWatch alarms. Everything
else comes in as an ID or ARN from another module's outputs:

| From | Output | Into |
| --- | --- | --- |
| `network/vpc` | `vpc_id`, `private_subnet_ids`, `public_subnet_ids`, `intra_subnet_ids` | `vpc_id` and `subnet_ids` of alb, ecs, eks, lambda, rds, valkey, efs, batch |
| any module with a security group | `security_group_id` | `security_group.ingress_security_group_ids` of the module it calls (alb → ecs, ecs → rds, proxy → rds) |
| `network/route53` | `zone_id` | `security/acm` `validation.zone_id` |
| `security/acm` | `arn` | alb `https_listener.certificate_arn`, nlb TLS `listeners[*].certificate_arn`, cloudfront `acm_certificate_arn`, api-gateway `custom_domain.certificate_arn`, http-api `domain.certificate_arn` |
| `network/alb`, `network/nlb`, `network/cloudfront` | `dns_name`/`domain_name`, `zone_id`/`hosted_zone_id` | route53 `records[*].alias` |
| `network/alb` | `arn` | nlb `target_groups[*].targets` with `target_type = "alb"` (static IPs, PrivateLink) |
| `integration/http-api` | `domain_target_name`, `domain_zone_id` | route53 `records[*].alias` |
| `security/cognito` | `endpoint`, `client_ids` | http-api `authorizers[*].jwt` (`issuer = "https://${endpoint}"`, `audience`) |
| `network/waf` | `arn` | alb, cloudfront, api-gateway `waf = { enabled = true, web_acl_arn = ... }` |
| `storage/log-bucket` | `name` | alb, s3 `access_logs.bucket`; vpc flow logs `s3_bucket_arn` (`arn`) |
| `integration/sqs`, DynamoDB/Kinesis streams | `arn`, `stream_arn` | lambda `event_sources` |
| `integration/eventbridge` | `rule_arns` | lambda `allowed_triggers[*].source_arn`, sqs `allowed_publishers[*].source_arn` |
| `compute/lambda` | `alias_arn`, `invoke_arn` | eventbridge rule and schedule targets, api-gateway routes, http-api `integrations[*].lambda.function_arn`, step-functions `lambda_function_arns` (`arn`) |
| `database/rds/postgres` | `id`, `security_group_id`, `master_user_secret_arn` | rds/proxy `target`, ecs service `secrets` |
| `security/iam-role` | `arn` | eks `pod_identities[*].role_arn`, any `iam_role = { create = false, arn = ... }` |
| `security/kms` | `arn` | any `kms = { key_id = ... }` |
| `observability/alarm-routing` | `topic_arns["<region>"]` | every module's `alarms.topic_arns` (the module's Region; `us-east-1` for cloudfront and `CLOUDFRONT`-scope waf) |
| `observability/alarm-routing` | `topic_arns` | cloudwatch-alarms `notifications.topic_arns`, cost-guardrails `notifications.sns.topic_arn` (with `budgets.amazonaws.com` and `costalerts.amazonaws.com` in `additional_publisher_service_principals`), rds/postgres `event_subscription.sns_topic_arn` (with `events.rds.amazonaws.com`) |
| `database/elasticache/valkey` and any module | `id`, `member_clusters`, `name`, `arn_suffix` | cloudwatch-alarms presets and custom alarms, for alarms that are not built in |

## Examples

Root configurations under [`examples/aws/`](../examples/aws/) wire the modules together and are planned under mocks by
`make verify`:

| Example | Modules |
| --- | --- |
| [`serverless`](../examples/aws/serverless) | cognito, dynamodb, sqs, two lambdas, eventbridge with a nightly schedule, api-gateway, http-api with a Cognito JWT authorizer, step-functions fulfilment flow that invokes the worker alias and is started by the API function; every built-in alarm routed to alarm-routing |
| [`web-service`](../examples/aws/web-service) | core/naming, vpc, kms shared by rds/postgres, rds/proxy logs, valkey, secrets-manager, efs, batch and log-group, two log-buckets (ALB and `aws-waf-logs-` WAF logs), route53, acm, waf on the alb, alb, nlb in front of the alb with a PrivateLink endpoint service, ecs, rds/postgres behind rds/proxy with IAM authentication end to end, security-group for the proxy clients, valkey with its AUTH token in secrets-manager, efs shared by ecs and batch, log-group for audit logs, batch nightly reports scheduled by eventbridge with an sqs dead-letter queue; built-in alarms routed to alarm-routing |
| [`static-site`](../examples/aws/static-site) | core/naming, core/encryption (one us-east-1 key for the edge logs), route53, acm in us-east-1, log-bucket, s3 behind cloudfront with origin access control, waf with CLOUDFRONT scope, amplify for the admin console on a sub-domain |
| [`eks-platform`](../examples/aws/eks-platform) | vpc, ecr, s3, iam-role, eks with node groups, access entries and Pod Identity; node group and NAT alarms routed to alarm-routing |
| [`multi-region`](../examples/aws/multi-region) | the same lambda and s3 in two Regions, proving names never collide; alarm-routing topics in both Regions, each module routed to its own |
| [`security-baseline`](../examples/aws/security-baseline) | organizations with a custom SCP rendered by core/policy-document, identity-center, account-baseline, cloudtrail, config, security-hub, guardduty, detective, inspector and iam-access-analyzer in account-only mode, systems-manager, backup with vault notifications, alarm-routing, cloudwatch-alarms, cost-guardrails |

Account and organization modules run in a fixed order across the management, security tooling and log archive
accounts; [AWS Organizations governance](organizations-governance.md) has the runbook.

## Not built yet

| Priority | Module | Why |
| --- | --- | --- |
| P2 | `database/rds/aurora` | 17 RDS cluster controls; the proxy can already target clusters |
| P2 | `security/iam-github-oidc` | CI deploy roles without IAM users |
| P2 | `integration/sns` | General topics (S3.11 notifications, RDS event subscriptions) |
| P2 | `network/transit-gateway` | Attachments and route tables (EC2.23, .33, .34, .52) |
| P2 | `network/network-firewall` | 10 uncovered controls; needs a firewall subnet tier in vpc |
| P2 | `ai/bedrock` | Guardrails, invocation logging, AgentCore (AI Security standard) |
| P2 | `analytics/opensearch` | 11 OpenSearch controls; vector store for knowledge bases |
| P2 | `streaming/kinesis`, `streaming/firehose` | Streams and log delivery to S3 |
| P2 | `governance/organizations` OUs and accounts | Account vending without Control Tower |
| P2 | `security/ssm-parameters`, `observability/log-centralization` | SecureString parameters; organization log aggregation |
| P3 | Security Lake, Shield Advanced, VPN and Client VPN, Private CA, Verified Access | Optional security services |
| P3 | SageMaker, MSK, Glue/Athena/Lake Formation, other RDS engines, Redshift, DocumentDB, Neptune | Data and ML workloads on demand |
| P3 | Dashboards, Synthetics, Resource Groups, Service Quotas, Pipes | Operations |

Macie, Firewall Manager, Audit Manager and Control Tower are out of scope by decision.

[Documentation index](../README.md#documentation)
