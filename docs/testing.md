# Module tests

The test levels and which of them this repository runs are in the README §9. This page holds
the test shapes a module adds.

## Native test — `tests/unit.tftest.hcl`

Every module ships one, and `tests/verify_modules.py` fails a module without it. `mock_provider`
needs no cloud credentials or live API calls; provider installation may still need network
access. `make verify` runs `terraform test` in every module directory. A test file does not
raise the module's `required_version`: it loads only under `terraform test`, in the CI toolkit
image.

A suite covers, for every resource the module manages:

1. **Naming** — `<application>-<environment>-<name>`, the fallback when `name` is null or empty,
   and any truncation or override the module implements.
2. **Tags** — `Application`, `Environment` and `Name` on every taggable resource, caller tags
   kept, and sub-resource `Name` overrides. Assert governance precedence only on a module that
   merges governance tags last (README §5.3), and never assert the overwrite.
3. **Security defaults** — KMS wiring, encryption, TLS, public access, deletion protection,
   logging and retention: whatever the module enforces.
4. **Parameters** — the shipped defaults, a run that overrides several optional inputs, and
   optional features off by default and created when enabled.
5. **Validation** — one `expect_failures` run per `validation` block.

```hcl
mock_provider "aws" {}

variables {
  application = "core"
  environment = "prod"
  name        = "test-resource"
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
}

run "verify_security_defaults" {
  command = plan

  assert {
    condition     = aws_s3_bucket.this.bucket == "core-prod-test-resource"
    error_message = "Bucket name did not match the expected rendered name."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).kms_master_key_id == var.kms_key_arn
    error_message = "KMS encryption key was not assigned."
  }
}

run "verify_invalid_environment_fails" {
  command = plan

  variables {
    environment = "INVALID_UPPERCASE"
  }

  expect_failures = [var.environment]
}
```

Cover both shapes, the happy path and a rejected input: a suite that only asserts the happy
path still passes after someone deletes a `validation` block. Prove a suite bites by breaking
the module in a scratch copy and watching a run fail.

### Mock mechanics

- A run sees the module's own resources, its outputs and its child modules' **outputs** — not
  resources inside a child module. An internal submodule is tested in its own directory with
  the normalized inputs its parent would pass.
- The mock returns random strings for computed values, which are unknown at `plan`. Use
  `command = apply` to read them; it builds state in memory only.
- The provider still validates arguments under the mock. Give computed ARNs and names that feed
  another resource a valid shape with `mock_resource "<type>" { defaults = { ... } }`, and data
  sources whose output is parsed with `mock_data` (`aws_iam_policy_document.json`,
  `aws_caller_identity.account_id`, `aws_region`).
- A module with `configuration_aliases` needs one `mock_provider` per alias.
- Give each `command = apply` run its own `state_key`, so its state cannot leak into a later
  `plan` run.
- Locally, share one provider download across modules with `TF_PLUGIN_CACHE_DIR` and
  `TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE=true`; without the second, an init with no
  lock file downloads the provider again.

[`modules/oneuptime/tests/unit.tftest.hcl`](../modules/oneuptime/tests/unit.tftest.hcl) is the
same shape against `mock_provider "oneuptime"`; each OneUptime submodule has its own suite
under `modules/oneuptime/modules/<area>/tests/`.

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
