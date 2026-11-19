# Development and testing

## Verify a change

```bash
make verify      # unit tests + contract checks + fmt + init + validate + terraform test
make contracts   # unit tests + contract checks, no Terraform binary required
make validate    # contract checks + Terraform checks only
make verify MODULES="modules/aws/compute/lambda modules/aws/security/kms"   # a subset
```

`tests/verify_modules.py` is the gate. For every module it asserts:

- `required_version`: exactly `>= 1.17.0` on AWS, at least `>= 1.9.0` on OneUptime; and the provider of its family
  (`hashicorp/aws`, `oneuptime/oneuptime`) wherever it declares a resource or data source.
- The family's governance variables are declared: `application` and `environment` on AWS,
  `application` on OneUptime.
- A `locals` block carrying naming and tag governance (AWS) or label governance (OneUptime)
  exists.
- Data sources declared in root Terraform files are referenced by module logic.
- A `README.md` exists whose examples use the public Git source with `?ref=<version>` or a
  stable SemVer tag.
  An internal submodule — a module inside another module's directory, such as an area of
  `modules/oneuptime` — needs a README, and takes its governance variables and published
  examples from the parent.
- No Markdown anywhere in the repository points a module `source` at a relative path.
- A native test suite exists under `tests/*.tftest.hcl`.
- Every `#trivy:ignore:<check>` in the module names a check its README explains.
- `terraform fmt -check -recursive`, `terraform init -backend=false`, and
  `terraform validate` all pass, and `terraform test` passes.

Individual commands, run inside a module directory:

```bash
terraform fmt -recursive .
terraform init -backend=false
terraform validate
terraform test          # tests/*.tftest.hcl; the suites need Terraform >= 1.10 (state_key)
```

## Repository checks beside the module gate

`make contracts` also runs this unit test:

- `tests/test_cloudwatch_alarms_contract.py`: the alarms module creates no destination resources and turns actions on
  only through `var.notifications` (off by default, caller-supplied topic ARNs only); the alarm-routing module creates
  only KMS-encrypted SNS topics, topic policies and email/HTTPS subscriptions; no example or test names a real endpoint.

## CI

`.github/workflows/pr.yml` runs, through github-ci-library:

- `terraform` (`terraform.yml`): `terraform fmt -check`, `validate` and TFLint over every module.
- `iac-scan` (`scan.yml`): Trivy IaC scan of `modules/`.
- `lint`, `check`, `secret-scan`: Markdown, changelog and release guards, secret scanning.

and, in the repository, `verify` (`make verify` in `grootantech/toolkit:2.1.0`): the Python unit tests, the contract
checks and every module's `terraform test`. A scanner finding is fixed in the module; when the provider or the
service leaves no fix, it is suppressed inline on that one resource and the module README's Security & Compliance
Guardrails section says why. There is no repository-wide skip list.

## Test levels

| Level | What it covers | State today |
| :---: | --- | --- |
| 0 | `fmt`, `validate`, contract checks | Enforced by `make verify` on every module directory |
| 1 | Static security and secret scanning | The PR jobs `terraform` (TFLint) and `iac-scan` (Trivy); secret scanning by the shared `secret-scanning.yml` workflow |
| 2 | `terraform test` with `mock_provider`, no credentials | Every module directory, required by the gate: naming, tags, security defaults, parameters, validation |
| 3 | Cross-module wiring | `examples/aws/*` planned under mocks by `make verify` |
| 4 | Terratest apply/idempotency/destroy against real cloud | Not wired in |
| 5 | Terraform core and provider version matrix | Not wired in |

Level 2 runs offline in seconds, and `make verify` fails a module without it. What a suite
covers and the test shapes are below.

## Native test — `tests/unit.tftest.hcl`

Every module ships one, and `tests/verify_modules.py` fails a module without it. `mock_provider` needs no cloud
credentials; `make verify` runs `terraform test` in every module directory.
[`modules/aws/compute/lambda/tests/unit.tftest.hcl`](../modules/aws/compute/lambda/tests/unit.tftest.hcl) is the
reference suite. A suite covers:

