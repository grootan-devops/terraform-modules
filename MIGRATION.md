# Migration Guide

This document records the required consumer actions when upgrading between releases of this
library. It is the source of truth for upgrade behaviour: if a release is not described
here, upgrading to it requires no action beyond changing the `?ref=` tag.

To upgrade, apply every section after your pinned version up to the target, oldest first.
Newer sections are split into **Required** (the upgrade breaks or misbehaves without it),
**Recommended** (aligns an existing stack with the current standards) and **Verify**.

## 1.5.0

### Required

No state migration required. AWS module interfaces, resource addresses and runtime behaviour are
unchanged; change the `?ref=` tag only. This release adds `modules/oneuptime`.

### Recommended

- A stack running a local copy of the OneUptime module can point its module blocks at
  `git::https://github.com/grootan-devops/terraform-modules.git//modules/oneuptime?ref=1.5.0`
  and run `terraform init -upgrade`. Resource addresses do not change while the module block
  keeps its name.
- The published module needs Terraform `>= 1.9.0` and `oneuptime/oneuptime`
  `>= 13.0.6, < 14.0.0`. Keep the stack's own provider pin inside that range.
- The Teams notification template's `dashboard_url` now defaults to `https://oneuptime.com`.
  Set it explicitly for a self-hosted instance.

### Verify

- A plan for each environment shows no changes after the `?ref=` change.
- A stack moved from a local copy shows no changes once `dashboard_url` is set to its instance.

## 1.4.0

No migration is required. This release only updates dependencies.

## 1.3.0

### Required

No state migration required. Module interfaces, resource addresses and runtime behaviour are
unchanged; change the `?ref=` tag only. This release adds the documentation index and the
consumption, provider-schema, state-migration, testing and other-provider guides.

### Recommended

None.

### Verify

- A plan for each environment shows no changes after the `?ref=` change.

## 1.2.0

No state migration required. Terraform module interfaces and runtime behavior remain unchanged. CI verification container is upgraded to `grootantech/toolkit:1.1.0` and reusable workflows are pinned to `github-ci-library` `@1.3.1`. The S3 `public_access_block` input remains accepted but has always been ignored; remove caller overrides that assume it can disable public access blocking.

KMS, Batch, EKS cluster, and RDS/Postgres no longer declare six unused context data sources. No managed resource address changes; consumers with existing state should review their next plan for data-source entry removal.

## 1.1.1

No migration is required. Only the PR verification container reference changes.

## 1.1.0

No migration is required. Terraform module interfaces remain unchanged.

## 1.0.0

No migration is required for the initial release.
