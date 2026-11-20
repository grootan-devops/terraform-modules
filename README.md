# Terraform Modules Library

[Security](./SECURITY.md) · [Contributing](./CONTRIBUTING.md)

Production-grade, modular Terraform library for provisioning secure, compliant cloud infrastructure,
and the OneUptime monitoring that watches it.

## Documentation

| Task | Read |
| --- | --- |
| Find a module and see how the repository is laid out | [AWS catalog](docs/AWS.md), [Repository layout](docs/repository-layout.md) |
| Wire modules together | [How the modules connect](docs/AWS.md#how-the-modules-connect), [Examples](examples/aws/) |
| Consume modules in a Terraform or Terragrunt stack | [Consuming modules](docs/consumption.md), [Terragrunt architecture](docs/terragrunt.md) |
| Design a module's public API | [Module contract](docs/module-contract.md), [Provider schema](docs/provider-schema.md) |
| Name resources and emit tags | [Naming and tagging](docs/naming-and-tagging.md), [Other providers](docs/other-providers.md) |
| Choose security controls | [Security baselines](docs/security-baselines.md), [AWS catalog](docs/AWS.md), [OneUptime catalog](docs/ONEUPTIME.md), [Other providers](docs/other-providers.md) |
| Govern an AWS organization and assess compliance | [Compliance documentation](docs/compliance/README.md), [AWS Organizations governance](docs/compliance/aws-organizations-governance.md), [Security baseline and roadmap](docs/compliance/aws-security-baseline.md) |
| Write a module README | [Module README standard](docs/module-readme.md) |
| Classify a change and release it | [Versioning and releases](docs/versioning.md), [MIGRATION.md](MIGRATION.md) |
| Test, scan and verify a module | [Development and testing](docs/testing.md), [Scanner suppressions](docs/compliance/scanner-suppressions.md) |
| Monitor a stack with OneUptime | [OneUptime catalog](docs/ONEUPTIME.md), [OneUptime module](modules/oneuptime/README.md), [Other providers](docs/other-providers.md#oneuptime) |

## Requirements

AWS modules: Terraform `>= 1.17.0` and `hashicorp/aws` `>= 6.73.0`. OneUptime modules: Terraform `>= 1.9.0` and
`oneuptime/oneuptime` `>= 13.0.6, < 14.0.0`. Each module's README lists its bounds under Requirements & Providers.

## Reading with an AI assistant

Start here, select the relevant task, and follow only the linked pages needed for it.
Resolve relative links from the containing document and keep every page on the same
branch, tag, commit or local checkout, including uncommitted edits. Do not concatenate `docs/`
or the module READMEs. Read the release a stack pins in its module `source` (`?ref=`), or the
latest release tag for a new stack; an example pin shows the syntax and does not select a release.
For upgrades, also read [MIGRATION.md](MIGRATION.md) and [CHANGELOG.md](CHANGELOG.md).

## License

Copyright 2026 Grootan Technologies Pvt Ltd.

Licensed under the [GNU Affero General Public License v3.0](./LICENSE.md)
(`AGPL-3.0-only`). External contributions are not accepted; see
[CONTRIBUTING.md](./CONTRIBUTING.md) for bug and security reporting.
