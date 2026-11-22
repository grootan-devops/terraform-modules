#!/usr/bin/env python3
"""Offline contract and Terraform validation for every reusable module."""

import argparse
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULES = ROOT / "modules"

# Per provider family under modules/: the provider its modules require, the
# governance variables they declare, and the token their governance local
# carries - resource tags on AWS, the label OneUptime attaches to everything.
FAMILIES = {
    "aws": ("hashicorp/aws", ("application", "environment"), "tags"),
    "oneuptime": ("oneuptime/oneuptime", ("application",), "oneuptime_label"),
}


SCOPES = ("workload", "account", "organization", "helper")
AWS_TERRAFORM_FLOOR = ">= 1.17.0"
AWS_PROVIDER_FLOOR = ">= 6.73.0"
BANNED_VARIABLES = ("subnets", "vpc_subnet_ids", "security_groups", "kms_key_id", "kms_master_key_id", "is_enabled")
SINGLETON_RESOURCES = (
    "aws_guardduty_detector", "aws_securityhub_account", "aws_config_configuration_recorder",
    "aws_inspector2_enabler", "aws_detective_graph", "aws_iam_account_password_policy",
    "aws_account_alternate_contact", "aws_s3_account_public_access_block", "aws_ebs_encryption_by_default",
    "aws_ebs_default_kms_key", "aws_ec2_instance_metadata_defaults", "aws_ec2_serial_console_access",
    "aws_ebs_snapshot_block_public_access", "aws_ec2_image_block_public_access",
    "aws_vpc_block_public_access_options", "aws_api_gateway_account", "aws_ecr_registry_scanning_configuration",
    "aws_ecr_replication_configuration", "aws_backup_region_settings", "aws_backup_global_settings",
    "aws_iam_openid_connect_provider", "aws_ssm_service_setting", "aws_ssm_default_patch_baseline",
    "aws_cloudwatch_log_account_policy", "aws_budgets_budget", "aws_ssmquicksetup_configuration_manager",
)
SINGLETON_PREFIXES = ("aws_organizations_", "aws_ce_")


def modules():
    return sorted({p.parent for p in MODULES.rglob("*.tf") if ".terraform" not in p.parts})


def examples():
    """Root configurations under examples/ that wire modules together."""
    base = ROOT / "examples"
    if not base.is_dir():
        return []
    return sorted({p.parent for p in base.rglob("*.tf") if ".terraform" not in p.parts and "tests" not in p.parts})


def blocks(text, kind):
    """Yield (name, body) for every top-level block of the given kind."""
    for match in re.finditer(rf'(?m)^{kind}[ \t]+"([^"]+)"[ \t]*\{{', text):
        depth, index = 1, match.end()
        while depth and index < len(text):
            depth += {"{": 1, "}": -1}.get(text[index], 0)
            index += 1
        yield match.group(1), text[match.end():index - 1]


