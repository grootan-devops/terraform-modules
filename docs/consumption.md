# Consuming modules

How an infrastructure repository composes versioned modules into environments. The layout and
examples are in README §2 and §3; these are the rules around them.

## Module sources and versions

- Pin a new remote call to an exact Registry version or a Git release tag (or commit); never a
  moving branch. Verify the source and revision exist before using them.
- Read the module's README, inputs, outputs, provider and Terraform requirements, and the
  migration notes at that same revision; read the implementation where the documentation is
  incomplete, and check that the capabilities and outputs you need exist.
- Use a local module path only when the consuming project owns that module. Never copy a
  module's implementation into the consumer.
- On an upgrade, read the migration notes across every version in between, and keep module
  addresses, inputs and state relationships unless the change requires a migration.

## Composition

- A new project uses the Terragrunt layout in §3: a shared `root.hcl`, one `resources/`
  composition root, and one `<environment>/terragrunt.hcl` per environment that includes
  `root.hcl`, sources `resources/` and supplies the inputs. A project already on native
  Terraform keeps its layout unless a migration is asked for.
- Keep one composition stack and one state per environment. If independently operated
  components would make one state too broad, raise that trade-off; never split an existing
  state silently.
- `resources/` holds the module calls, the provider requirements and a single provider
  configuration, variables, outputs, locals and supporting data sources. Connect modules
  through their documented outputs; keep non-secret environment values in the environment's
  `terragrunt.hcl`.
- New work adds module calls, not `resource` blocks. Existing direct resources (such as the
  IAM and DNS files in §3) stay as they are, and a capability no module provides is reported as
  a module gap.

## State, providers and secrets

- For an existing environment, identify its backend and exact state key before editing, and
  keep them; no path rewrites or renamed state objects. A new environment gets a known backend
  with locking and recovery and a stable, distinct state key; on S3, use native lockfiles and
  bucket versioning where the Terraform version supports them. A stack never creates its own
  backend.
- Configure each provider once in the Terraform root, parameterising the region and other
  per-environment settings; add aliases only when a module requires them. Never copy example
  account IDs, regions, role names or provider override files into a new project.
- No literal credentials or secret values in tracked Terraform, Terragrunt, variable files,
  examples or logs: use the project's secret delivery, and mark secret variables and outputs
  `sensitive`. Plans and state still contain secret values.
- Keep `.terraform/`, state files and saved plans out of version control, and commit the
  `.terraform.lock.hcl` of every root so provider selections are reproducible.

## Validation

Format and check the changed Terraform and Terragrunt files. Where dependencies are available,
`terraform init -backend=false` and `terraform validate` the composition root, and validate
the Terragrunt HCL of the affected environments. Check module source resolution, required
inputs, provider compatibility, lock files and unchanged state keys. A plan is reviewed for
its create, update, replace and delete actions before anything is applied.

[Documentation index](../README.md#documentation)
