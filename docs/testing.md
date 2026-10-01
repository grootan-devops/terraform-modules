# Module tests

The test levels and which of them this repository runs are in the README §9. This page holds
the test shapes a module adds.

## Native test — `tests/unit.tftest.hcl`

`mock_provider` needs no cloud credentials or live API calls; provider installation may still
need network access. Add this level with every new module: `make verify` runs `terraform test`
in any module directory containing a `*.tftest.hcl`. Shipping one raises that module's
`required_version` to `>= 1.6.0`.

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
    condition     = aws_s3_bucket_server_side_encryption_configuration.this.rule[0].apply_server_side_encryption_by_default[0].kms_master_key_id == var.kms_key_arn
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
path still passes after someone deletes a `validation` block.

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
