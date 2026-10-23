# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and
this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.0] - 2026-10-23

### Added

- `modules/oneuptime`, which turns an inventory of components, owning groups and monitors into OneUptime labels, teams, monitors, alert and incident rules, on-call policies, status pages and workflows, with one internal submodule per area under `modules/oneuptime/modules/`.
- Monitor probe steps and Offline / Degraded / Operational criteria generated from `monitor_type` for 15 monitor types, with module, stack and per-item defaults through `monitor_defaults` and `status_page_defaults`.
- Plan-time validation that names the offending monitors, status pages and workflows when inputs reference each other inconsistently.
- `modules/oneuptime/modules/workflows-templates/teams-notification`, which builds the five standard Microsoft Teams notification workflows without creating resources.
- A mock-provider `terraform test` suite in `modules/oneuptime/tests/`, run by `make verify`.
- The OneUptime module guide, `modules/oneuptime/CONVENTIONS.md`, a OneUptime section in `docs/other-providers.md`, and a documentation index row.

### Changed

- `tests/verify_modules.py` checks each provider family against its own contract: AWS modules keep `hashicorp/aws`, `application`, `environment` and tag governance; OneUptime modules need `oneuptime/oneuptime`, `application` and label governance. Checks on AWS modules are unchanged.
- Internal submodules under a module's own `modules/` directory need a README and take their governance variables and published examples from the parent.
- The OneUptime module and its submodules require Terraform `>= 1.9.0` and `oneuptime/oneuptime` `>= 13.0.6, < 14.0.0`; 14.x removes the `name` argument of the `oneuptime_domain` data source.
- README §1, §4 and §9 describe the OneUptime family and the 32 module directories the gate now covers.

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
