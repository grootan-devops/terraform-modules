"""Every inline scanner suppression is registered, justified and still present in the code."""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTER = ROOT / "docs" / "compliance" / "scanner-suppressions.md"

INLINE = re.compile(
    r"#\s*(checkov:skip=(?P<checkov>CKV2?_[A-Z0-9_]+)|trivy:ignore:(?P<trivy>[A-Za-z0-9-]+)|"
    r"tflint-ignore:\s*(?P<tflint>[a-z0-9_]+))"
)
# Register rows: | `file` | `resource address`[, `another`] | `check id` | reason | justification | remediation |
ROW = re.compile(r"^\|\s*`(?P<file>[^`]+)`\s*\|\s*(?P<resource>`[^|]+`)\s*\|\s*`(?P<check>[^`]+)`\s*\|"
                 r"(?P<reason>[^|]*)\|(?P<justification>[^|]*)\|(?P<remediation>[^|]*)\|\s*$")
BLANKET = [
    re.compile(r"checkov:skip\s*=\s*\*"),
    re.compile(r"trivy:ignore:\*"),
    re.compile(r"tflint-ignore:\s*all"),
]


def inline_suppressions():
    found = set()
    for path in sorted((ROOT / "modules").rglob("*.tf")):
        if ".terraform" in path.parts:
            continue
        for line in path.read_text().splitlines():
            for blanket in BLANKET:
                if blanket.search(line):
                    raise AssertionError(f"{path.relative_to(ROOT)}: blanket suppression is not allowed: {line.strip()}")
            match = INLINE.search(line)
            if match:
                found.add((path.relative_to(ROOT).as_posix(),
                           match.group("checkov") or match.group("trivy") or match.group("tflint")))
    return found


def registered():
    rows = []
    for line in REGISTER.read_text().splitlines():
        match = ROW.match(line)
        if match:
            rows.append({k: v.strip() for k, v in match.groupdict().items()})
    return rows


class ScannerSuppressionTests(unittest.TestCase):
    def test_no_global_skip_configuration(self):
        for name in (".checkov.yaml", ".checkov.yml", ".trivyignore", ".trivyignore.yaml", "ignored-cves.yml"):
            self.assertFalse((ROOT / name).exists(), f"{name} would suppress checks repository-wide")

    def test_every_inline_suppression_is_registered(self):
        rows = {(r["file"], r["check"]) for r in registered()}
        for suppression in sorted(inline_suppressions()):
            with self.subTest(file=suppression[0], check=suppression[1]):
                self.assertIn(suppression, rows, "add a row to docs/compliance/scanner-suppressions.md")

    def test_every_registered_suppression_exists(self):
        inline = inline_suppressions()
        for row in registered():
            with self.subTest(file=row["file"], check=row["check"]):
                self.assertIn((row["file"], row["check"]), inline, "stale register row")

    def test_registered_rows_are_justified(self):
        for row in registered():
            with self.subTest(file=row["file"], check=row["check"]):
                for field in ("resource", "reason", "justification", "remediation"):
                    self.assertGreaterEqual(len(row[field]), 10 if field != "resource" else 3, f"{field} is empty")


if __name__ == "__main__":
    unittest.main()