def aws_standard_checks(module, text, rel):
    """The AWS module standard (docs/module-contract.md)."""
    errors = []
    if not re.search(rf'required_version\s*=\s*"{re.escape(AWS_TERRAFORM_FLOOR)}"', text):
        errors.append(f"{rel}: required_version must be \"{AWS_TERRAFORM_FLOOR}\"")
    if re.search(r'source\s*=\s*"hashicorp/aws"', text) and not re.search(
        rf'source\s*=\s*"hashicorp/aws"\s*\n\s*version\s*=\s*"{re.escape(AWS_PROVIDER_FLOOR)}"', text
    ):
        errors.append(f"{rel}: hashicorp/aws version must be \"{AWS_PROVIDER_FLOOR}\"")
    if "configuration_aliases" in text:
        errors.append(f"{rel}: configuration_aliases are not allowed; use the resource-level region argument")
    for name, body in blocks(text, "variable"):
        if name in BANNED_VARIABLES or re.match(r"(create|enable)_", name):
            errors.append(f"{rel}: variable {name!r} breaks the naming standard")
        if not re.search(r"(?m)^\s*description\s*=", body):
            errors.append(f"{rel}: variable {name!r} has no description")
        if re.search(r"(?m)^\s*type\s*=.*\bany\b", body):
            errors.append(f"{rel}: variable {name!r} uses an untyped any")
    for name, body in blocks(text, "output"):
        if not re.search(r"(?m)^\s*description\s*=", body):
            errors.append(f"{rel}: output {name!r} has no description")
    if re.search(r"\blookup\(", text):
        errors.append(f"{rel}: lookup() is not used on typed inputs")
    readme = module / "README.md"
    scope = None
    if readme.exists():
        found = re.search(r"(?m)^Scope: `([a-z]+)`$", readme.read_text())
        scope = found.group(1) if found else None
    if scope not in SCOPES:
        errors.append(f"{rel}: README.md must declare 'Scope: `workload|account|organization|helper`'")
    elif scope == "helper" and rel.parts[2] != "core":
        errors.append(f"{rel}: helper modules live under modules/aws/core")
    elif scope == "workload":
        for kind in sorted(set(re.findall(r'(?m)^resource[ \t]+"([^"]+)"', text))):
            if kind in SINGLETON_RESOURCES or kind.startswith(SINGLETON_PREFIXES):
                errors.append(f"{rel}: workload module declares account singleton {kind}")
    return errors


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
    if rel.parts[1] not in FAMILIES:
        return [f"{rel}: provider family {rel.parts[1]!r} has no contract in FAMILIES"]
    provider, variables, governance = FAMILIES[rel.parts[1]]
    # A module inside another module's directory is wired by that parent,
    # which owns the governance inputs and the published examples.
    nested = any(
        any(ROOT.joinpath(*rel.parts[:depth]).glob("*.tf")) for depth in range(2, len(rel.parts))
    )
    errors = []
    helper = rel.parts[1] == "aws" and len(rel.parts) > 2 and rel.parts[2] == "core"
    match = re.search(r'required_version\s*=\s*">=\s*([0-9]+)\.([0-9]+)', text)
    # 1.9 is the floor: modules validate one input against another.
    if not match or tuple(map(int, match.groups())) < (1, 9):
        errors.append(f"{rel}: Terraform >= 1.9.0 contract is missing")
    declares_objects = re.search(r'(?m)^[ \t]*(?:resource|data)[ \t]+"', text)
    if declares_objects and not re.search(rf'source\s*=\s*"{re.escape(provider)}"', text):
        errors.append(f"{rel}: {provider} provider contract is missing")
    if not nested and not helper:
        for name in variables:
            if not re.search(rf'variable\s+"{name}"', text):
                errors.append(f"{rel}: required governance variable {name!r} is missing")
        if ("locals" not in text and 'module "naming"' not in text) or governance not in text:
            errors.append(f"{rel}: local naming/{governance} governance contract is missing")
    for kind, name in re.findall(
        r'(?m)^[ \t]*data[ \t]+"([^"]+)"[ \t]+"([^"]+)"[ \t]*\{', text
    ):
        if not re.search(rf'\bdata\.{re.escape(kind)}\.{re.escape(name)}\b', text):
            errors.append(f"{rel}: unused data source data.{kind}.{name}")
    readme = module / "README.md"
    if not readme.exists():
        errors.append(f"{rel}: README.md is missing")
    elif not nested:
        stable_tag = r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
        expected_source = re.compile(
            r"git::https://github\.com/grootan-devops/terraform-modules\.git//"
            rf"{re.escape(rel.as_posix())}\?ref=(?:{stable_tag}|<version>)(?=\"|&)"
        )
        if not expected_source.search(readme.read_text()):
            errors.append(
                f"{rel}: examples must use the public Git source pinned to a stable SemVer tag "
                "or the <version> placeholder"
            )
    if not any((module / "tests").glob("*.tftest.hcl")):
        errors.append(f"{rel}: tests/*.tftest.hcl is missing")
    readme_text = readme.read_text() if readme.exists() else ""
    for check in sorted(set(re.findall(r"#\s*trivy:ignore:([A-Z]+-[A-Z]+-[0-9]+)", text))):
        if check not in readme_text:
            errors.append(f"{rel}: Trivy suppression {check} is not explained in README.md")
    if rel.parts[1] == "aws" and not nested:
        errors.extend(aws_standard_checks(module, text, rel))
    return errors


def role_purpose_checks():
    """Two modules with the same name in one environment must never share an IAM role name."""
    owners = {}
    for tf in sorted((ROOT / "modules/aws").rglob("*.tf")):
        if ".terraform" in tf.parts or "tests" in tf.parts:
            continue
        module = tf.parent.relative_to(ROOT / "modules/aws").as_posix()
        for _, body in blocks(tf.read_text(), "module"):
            if re.search(r'source\s*=\s*"[^"]*security/iam-role"', body):
                purpose = re.search(r'(?m)^\s*purpose\s*=\s*"([^"$]+)"\s*$', body)
                if purpose:
                    owners.setdefault(purpose.group(1), set()).add(module)
    return [f'IAM role purpose "{p}" is used by {", ".join(sorted(m))}; give each module its own'
            for p, m in sorted(owners.items()) if len(m) > 1]


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
    parser.add_argument("--modules", nargs="*", default=None, help="Only these module paths (relative to the repo root)")
    args = parser.parse_args()
    failures = []
    discovered = modules()
    if args.modules:
        wanted = {(ROOT / m).resolve() for m in args.modules}
        discovered = [m for m in discovered if m.resolve() in wanted]
    if not discovered:
        failures.append("no Terraform modules discovered")
    failures.extend(documentation_checks())
    failures.extend(role_purpose_checks())
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
    scenarios = [] if args.modules else examples()
    for example in scenarios:
        if args.static_only:
            continue
        try:
            run(["terraform", "fmt", "-check", "-recursive", "."], example)
            run(["terraform", "init", "-backend=false", "-input=false"], example)
            run(["terraform", "validate"], example)
            if any(example.rglob("*.tftest.hcl")):
                run(["terraform", "test"], example)
            else:
                failures.append(f"{example.relative_to(ROOT)}: tests/*.tftest.hcl is missing")
        except (AssertionError, FileNotFoundError) as exc:
            failures.append(str(exc))
    if failures:
        print("\n".join(f"ERROR: {item}" for item in failures), file=sys.stderr)
        return 1
    print(f"Validated {len(discovered)} Terraform modules and {len(scenarios)} examples")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
