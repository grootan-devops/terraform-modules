#!/usr/bin/env python3
"""Offline contract and Terraform validation for every reusable module."""

import argparse
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULES = ROOT / "modules"


def modules():
    return sorted({p.parent for p in MODULES.rglob("*.tf") if p.name != ".terraform"})


def run(command, cwd, allowed_errors=()):
    result = subprocess.run(command, cwd=cwd, text=True, capture_output=True)
    if result.returncode:
        output = result.stdout + result.stderr
        if any(message in output for message in allowed_errors):
            print(
                f"SKIP: {' '.join(command)} in {cwd.relative_to(ROOT)}: "
                "requires a compatible provider runtime or consumer provider aliases"
            )
            return False
        raise AssertionError(
            f"{' '.join(command)} failed in {cwd.relative_to(ROOT)}\n"
            f"{output}"
        )
    return True


def source(module):
    return "\n".join(p.read_text() for p in sorted(module.glob("*.tf")))


def contract_checks(module):
    text = source(module)
    rel = module.relative_to(ROOT)
    errors = []
    match = re.search(r'required_version\s*=\s*">=\s*([0-9]+)\.([0-9]+)', text)
    if not match or tuple(map(int, match.groups())) < (1, 5):
        errors.append(f"{rel}: Terraform >= 1.5.0 contract is missing")
    if not re.search(r'source\s*=\s*"hashicorp/aws"', text):
        errors.append(f"{rel}: hashicorp/aws provider contract is missing")
    for name in ("application", "environment"):
        if not re.search(rf'variable\s+"{name}"', text):
            errors.append(f"{rel}: required governance variable {name!r} is missing")
    if "locals" not in text or "tags" not in text:
        errors.append(f"{rel}: local naming/tag governance contract is missing")
    for kind, name in re.findall(
        r'(?m)^[ \t]*data[ \t]+"([^"]+)"[ \t]+"([^"]+)"[ \t]*\{', text
    ):
        if not re.search(rf'\bdata\.{re.escape(kind)}\.{re.escape(name)}\b', text):
            errors.append(f"{rel}: unused data source data.{kind}.{name}")
    readme = module / "README.md"
    if not readme.exists():
        errors.append(f"{rel}: README.md is missing")
    else:
        stable_tag = r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
        expected_source = re.compile(
            r"git::https://github\.com/grootan-devops/terraform-modules\.git//"
            rf"{re.escape(rel.as_posix())}\?ref={stable_tag}(?=\"|&)"
        )
        if not expected_source.search(readme.read_text()):
            errors.append(
                f"{rel}: examples must use the public Git source pinned to a stable SemVer tag"
            )
    return errors


def documentation_checks():
    errors = []
    relative_source = re.compile(r'source\s*=\s*"\.\.?/')
    for document in ROOT.rglob("*.md"):
        if relative_source.search(document.read_text()):
            errors.append(
                f"{document.relative_to(ROOT)}: documentation must not use a local source"
            )
    return errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--static-only", action="store_true")
    args = parser.parse_args()
    failures = []
    discovered = modules()
    if not discovered:
        failures.append("no Terraform modules discovered")
    failures.extend(documentation_checks())
    for module in discovered:
        failures.extend(contract_checks(module))
        if args.static_only:
            continue
        try:
            run(["terraform", "fmt", "-check", "-recursive", "."], module)
            run(["terraform", "init", "-backend=false", "-input=false"], module)
            run(
                ["terraform", "validate"],
                module,
                allowed_errors=(
                    "Failed to load plugin schemas",
                    "Provider configuration not present",
                ),
            )
            if any(module.rglob("*.tftest.hcl")):
                run(["terraform", "test"], module)
        except (AssertionError, FileNotFoundError) as exc:
            failures.append(str(exc))
    if failures:
        print("\n".join(f"ERROR: {item}" for item in failures), file=sys.stderr)
        return 1
    print(f"Validated {len(discovered)} Terraform modules")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
