# Migration Guide

This document records the required consumer actions when upgrading between releases of this
library. It is the source of truth for upgrade behaviour: if a release is not described
here, upgrading to it requires no action beyond changing the `?ref=` tag.

## 1.2.0

No state migration required. Terraform module interfaces and runtime behavior remain unchanged. CI verification container is upgraded to `grootantech/toolkit:1.1.0` and reusable workflows are pinned to `github-ci-library` `@1.3.1`. The S3 `public_access_block` input remains accepted but has always been ignored; remove caller overrides that assume it can disable public access blocking.

KMS, Batch, EKS cluster, and RDS/Postgres no longer declare six unused context data sources. No managed resource address changes; consumers with existing state should review their next plan for data-source entry removal.

## 1.1.1

No migration is required. Only the PR verification container reference changes.

## 1.1.0

No migration is required. Terraform module interfaces remain unchanged.

## 1.0.0

No migration is required for the initial release.
