# Migration Guide

This document records the required consumer actions when upgrading between releases of this
library. It is the source of truth for upgrade behaviour: if a release is not described
here, upgrading to it requires no action beyond changing the `?ref=` tag.

## 1.2.0

No consumer migration required. Terraform module interfaces and variable contracts remain unchanged. CI verification container is upgraded to `grootantech/toolkit:1.1.0` and reusable workflows are pinned to `github-ci-library` `@1.3.1`.

## 1.1.1

No migration is required. Only the PR verification container reference changes.

## 1.1.0

No migration is required. Terraform module interfaces remain unchanged.

## 1.0.0

No migration is required for the initial release.
