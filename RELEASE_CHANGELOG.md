### Added
- `docs/repository-layout.md`, `docs/terragrunt.md`, `docs/module-contract.md`, `docs/naming-and-tagging.md`, `docs/security-baselines.md`, `docs/module-readme.md` and `docs/versioning.md`: the README's sections 1 and 3–8, one task per page. Section 2 joins `docs/consumption.md` and section 9 `docs/testing.md`, now titled Development and testing.
- A Requirements section in the README (Terraform `>= 1.9.0`; provider bounds in each module's README) and, in `docs/versioning.md`, the deprecation policy: announced in the changelog and migration guide, and kept through at least the next MINOR release where practical.
### Changed
- The README is a slim documentation index: the task table, requirements, a "Reading with an AI assistant" section that says which release to read, and the license. Reading the index no longer means reading every standard.
- The README header drops its hand-kept release line and the link to the ai-skills compatibility page: the tag is the release, and this library documents its own versioning and requirements.
- Examples in the docs and the module READMEs pin `?ref=<version>`, which shows the syntax, instead of the current release; a release no longer re-pins every example. `tests/verify_modules.py` accepts `<version>` as well as a stable SemVer tag, and still rejects relative paths, branches and pre-releases.
- The "current state" callouts in the module contract and naming pages describe the release they ship in rather than naming it.
