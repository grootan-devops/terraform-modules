# Module README standard

Every module ships a `README.md` with these sections, in this order. The API tables are
generated from source, so they are kept in dedicated sections that tooling can refresh
without touching the hand-written narrative around them.

```text
# <Provider> <Resource> Module
<what it provisions, its operational role — no marketing, no project names>

### Architecture & Managed Resources     hand-written
### Security & Compliance Guardrails     hand-written
## Requirements & Providers              generated from versions.tf
## Usage Examples                        hand-written
### Minimal Working Example
### Complete Production Example
## Inputs Specification                  generated from variables.tf
## Outputs Specification                 generated from outputs.tf
```

Table conventions:

- **Inputs** — a mandatory variable sets `Default` to `**Required**` and `Required` to `Yes`;
  an optional one shows the literal default and `No`. Structural types are written compactly
  (`object({...})`, `list(object({...}))`).
- **Outputs** — the `Sensitive` column is `Yes` or `No`, never blank.

Modules needing more than this append sections; they do not drop any. Migration notes,
ownership and lifecycle boundaries, and known caveats are the common additions.

Every usage example references the public Git source with `?ref=<version>`, which shows the
syntax: a consumer pins the release their stack uses, so an example needs no change at a
release. `tests/verify_modules.py` rejects a module README whose examples use a relative
path, a branch or a pre-release; it also accepts a stable SemVer tag.

Start the architecture diagram from [docs/assets/architecture-template.svg](assets/architecture-template.svg)
(a PNG export sits beside it).

[Documentation index](../README.md#documentation)
