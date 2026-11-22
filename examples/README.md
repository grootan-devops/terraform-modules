# Examples

Root configurations that wire the modules together. Each one has a `tests/plan.tftest.hcl` that plans the whole
scenario with a mocked provider, so every ARN and ID that one module passes to another is unknown at plan time:
the hard case for a real first apply. `make verify` runs them.

| Example | Proves |
| --- | --- |
| [`aws/serverless`](aws/serverless) | Lambda, SQS, DynamoDB streams, EventBridge rules, targets and a Scheduler schedule, a REST API and an HTTP API behind Cognito authorizers, a Step Functions fulfilment workflow; queue policies that point back at rules without a cycle |
| [`aws/web-service`](aws/web-service) | VPC, Route 53, ACM, an internet-facing ALB with WAF and access logs, ECS behind it, Postgres behind an IAM-auth RDS Proxy, a Valkey cache, an app secret, shared EFS storage and nightly Batch jobs, all on one shared KMS key and wired by security group; an internal NLB with the ALB as target behind a PrivateLink endpoint service |
| [`aws/eks-platform`](aws/eks-platform) | VPC, ECR, S3, EKS with node groups, an access entry and two Pod Identity workloads (module-built and caller-built roles) |
| [`aws/static-site`](aws/static-site) | An S3 site behind CloudFront with a CLOUDFRONT-scope WAF, a us-east-1 certificate, Route 53 aliases and an Amplify admin console |
| [`aws/multi-region`](aws/multi-region) | The same function and bucket in two Regions: function names repeat, IAM role and bucket names do not |
| [`aws/security-baseline`](aws/security-baseline) | Every account and organization module in a one-account organization: Identity Center, a custom SCP, threat detection, AWS Backup and Systems Manager, with budget, anomaly and backup alerts on the alarm-routing topics |
| [`oneuptime/platform`](oneuptime/platform) | Every OneUptime area in one inventory: labels and teams (one component owned by two groups), every monitor type with generated criteria, alert and incident rules, on-call with schedules where enabled, a public and a private status page, custom workflows and the Teams notification template |

Together they call every AWS module at least once. The examples use relative module paths because they live in this repository. A stack outside it uses the pinned Git
source shown in each module README.
