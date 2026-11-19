"""Regression tests for the native module documentation contract."""

from pathlib import Path
import tempfile
import unittest

import verify_modules

AWS_VERSIONS = (
    'terraform {\n  required_version = ">= 1.17.0"\n\n  required_providers {\n    aws = {\n'
    '      source  = "hashicorp/aws"\n      version = ">= 6.73.0"\n    }\n  }\n}\n'
)
AWS_VARIABLES = (
    'variable "application" {\n  description = "Application name."\n  type        = string\n}\n'
    'variable "environment" {\n  description = "Environment name."\n  type        = string\n}\n'
)
SOURCE = "git::https://github.com/grootan-devops/terraform-modules.git//{rel}?ref=<version>"


class PublicSourceContractTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        original_root = verify_modules.ROOT
        verify_modules.ROOT = Path(self.temp.name)
        self.addCleanup(setattr, verify_modules, "ROOT", original_root)
        self.module = verify_modules.ROOT / "modules/aws/network/vpc"
        self.module.mkdir(parents=True)
        (self.module / "versions.tf").write_text(AWS_VERSIONS)
        (self.module / "variables.tf").write_text(AWS_VARIABLES)
        (self.module / "locals.tf").write_text('locals { tags = {} }\n')
        (self.module / "tests").mkdir()
        (self.module / "tests/unit.tftest.hcl").write_text('run "plan" {}\n')

    def findings_for_source(self, source):
        (self.module / "README.md").write_text(
            f'# VPC\n\nScope: `workload`\n\n```hcl\nmodule "vpc" {{\n  source = "{source}"\n}}\n```\n'
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

    def write_parent(self, rel="modules/oneuptime"):
        parent = verify_modules.ROOT / rel
        parent.mkdir(parents=True, exist_ok=True)
        (parent / "main.tf").write_text('module "area" { source = "./area" }\n')

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
        self.write_parent()
        module = self.write_module(
            "modules/oneuptime/alerts",
            body='resource "oneuptime_alert_owner_rule" "this" {}\n',
            readme="# Alerts\n",
        )
        self.assertEqual(verify_modules.contract_checks(module), [])

        (module / "README.md").unlink()
        self.assertEqual(
            verify_modules.contract_checks(module),
            ["modules/oneuptime/alerts: README.md is missing"],
        )

    def test_module_without_a_parent_module_is_not_nested(self):
        module = self.write_module(
            "modules/oneuptime/alerts",
            body='resource "oneuptime_alert_owner_rule" "this" {}\n',
            readme="# Alerts\n",
        )
        self.assertIn(
            "modules/oneuptime/alerts: required governance variable 'application' is missing",
            verify_modules.contract_checks(module),
        )

    def test_nested_module_with_resources_still_requires_its_provider(self):
        self.write_parent()
        module = self.write_module(
            "modules/oneuptime/monitors",
            provider="hashicorp/aws",
            body='data "oneuptime_monitor_status" "offline" {}\n'
            'output "id" { value = data.oneuptime_monitor_status.offline.id }\n',
            readme="# Monitors\n",
        )
        self.assertEqual(
            verify_modules.contract_checks(module),
            ["modules/oneuptime/monitors: oneuptime/oneuptime provider contract is missing"],
        )

    def test_resource_free_module_needs_no_provider(self):
        self.write_parent()
        module = verify_modules.ROOT / "modules/oneuptime/workflows-templates/teams"
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


class AwsStandardTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        original_root = verify_modules.ROOT
        verify_modules.ROOT = Path(self.temp.name)
        self.addCleanup(setattr, verify_modules, "ROOT", original_root)

    def write(self, rel="modules/aws/compute/lambda", scope="workload", body="", versions=AWS_VERSIONS):
        module = verify_modules.ROOT / rel
        module.mkdir(parents=True)
        (module / "versions.tf").write_text(versions)
        (module / "variables.tf").write_text(AWS_VARIABLES)
        (module / "main.tf").write_text('module "naming" {\n  source = "../../core/naming"\n  tags = {}\n}\n' + body)
        readme = f"# Module\n\nScope: `{scope}`\n\n" if scope else "# Module\n\n"
        (module / "README.md").write_text(readme + SOURCE.format(rel=rel) + '"\n')
        (module / "tests").mkdir()
        (module / "tests/unit.tftest.hcl").write_text('run "plan" {}\n')
        return module

    def test_compliant_module_passes(self):
        self.assertEqual(verify_modules.contract_checks(self.write()), [])

    def test_version_floors_are_enforced(self):
        module = self.write(versions='terraform {\n  required_version = ">= 1.9.0"\n  required_providers {\n    aws = {\n      source  = "hashicorp/aws"\n      version = ">= 6.0.0"\n    }\n  }\n}\n')
        findings = verify_modules.contract_checks(module)
        self.assertIn('modules/aws/compute/lambda: required_version must be ">= 1.17.0"', findings)
        self.assertIn('modules/aws/compute/lambda: hashicorp/aws version must be ">= 6.73.0"', findings)

    def test_configuration_aliases_are_rejected(self):
        module = self.write(body="locals { x = \"configuration_aliases\" }\n")
        self.assertTrue(any("configuration_aliases" in f for f in verify_modules.contract_checks(module)))

    def test_banned_and_undescribed_variables(self):
        module = self.write(body=(
            'variable "subnets" {\n  description = "x"\n  type = list(string)\n}\n'
            'variable "create_role" {\n  description = "x"\n  type = bool\n}\n'
            'variable "settings" {\n  type = map(any)\n}\n'
            'output "id" {\n  value = 1\n}\n'
        ))
        findings = verify_modules.contract_checks(module)
        for message in (
            "variable 'subnets' breaks the naming standard",
            "variable 'create_role' breaks the naming standard",
            "variable 'settings' has no description",
            "variable 'settings' uses an untyped any",
            "output 'id' has no description",
        ):
            with self.subTest(message=message):
                self.assertIn(f"modules/aws/compute/lambda: {message}", findings)

    def test_lookup_is_rejected(self):
        module = self.write(body='locals { x = lookup(var.y, "z", 1) }\n')
        self.assertIn("modules/aws/compute/lambda: lookup() is not used on typed inputs", verify_modules.contract_checks(module))

    def test_scope_is_required(self):
        module = self.write(scope=None)
        self.assertTrue(any("must declare 'Scope" in f for f in verify_modules.contract_checks(module)))

    def test_workload_module_cannot_declare_account_singletons(self):
        module = self.write(body='resource "aws_guardduty_detector" "this" {}\nresource "aws_organizations_policy" "this" {}\nresource "aws_ce_anomaly_monitor" "this" {}\nresource "aws_budgets_budget" "this" {}\n')
        findings = verify_modules.contract_checks(module)
        self.assertIn("modules/aws/compute/lambda: workload module declares account singleton aws_guardduty_detector", findings)
        self.assertIn("modules/aws/compute/lambda: workload module declares account singleton aws_organizations_policy", findings)
        self.assertIn("modules/aws/compute/lambda: workload module declares account singleton aws_ce_anomaly_monitor", findings)
        self.assertIn("modules/aws/compute/lambda: workload module declares account singleton aws_budgets_budget", findings)

    def test_account_module_may_declare_singletons(self):
        module = self.write(rel="modules/aws/security/guardduty", scope="account", body='resource "aws_guardduty_detector" "this" {}\n')
        self.assertEqual(verify_modules.contract_checks(module), [])

    def test_helper_scope_only_under_core(self):
        module = self.write(scope="helper")
        self.assertIn("modules/aws/compute/lambda: helper modules live under modules/aws/core", verify_modules.contract_checks(module))

    def test_core_helper_needs_no_governance_variables(self):
        module = verify_modules.ROOT / "modules/aws/core/policy-document"
        module.mkdir(parents=True)
        (module / "versions.tf").write_text('terraform {\n  required_version = ">= 1.17.0"\n}\n')
        (module / "outputs.tf").write_text('output "json" {\n  description = "Policy JSON."\n  value = "{}"\n}\n')
        (module / "README.md").write_text("# Policy\n\nScope: `helper`\n\n" + SOURCE.format(rel="modules/aws/core/policy-document") + '"\n')
        (module / "tests").mkdir()
        (module / "tests/unit.tftest.hcl").write_text('run "plan" {}\n')
        self.assertEqual(verify_modules.contract_checks(module), [])


if __name__ == "__main__":
    unittest.main()
