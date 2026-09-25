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
            'terraform { required_version = ">= 1.5.0" '
            'required_providers { aws = { source = "hashicorp/aws" } } }\n'
        )
        (self.module / "variables.tf").write_text(
            'variable "application" {}\nvariable "environment" {}\n'
        )
        (self.module / "locals.tf").write_text('locals { tags = {} }\n')

    def findings_for_source(self, source):
        (self.module / "README.md").write_text(
            f'```hcl\nmodule "vpc" {{\n  source = "{source}"\n}}\n```\n'
        )
        return verify_modules.contract_checks(self.module)

    def test_stable_semver_tags_do_not_depend_on_literal_1_0_0(self):
        for tag in ("1.0.0", "1.2.0", "10.3.42", "1.2.0&depth=1"):
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
            "git::https://github.com/grootan-devops/terraform-modules.git//modules/aws/network/alb?ref=1.2.0",
            "./",
        ):
            with self.subTest(source=source):
                findings = self.findings_for_source(source)
                self.assertTrue(any("public Git source pinned" in item for item in findings))

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


if __name__ == "__main__":
    unittest.main()
