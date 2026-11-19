"""The compliance inventory is evidence: every claim must point at code that exists."""

import json
import re
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMPLIANCE = ROOT / "docs" / "compliance"
INVENTORY = COMPLIANCE / "aws-compliance-inventory.json"
CATALOG = COMPLIANCE / "data" / "securityhub-controls.json"

STATUSES = {"PASS", "PARTIAL", "FAIL", "NOT_APPLICABLE", "PROVIDER_MANAGED", "NOT_SUPPORTED", "REQUIRES_RUNTIME_VALIDATION"}
CAPABILITIES = {"required", "recommended", "optional", "provider_managed", "not_supported", "not_applicable"}
AREAS = {
    "encryption_at_rest", "encryption_in_transit", "iam", "network", "public_access", "logging", "log_retention",
    "backup", "deletion_protection", "versioning", "secrets", "monitoring", "tagging", "api_security",
    "terraform_state", "governance", "detection",
}
ENFORCEMENT = {"preventive", "detective", "corrective"}
LAYERS = {"terraform", "organizations", "config", "security_hub", "runtime", "operational"}
REQUIRED_KEYS = {
    "module", "resource_type", "resource_address", "aws_service", "security_area", "implemented", "missing",
    "expected", "capability", "status_before", "status", "enforcement", "enforcement_layer", "controls",
    "framework_refs", "evidence", "remediation",
}
FRAMEWORK_KEYS = {
    "fsbp_v1_0_0", "cis_v5_0_0", "cis_v3_0_0", "cis_v1_4_0", "cis_v1_2_0", "nist_800_53_r5", "nist_800_171_r2",
    "pci_v4_0_1", "pci_v3_2_1", "tagging_v1_0_0", "ai_security_v1_0_0", "cri_profile_v2_2",
}
# Entries outside any module (organization-wide or account-level controls) use this pseudo-module.
ORGANIZATION_SCOPE = "organization"


def composed_source(module, seen=None):
    """Terraform source of a module and every local module it composes."""
    seen = set() if seen is None else seen
    module = module.resolve()
    if module in seen:
        return ""
    seen.add(module)
    text = "\n".join(p.read_text() for p in sorted(module.glob("*.tf")))
    for rel in re.findall(r'(?m)^\s*source\s*=\s*"(\.\.?/[^"]+)"', text):
        text += "\n" + composed_source(module / rel, seen)
    return text


class ComplianceInventoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.inventory = json.loads(INVENTORY.read_text())
        cls.catalog = json.loads(CATALOG.read_text())
        cls.entries = cls.inventory["entries"]

    def test_inventory_is_not_empty(self):
        self.assertGreater(len(self.entries), 0)

    def test_entries_have_the_schema(self):
        for index, entry in enumerate(self.entries):
            with self.subTest(index=index, address=entry.get("resource_address")):
                self.assertEqual(REQUIRED_KEYS - entry.keys(), set(), "missing keys")
                self.assertIn(entry["status"], STATUSES)
                self.assertIn(entry["status_before"], STATUSES)
                self.assertIn(entry["capability"], CAPABILITIES)
                self.assertIn(entry["security_area"], AREAS)
                self.assertIn(entry["enforcement"], ENFORCEMENT)
                self.assertIn(entry["enforcement_layer"], LAYERS)
                self.assertTrue(entry["expected"].strip(), "expected configuration must be stated")
                self.assertEqual(set(entry["framework_refs"]) - FRAMEWORK_KEYS, set(), "unknown framework key")
                if entry["status"] in ("PARTIAL", "FAIL"):
                    self.assertTrue(entry["missing"].strip() or entry["remediation"].strip(),
                                    "a gap must say what is missing or how to remediate it")

    def test_controls_exist_in_the_catalog(self):
        for entry in self.entries:
            for control in entry["controls"]:
                with self.subTest(address=entry["resource_address"], control=control):
                    self.assertIn(control, self.catalog["controls"])

    def test_module_and_resource_type_exist(self):
        for entry in self.entries:
            if entry["module"] == ORGANIZATION_SCOPE:
                continue
            with self.subTest(module=entry["module"], resource=entry["resource_type"]):
                module = ROOT / entry["module"]
                self.assertTrue(module.is_dir(), "module directory is missing")
                source = composed_source(module)
                self.assertRegex(source, rf'(resource|data)\s+"{re.escape(entry["resource_type"])}"')

    def test_evidence_patterns_match(self):
        for entry in self.entries:
            for evidence in entry["evidence"]:
                with self.subTest(address=entry["resource_address"], file=evidence["file"]):
                    path = ROOT / evidence["file"]
                    self.assertTrue(path.is_file(), "evidence file is missing")
                    self.assertRegex(path.read_text(), re.compile(evidence["pattern"], re.M))

    def test_pass_claims_carry_evidence(self):
        for entry in self.entries:
            if entry["status"] == "PASS" and entry["enforcement_layer"] in ("terraform", "organizations", "config"):
                with self.subTest(address=entry["resource_address"], area=entry["security_area"]):
                    self.assertTrue(entry["evidence"], "a PASS enforced in code needs evidence")

    def test_generated_views_are_current(self):
        result = subprocess.run(
            [sys.executable, str(ROOT / "scripts" / "compliance" / "render_compliance.py"), "--check"],
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