1. **Names**: the base name, Region and account suffixes on IAM and S3 names, truncation at each limit.
2. **Tags**: caller tags kept, governance tags win, `Name` overrides on sub-resources.
3. **Secure defaults**: encryption, TLS, public access, deletion protection, logging and retention.
4. **Encryption modes**: no `kms` input (AWS managed key), `kms = { create = true }` in a `command = plan` run (the key
   ARN is unknown, so this proves the module plans) and in an `apply` run, and `kms = { key_id = ... }`.
5. **Wiring**: security group rules, IAM statements (through `module.role[0].policy_json`), log group settings.
6. **Switches**: every optional feature off by default and on when enabled.
7. **Validation**: one `expect_failures` run per `validation` block.
8. **Built-in alarms**: the default alarm keys and names, `alarms = { enabled = false }` creating none, an override
   that changes one threshold and disables one alarm (through `module.alarms[0].alarm_settings`), `topic_arns` routing
   by severity (`module.alarms[0].alarm_routes`) and the keys at plan with unknown ARNs.

```hcl
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }

  mock_data "aws_region" {
    defaults = { region = "eu-west-1" }
  }

  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
}

variables {
  application = "core"
  environment = "prod"
  name        = "orders"
}

run "module_key_is_planned_safely" {
  command = plan

  variables {
    kms = { create = true }
  }

  assert {
    condition     = module.encryption.created
    error_message = "kms.create must plan without knowing the key ARN."
  }
}

run "rejects_invalid_environment" {
  command = plan

  variables {
    environment = "PROD"
  }

  expect_failures = [var.environment]
}
```

### Mock mechanics

- A run sees the module's own resources, its outputs and its child modules' **outputs**, not resources inside a
  child module. That is why the building blocks output their rendered policies, rule IDs and effective settings.
- Computed values are unknown at `plan`. Use `command = apply` (mocked, in memory) to read them, and give ARNs that
  are parsed or asserted a valid shape with `mock_resource "<type>" { defaults = { ... } }`.
- Runs share state. A run that must create fresh resources after an `apply` run sets its own `state_key`; otherwise
  `ignore_changes` keeps the earlier values.
- Locally, share one provider download with `TF_PLUGIN_CACHE_DIR` and
  `TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE=true`.

[`modules/oneuptime/tests/unit.tftest.hcl`](../modules/oneuptime/tests/unit.tftest.hcl) is the same shape against
`mock_provider "oneuptime"`.

## Cross-module examples — `examples/`

`examples/aws/<scenario>/` are root configurations that wire several modules together with relative sources, each
with a `tests/*.tftest.hcl` that plans the whole scenario under mocks. They prove that one module's outputs fit the
next module's inputs; `make verify` runs them with the modules.

## Terratest — `test/<module>_test.go`

For behaviour only a live API shows. It costs real money and time, so add it on request, not
by default. It needs a fixture such as `examples/minimal`, which this repository does not ship
yet, so the fixture comes with the test.

```go
package test

import (
    "testing"

    "github.com/gruntwork-io/terratest/modules/terraform"
    "github.com/stretchr/testify/assert"
)

func TestModuleLifecycle(t *testing.T) {
    t.Parallel()

    terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
        TerraformDir: "../examples/minimal",
        Vars: map[string]interface{}{
            "application": "testapp",
            "environment": "dev",
        },
    })

    defer terraform.Destroy(t, terraformOptions)

    terraform.InitAndApply(t, terraformOptions)

    outputID := terraform.Output(t, terraformOptions, "id")
    assert.NotEmpty(t, outputID)

    // A second plan must be empty, or the module is not idempotent.
    exitCode := terraform.PlanExitCode(t, terraformOptions)
    assert.Equal(t, 0, exitCode, "expected zero changes on the second plan")
}
```

[Documentation index](../README.md#documentation)
