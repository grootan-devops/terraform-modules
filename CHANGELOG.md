# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
- The OneUptime module and its submodules require Terraform `>= 1.9.0` and `oneuptime/oneuptime` `>= 13.0.6, < 14.0.0`; 14.x removes the `name` argument of the `oneuptime_domain` data source.
- README §1, §4 and §9 describe the OneUptime family and the 32 module directories the gate now covers.
- Pinned repository CI reusable workflow callers to `github-ci-library` `@1.6.1`.
- `tests/verify_modules.py` fails a module without a `tests/*.tftest.hcl` suite.
- A test file no longer raises a module's `required_version`: test files load only under `terraform test`, in the CI toolkit image. README §4.4 and `docs/testing.md` say so, and `docs/testing.md` lists what a suite covers.

### Fixed

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
