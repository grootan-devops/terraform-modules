# Repository layout

Modules are grouped by provider and domain under `modules/`:

```text
terraform-modules/
├── .github/workflows/                  # CI through github-ci-library
├── README.md                           # Documentation index
├── Makefile                            # contracts, validate, test, verify (MODULES= filter)
├── docs/
│   ├── AWS.md                          # AWS module catalog, wiring, examples and roadmap
│   ├── ONEUPTIME.md                    # OneUptime architecture, monitoring baselines & catalog
│   ├── consumption.md                  # Calling modules and the rules for composing environments
│   ├── module-contract.md              # The AWS module standard
│   ├── module-readme.md                # The README every module ships
│   ├── naming-and-tagging.md           # Collision-free names, length limits and governance tags
│   ├── organizations-governance.md     # Account model, policy types, rollout and break-glass for an organization
│   ├── other-providers.md              # Naming bounds and capability tables beyond AWS
│   ├── provider-schema.md              # Deriving inputs and outputs from the schema
│   ├── repository-layout.md            # This layout
│   ├── security-baselines.md           # Capability-aware controls, keys, network, IAM and credentials
│   ├── terragrunt.md                   # The Terragrunt live-repository layout
│   ├── testing.md                      # make verify, the gate, test levels and test shapes
│   └── versioning.md                   # SemVer levels and releases
├── examples/
│   ├── aws/                            # serverless, web-service, static-site, eks-platform, multi-region, security-baseline
│   └── oneuptime/                      # platform: every OneUptime area in one inventory
├── modules/
│   ├── aws/
│   │   ├── core/                       # naming, encryption, policy-document (helpers)
│   │   ├── compute/                    # batch, ecr, ecs, eks, lambda
│   │   ├── database/                   # dynamodb, elasticache/valkey, rds/postgres, rds/proxy
│   │   ├── governance/                 # account-baseline, cost-guardrails, organizations, systems-manager
│   │   ├── integration/                # api-gateway, eventbridge (with Scheduler), http-api, sqs, step-functions
│   │   ├── network/                    # alb, cloudfront, nlb, route53, security-group, vpc, waf
│   │   ├── observability/              # alarm-routing, cloudwatch-alarms, log-group
│   │   ├── security/                   # acm, cloudtrail, cognito, config, detective, guardduty, iam-access-analyzer,
│   │   │                               # iam-role, identity-center, inspector, kms, secrets-manager, security-hub
│   │   └── storage/                    # amplify, backup, efs, log-bucket, s3
│   └── oneuptime/                      # OneUptime monitors, on-call, status pages, workflows
└── tests/                              # Contract gate and alarm checks
```

[Documentation index](../README.md#documentation)
