"""Regression tests for the native module documentation contract."""

from pathlib import Path
import tempfile
import unittest

import verify_modules


class PublicSourceContractTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        original_root = verify_modules.ROOT
        verify_modules.ROOT = Path(self.temp.name)
        self.addCleanup(setattr, verify_modules, "ROOT", original_root)
        self.module = verify_modules.ROOT / "modules/aws/network/vpc"
        self.module.mkdir(parents=True)
        (self.module / "versions.tf").write_text(
            'terraform { required_version = ">= 1.9.0" '
            'required_providers { aws = { source = "hashicorp/aws" } } }\n'
        )
        (self.module / "variables.tf").write_text(
            'variable "application" {}\nvariable "environment" {}\n'
        )
        (self.module / "locals.tf").write_text('locals { tags = {} }\n')
        (self.module / "tests").mkdir()
        (self.module / "tests/unit.tftest.hcl").write_text('run "plan" {}\n')

    def findings_for_source(self, source):
        (self.module / "README.md").write_text(
            f'```hcl\nmodule "vpc" {{\n  source = "{source}"\n}}\n```\n'
        )
        return verify_modules.contract_checks(self.module)

    def test_stable_semver_tags_do_not_depend_on_literal_1_0_0(self):
        for tag in ("1.0.0", "1.2.0", "10.3.42", "1.2.0&depth=1", "<version>", "<version>&depth=1"):
            with self.subTest(tag=tag):
                source = (
                    "git::https://github.com/grootan-devops/terraform-modules.git//"
                    f"modules/aws/network/vpc?ref={tag}"
                )
                self.assertEqual(self.findings_for_source(source), [])

    def test_branch_relative_and_wrong_module_sources_fail(self):
        for source in (
            "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/vpc?ref=main",
            "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/vpc?ref=1.2.0-rc1",
            "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/vpc?ref=01.2.0",
            "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/vpc?ref=<tag>",
            "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/alb?ref=1.2.0",
            "./",
        ):
            with self.subTest(source=source):
                findings = self.findings_for_source(source)
                self.assertTrue(any("public Git source pinned" in item for item in findings))

    def test_terraform_floor_is_1_9(self):
        source = (
            "git::https://github.com/grootan-devops/terraform-modules.git//"
            "modules/aws/network/vpc?ref=1.5.0"
        )
        for version, ok in ((">= 1.5.0", False), (">= 1.8.5", False), (">= 1.9.0", True), (">= 1.11.0", True)):
            with self.subTest(version=version):
                (self.module / "versions.tf").write_text(
                    f'terraform {{ required_version = "{version}" '
                    'required_providers { aws = { source = "hashicorp/aws" } } }\n'
                )
                findings = self.findings_for_source(source)
                self.assertEqual(
                    "modules/aws/network/vpc: Terraform >= 1.9.0 contract is missing" in findings,
                    not ok,
                )

    def test_unused_data_source_is_found_outside_data_tf(self):
        (self.module / "iam.tf").write_text('data "aws_caller_identity" "current" {}\n')
        source = (
            "git::https://github.com/grootan-devops/terraform-modules.git//"
            "modules/aws/network/vpc?ref=1.0.0"
        )
        findings = self.findings_for_source(source)
        self.assertTrue(any("unused data source data.aws_caller_identity.current" in item
                            for item in findings))

        (self.module / "locals.tf").write_text(
            'locals { tags = { Account = data.aws_caller_identity.current.account_id } }\n'
        )
        self.assertEqual(self.findings_for_source(source), [])


class ProviderFamilyContractTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        original_root = verify_modules.ROOT
        verify_modules.ROOT = Path(self.temp.name)
        self.addCleanup(setattr, verify_modules, "ROOT", original_root)

    def write_module(self, rel, provider="oneuptime/oneuptime", body="", readme=None):
        module = verify_modules.ROOT / rel
        module.mkdir(parents=True)
        (module / "main.tf").write_text(
            'terraform { required_version = ">= 1.9.0" '
            f'required_providers {{ oneuptime = {{ source = "{provider}" }} }} }}\n{body}'
        )
        if readme is None:
            readme = (
                "git::https://github.com/grootan-devops/terraform-modules.git//"
                f"{rel}?ref=1.5.0\""
            )
        (module / "README.md").write_text(readme)
        (module / "tests").mkdir()
        (module / "tests/unit.tftest.hcl").write_text('run "plan" {}\n')
        return module

    def test_oneuptime_module_uses_label_governance_without_environment(self):
        module = self.write_module(
            "modules/oneuptime",
            body='variable "application" {}\nlocals {}\nresource "oneuptime_label" "this" {}\n',
        )
        self.assertEqual(verify_modules.contract_checks(module), [])

    def test_oneuptime_module_without_its_provider_or_labels_fails(self):
        module = self.write_module(
            "modules/oneuptime",
            provider="hashicorp/aws",
            body='variable "application" {}\nlocals { tags = {} }\nresource "aws_s3_bucket" "this" {}\n',
        )
        findings = verify_modules.contract_checks(module)
        self.assertIn("modules/oneuptime: oneuptime/oneuptime provider contract is missing", findings)
        self.assertIn(
            "modules/oneuptime: local naming/oneuptime_label governance contract is missing", findings
        )

    def test_aws_module_still_requires_environment_and_tags(self):
        module = self.write_module(
            "modules/aws/network/vpc",
            provider="hashicorp/aws",
            body='variable "application" {}\nresource "aws_vpc" "this" {}\n',
        )
        findings = verify_modules.contract_checks(module)
        self.assertIn(
            "modules/aws/network/vpc: required governance variable 'environment' is missing", findings
        )
        self.assertIn(
            "modules/aws/network/vpc: local naming/tags governance contract is missing", findings
        )

    def test_nested_module_skips_parent_governance_and_published_example(self):
        module = self.write_module(
            "modules/oneuptime/modules/alerts",
            body='resource "oneuptime_alert_owner_rule" "this" {}\n',
            readme="# Alerts\n",
        )
        self.assertEqual(verify_modules.contract_checks(module), [])

        (module / "README.md").unlink()
        self.assertEqual(
            verify_modules.contract_checks(module),
            ["modules/oneuptime/modules/alerts: README.md is missing"],
        )

    def test_nested_module_with_resources_still_requires_its_provider(self):
        module = self.write_module(
            "modules/oneuptime/modules/monitors",
            provider="hashicorp/aws",
            body='data "oneuptime_monitor_status" "offline" {}\n'
            'output "id" { value = data.oneuptime_monitor_status.offline.id }\n',
            readme="# Monitors\n",
        )
        self.assertEqual(
            verify_modules.contract_checks(module),
            ["modules/oneuptime/modules/monitors: oneuptime/oneuptime provider contract is missing"],
        )

    def test_resource_free_module_needs_no_provider(self):
        module = verify_modules.ROOT / "modules/oneuptime/modules/workflows-templates/teams"
        module.mkdir(parents=True)
        (module / "versions.tf").write_text('terraform { required_version = ">= 1.9.0" }\n')
        (module / "outputs.tf").write_text('output "workflow_configs" { value = {} }\n')
        (module / "README.md").write_text("# Teams\n")
        (module / "tests").mkdir()
        (module / "tests/unit.tftest.hcl").write_text('run "plan" {}\n')
        self.assertEqual(verify_modules.contract_checks(module), [])

    def test_module_without_a_native_test_suite_fails(self):
        module = self.write_module(
            "modules/oneuptime",
            body='variable "application" {}\nlocals {}\nresource "oneuptime_label" "this" {}\n',
        )
        (module / "tests/unit.tftest.hcl").unlink()
        self.assertEqual(
            verify_modules.contract_checks(module),
            ["modules/oneuptime: tests/*.tftest.hcl is missing"],
        )

        # Suites live in tests/; a file in the module root does not count.
        (module / "unit.tftest.hcl").write_text('run "plan" {}\n')
        self.assertEqual(
            verify_modules.contract_checks(module),
            ["modules/oneuptime: tests/*.tftest.hcl is missing"],
        )

    def test_unknown_provider_family_is_reported(self):
        module = self.write_module("modules/azure/storage/account", provider="hashicorp/azurerm")
        self.assertEqual(
            verify_modules.contract_checks(module),
            ["modules/azure/storage/account: provider family 'azure' has no contract in FAMILIES"],
        )


if __name__ == "__main__":
    unittest.main()
