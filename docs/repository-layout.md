# Repository layout

Modules are grouped by provider and domain under `modules/`:

```text
terraform-modules/
├── .gitignore                          # Artifact exclusions
├── README.md                           # Documentation index
├── docs/
│   ├── AWS.md                          # AWS architecture, CIS baselines & module catalog
│   ├── ONEUPTIME.md                    # OneUptime architecture, monitoring baselines & catalog
│   ├── consumption.md                  # Calling modules and the rules for composing environments
│   ├── module-contract.md              # Variables, outputs, providers and version constraints
│   ├── module-readme.md                # The README every module ships
│   ├── naming-and-tagging.md           # Deterministic names, length limits and governance tags
│   ├── other-providers.md              # Naming bounds and capability tables beyond AWS
│   ├── provider-schema.md              # Deriving inputs and outputs from the schema
│   ├── repository-layout.md            # This layout
│   ├── security-baselines.md           # Capability-aware controls, keys, transport and credentials
│   ├── state-migration.md              # Moved blocks and the release plan gate
│   ├── terragrunt.md                   # The Terragrunt live-repository layout
│   ├── testing.md                      # make verify, the gate, test levels and test shapes
│   ├── versioning.md                   # SemVer levels, deprecations and releases
│   └── assets/                         # Architecture diagram template
└── modules/
    ├── aws/                            # AWS infrastructure modules
    │   ├── compute/                    # batch, ecs, eks, lambda
    │   ├── database/                   # dynamodb, elasticache/valkey, rds/postgres, rds/proxy
    │   ├── integration/                # api-gateway, eventbridge, sqs, step-functions
    │   ├── network/                    # alb, cloudfront, vpc, waf
    │   ├── security/                   # cognito, kms, secrets-manager
    │   └── storage/                    # amplify, efs, s3
    └── oneuptime/                      # OneUptime monitors, on-call, status pages, workflows
        └── modules/                    # internal areas, and the teams-notification template
```

[Documentation index](../README.md#documentation)
