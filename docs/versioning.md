# Versioning and releases

Modules follow [Semantic Versioning 2.0.0](https://semver.org/) as one library: the
repository tag is the version, and every module moves with it.

| Level | Triggers | Examples |
| :---: | --- | --- |
| **PATCH** `x.y.Z` | Fixes and internal refactors with zero behavioural or state change for callers. | Documentation fix; `terraform fmt`; a local expression rewritten. |
| **MINOR** `x.Y.0` | Backward-compatible additions. | A new optional variable with a safe default; a new output; dropping an artificial upper version bound. |
| **MAJOR** `X.0.0` | Any break in the public surface. | Renaming or removing a variable or output; changing a default that alters live infrastructure; moving a resource address without a `moved` block; raising the minimum provider to an incompatible major. |

Anything at MAJOR — and any MINOR that changes observable behaviour — requires an entry in
[MIGRATION.md](../MIGRATION.md) before release. Release notes go in
[CHANGELOG.md](../CHANGELOG.md). Moving a resource address, and the plan review that gates a
risky release, are in [State migration](state-migration.md).

Consumers pin an exact release tag (or Registry version); a branch is never a release
reference. A deprecated variable, output or behaviour is announced in the changelog and the
migration guide and, where practical, kept through at least the next MINOR release before
it goes. Security, correctness or provider requirements may remove unsafe behaviour sooner.
A page describes the release it ships in: what changed between releases belongs in the
changelog and migration guide.

[Documentation index](../README.md#documentation)
