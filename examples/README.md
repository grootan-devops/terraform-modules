# Examples

Root configurations that wire the AWS modules together. Each one has a `tests/plan.tftest.hcl` that plans the whole
scenario with a mocked AWS provider, so every ARN and ID that one module passes to another is unknown at plan time:
the hard case for a real first apply. `make verify` runs them.

| Example | Proves |
| --- | --- |
| [`aws/serverless`](aws/serverless) | Lambda, SQS, DynamoDB streams, EventBridge rules, targets and a Scheduler schedule, a REST API and an HTTP API behind Cognito authorizers; queue policies that point back at rules without a cycle |
| [`aws/web-service`](aws/web-service) | VPC, Route 53, ACM, an internet-facing ALB with access logs, ECS behind it and Postgres behind ECS, wired by security group; an internal NLB with the ALB as target behind a PrivateLink endpoint service |
| [`aws/eks-platform`](aws/eks-platform) | VPC, ECR, S3, EKS with node groups, an access entry and two Pod Identity workloads (module-built and caller-built roles) |
| [`aws/multi-region`](aws/multi-region) | The same function and bucket in two Regions: function names repeat, IAM role and bucket names do not |
| [`aws/security-baseline`](aws/security-baseline) | The account and organization modules together, with budget and anomaly alerts on the alarm-routing topic |

The examples use relative module paths because they live in this repository. A stack outside it uses the pinned Git
source shown in each module README.
